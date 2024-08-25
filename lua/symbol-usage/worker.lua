local u = require('symbol-usage.utils')
local o = require('symbol-usage.options')
local state = require('symbol-usage.state')
local log = require('symbol-usage.logger')

local ns = u.NS

---@alias Method 'references'|'definition'|'implementation'

---@class Symbol
---@field mark_id? integer Is of extmark
---@field references? integer Count of references
---@field definition? integer Count of definitions
---@field implementation? integer Count of implementations
---@field stacked_count? integer Count of symbols that are on the same line but not displayed
---@field stacked_symbols? table<string, Symbol> Symbols that are on the same line but not displayed
---@field is_stacked? boolean Is symbol on the same line but not displayed
---@field raw_symbol table Item from response of `textDocument/documentSymbol`
---@field is_rendered? boolean Is symbol rendered
---@field allowed_methods table<Method, boolean> Method to count

---@class Worker
---@field bufnr number Buffer id
---@field client vim.lsp.Client
---@field opts UserOpts
---@field symbols table<string, Symbol>
---@field buf_version integer
local W = {}
W.__index = W

---New worker for buffer and client
---@param bufnr integer Buffer id
---@param client vim.lsp.Client
---@return Worker
function W.new(bufnr, client)
  return setmetatable({
    bufnr = bufnr,
    client = client,
    symbols = {},
    opts = o.get_ft_or_default(bufnr),
    buf_version = vim.lsp.util.buf_versions[bufnr],
  }, W)
end

---Run worker for buffer
---@param force? boolean|nil
function W:run(force)
  local no_run = not state.active
    or not vim.api.nvim_buf_is_valid(self.bufnr)
    or vim.tbl_contains(self.opts.disable.lsp, self.client.name)
    or vim.tbl_contains(self.opts.disable.filetypes, vim.bo[self.bufnr].filetype)
    or u.some(self.opts.disable.cond, function(cb)
      return cb(self.bufnr)
    end)

  if no_run then
    return
  end

  local is_changed = self.buf_version ~= vim.lsp.util.buf_versions[self.bufnr]

  -- Run `collect_symbols` only if it is a force refresh or the buffer has been changed
  if is_changed or force then
    self.buf_version = vim.lsp.util.buf_versions[self.bufnr]

    for _, symbol in pairs(self.symbols) do
      symbol.is_stacked = nil
      symbol.is_rendered = false
      symbol.stacked_count = 0
      symbol.stacked_symbols = {}
    end

    log.debug('Run `collect_symbols`. Reason:', { force = force, changed = is_changed, buf_version = self.buf_version })
    self:collect_symbols()
  else
    local win_info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
    local top = win_info.topline
    local bot = win_info.botline

    for symbol_id, symbol in pairs(self.symbols) do
      local pos = u.get_position(symbol.raw_symbol, self.opts)
      if not symbol.is_stacked and not symbol.is_rendered and pos.line >= top and pos.line <= bot then
        for _, method in pairs({ 'references', 'definition', 'implementation' }) do
          log.debug("Render symbol '" .. symbol_id .. "' on '" .. method .. "'" .. ' line: ' .. pos.line)
          if self.symbols[symbol_id].allowed_methods[method] then
            self:count_method(method, symbol_id, symbol.raw_symbol)
          end
        end
      end
    end
  end
end

---Collect textDocument symbols
function W:collect_symbols()
  local function handler(_, response, ctx)
    if not vim.api.nvim_buf_is_valid(self.bufnr) then
      log.warn('`textDocument/documentSymbol` request was skipped. Reason: buffer is not valid')
      return
    end

    if not response or vim.tbl_isempty(response) then
      log.warn('`textDocument/documentSymbol` request was skipped. Reason: no response')
      -- When the entire buffer content is deleted
      self:clear_unused_symbols({})
      return
    end

    if vim.fn.has('nvim-0.10') ~= 0 then
      if ctx.version ~= vim.lsp.util.buf_versions[self.bufnr] then
        log.warn('`textDocument/documentSymbol` request was skipped. Reason: buffer version is changed during request')
        return
      end
    end

    log.debug('Completed request `textDocument/documentSymbol`')

    local actual = self:traversal(response)
    self:clear_unused_symbols(actual)
  end

  log.debug('Start request `textDocument/documentSymbol`')
  local params = { textDocument = vim.lsp.util.make_text_document_params() }
  self.client.request('textDocument/documentSymbol', params, handler, self.bufnr)
end

---Clear symbols that no longer exist
---@param actual_symbols table<string, boolean>
function W:clear_unused_symbols(actual_symbols)
  for id, rec in pairs(self.symbols) do
    if not actual_symbols[id] then
      pcall(vim.api.nvim_buf_del_extmark, self.bufnr, ns, rec.mark_id)
      self.symbols[id] = nil
    end

    if rec.is_stacked then
      pcall(vim.api.nvim_buf_del_extmark, self.bufnr, ns, rec.mark_id)
    end
  end
end

---Check if the current symbol needs to be counted
---@param symbol table
---@param method Method
---@param parent table Uses in kinds_filters
---@return boolean
function W:is_need_count(symbol, method, parent)
  if not (self.opts[method].enabled and u.support_method(self.client, method)) then
    return false
  end

  local kind = symbol.kind

  local kinds = self.opts[method].kinds or self.opts.kinds
  ---@diagnostic disable-next-line: param-type-mismatch
  local matches_kind = vim.tbl_contains(kinds, kind)
  local filters = self.opts.kinds_filter[kind]
  local matches_filter = true
  if (matches_kind and filters) and not vim.tbl_isempty(filters) then
    matches_filter = u.every(filters, function(filter)
      return filter({ symbol = symbol, parent = parent, bufnr = self.bufnr })
    end)
  end

  return matches_kind and matches_filter
end

---Traverse and collect document symbols
---@param symbol_tree table Response of `textDocument/documentSymbol`
---@return table
function W:traversal(symbol_tree)
  -- Sort by line and by position in line
  symbol_tree = u.sort(symbol_tree, function(a, b)
    local pos_a = u.get_position(a, self.opts)
    local pos_b = u.get_position(b, self.opts)
    if not (pos_a and pos_b) then
      return false
    end
    if pos_a.line == pos_b.line then
      return pos_a.character < pos_b.character
    else
      return pos_a.line < pos_b.line
    end
  end)

  ---@type table<Method, table<integer, string>>
  local booked_lines = {
    references = {},
    definition = {},
    implementation = {},
  }

  ---@param sorted_symbol_tree table Sorted response of `textDocument/documentSymbol`
  ---@param parent table sorted_symbol_tree item (symbol)
  ---@param actual table
  ---@return table
  local function _walk(sorted_symbol_tree, parent, actual)
    for _, symbol in ipairs(sorted_symbol_tree) do
      local pos = u.get_position(symbol, self.opts)
      -- If not `pos`, the following actions are useless
      if pos then
        local symbol_id = table.concat({
          parent.name or '',
          symbol.kind,
          symbol.name,
          symbol.detail and symbol.detail or '',
        })

        for _, method in pairs({ 'references', 'definition', 'implementation' }) do
          if self:is_need_count(symbol, method, parent) then
            local mock_data = {
              is_stacked = false,
              stacked_count = 0,
              stacked_symbols = {},
              is_rendered = false,
              raw_symbol = symbol,
              allowed_methods = { [method] = true },
            }

            local line_is_booked = booked_lines[method][pos.line] ~= nil
            if line_is_booked then
              local line_holder_id = booked_lines[method][pos.line]

              -- so that mark_id is not lost if it was set for correct deleting this mark
              local prev_data = self.symbols[symbol_id] or {}
              mock_data.mark_id = prev_data.mark_id
              self.symbols[symbol_id] = vim.tbl_deep_extend('force', mock_data, {
                is_rendered = false,
                is_stacked = true,
                raw_symbol = symbol,
                allowed_methods = { [method] = true },
              })
              self.symbols[line_holder_id].stacked_symbols[symbol_id] = self.symbols[symbol_id]
            else
              booked_lines[method][pos.line] = symbol_id
            end

            if not self.symbols[symbol_id] then
              if self.opts.request_pending_text then
                mock_data.mark_id = self:set_extmark(symbol_id, pos.line)
              end
              self.symbols[symbol_id] = mock_data
            else
              -- Restore symbol for corrent range
              self.symbols[symbol_id].raw_symbol = symbol
            end

            -- Collect actual symbols to remove irrelevant ones afterward
            actual[symbol_id] = symbol
          end
        end
      end

      if symbol.children and not vim.tbl_isempty(symbol.children) then
        _walk(symbol.children, symbol, actual)
      end
    end

    return actual
  end

  local actual = _walk(symbol_tree, {}, {})

  for symbol_id, raw_symbol in pairs(actual) do
    self.symbols[symbol_id].stacked_count = #(vim.tbl_keys(self.symbols[symbol_id].stacked_symbols or {}))
    local pos = u.get_position(raw_symbol, self.opts)
    local win_info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
    local top = win_info.topline
    local bot = win_info.botline

    if pos and pos.line >= top and pos.line <= bot then
      for _, method in pairs({ 'references', 'definition', 'implementation' }) do
        print("Check symbol '" .. symbol_id .. "' on '" .. method .. "'" .. ' line: ' .. pos.line)
        print('Allowed methods: ' .. vim.inspect(self.symbols[symbol_id].allowed_methods))
        if self.symbols[symbol_id].allowed_methods[method] then
          self:count_method(method, symbol_id, raw_symbol)
        end
      end
    end
  end

  return actual
end

---Set or update extmark.
---@param symbol_id string Symbol id
---@param line integer 0-index line number
---@param count table<Method, integer>|nil
---@param id integer|nil
---@return integer? Extmark id
function W:set_extmark(symbol_id, line, count, id)
  -- The buffer can already be removed from the state when the woker finishes. See issue #32
  -- Prevent drawing already unneeded extmarks
  if next(state.get_buf_workers(self.bufnr)) == nil then
    return
  end

  local text = self.opts.request_pending_text
  if self.symbols[symbol_id] and count then
    count = vim.tbl_deep_extend('force', self.symbols[symbol_id], count)
    text = self.opts.text_format(count)
  end

  if not text then
    return
  end

  local opts = u.make_extmark_opts(text, self.opts, line, self.bufnr, id)
  local ok, new_id = pcall(vim.api.nvim_buf_set_extmark, self.bufnr, ns, line, 0, opts)
  return ok and new_id or nil
end

---Count method for symbol
---@param method Method
---@param symbol_id string
function W:count_method(method, symbol_id, symbol)
  if not u.support_method(self.client, method) then
    return
  end

  local params = self:make_params(symbol, method)
  if not params then
    return
  end

  local function handler(err, response, ctx)
    if err or not vim.api.nvim_buf_is_valid(self.bufnr) then
      return
    end

    -- If document was changed, break collecting
    if vim.fn.has('nvim-0.10') ~= 0 then
      if ctx.version ~= vim.lsp.util.buf_versions[self.bufnr] then
        return
      end
    end

    -- Some clients return `nil` if there are no references (e.g., `lua_ls`)
    local count = response and #response or 0
    local record = self.symbols[symbol_id]

    if not record then
      return
    end

    record[method] = count
    if not record.is_stacked then
      record.mark_id = self:set_extmark(symbol_id, params.position.line, { [method] = count }, record.mark_id)
      record.is_rendered = true
    end
  end

  self.client.request('textDocument/' .. method, params, handler, self.bufnr)
end

---Make params for lsp method request
---@param symbol table
---@param method Method Method name without 'textDocument/', e.g. 'references'|'definition'|'implementation'
---@return table? returns nil if symbol have not 'selectionRange' or 'range' field
function W:make_params(symbol, method)
  local position = u.get_position(symbol, self.opts)
  if not position then
    return
  end

  local params = { position = position, textDocument = { uri = vim.uri_from_bufnr(0) } }

  if method == 'references' then
    params.context = { includeDeclaration = self.opts.references.include_declaration }
  end

  return params
end

return W
