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
---@field is_rendered? boolean Is symbol rendered
---@field allowed_methods table<integer, Method> Method to count
---@field raw_symbol table Item from response of `textDocument/documentSymbol`
---@field version? integer LSP version

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
    log.debug('Skip `run`. Reason: no_run = true')
    return
  end

  local is_changed = self.buf_version ~= vim.lsp.util.buf_versions[self.bufnr]

  -- Run `collect_symbols` only if it is a force refresh or the buffer has been changed
  if is_changed or force then
    self.buf_version = vim.lsp.util.buf_versions[self.bufnr]
    log.debug('Run `collect_symbols`. Reason:', { force = force, changed = is_changed, buf_version = self.buf_version })
    self:collect_symbols()
  else
    log.debug('Skip `collect_symbols`. Rerender only')
    self:render_in_viewport(true)
  end
end

---Collect textDocument symbols
function W:collect_symbols()
  local function handler(_, response, ctx)
    if not vim.api.nvim_buf_is_valid(self.bufnr) then
      log.warn('`textDocument/documentSymbol` request was skipped. Reason: buffer is not valid')
      return
    end

    if vim.tbl_isempty(response or {}) then
      log.warn('`textDocument/documentSymbol` request was skipped. Reason: no response')
      -- When the entire buffer content is deleted
      self:delete_outdated_symbols()
      return
    end

    if vim.fn.has('nvim-0.10') ~= 0 then
      if ctx.version ~= vim.lsp.util.buf_versions[self.bufnr] then
        log.warn('`textDocument/documentSymbol` request was skipped. Reason: buffer version is changed during request')
        return
      end
    end

    log.debug('Completed request `textDocument/documentSymbol`')
    self:traversal(response)
  end

  log.debug('Start request `textDocument/documentSymbol`')
  local params = { textDocument = vim.lsp.util.make_text_document_params() }
  self.client.request('textDocument/documentSymbol', params, handler, self.bufnr)
end

---Delete outdated symbols and their marks
function W:delete_outdated_symbols()
  log.debug('Delete outdated symbols')
  for id, rec in pairs(self.symbols) do
    if rec.version ~= self.buf_version then
      pcall(vim.api.nvim_buf_del_extmark, self.bufnr, ns, rec.mark_id)
      self.symbols[id] = nil
    end

    if rec.is_stacked and rec.mark_id then
      pcall(vim.api.nvim_buf_del_extmark, self.bufnr, ns, rec.mark_id)
    end
  end
end

---Count symbols in viewport and render it
---@param check_is_rendered boolean Checks if symbol is already rendered and skips it if `true`. Otherwise, overwrite it with a new value
function W:render_in_viewport(check_is_rendered)
  local win_info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  local top = win_info.topline
  local bot = win_info.botline

  for symbol_id, symbol in pairs(self.symbols) do
    local pos = u.get_position(symbol.raw_symbol, self.opts)
    local need_render = not (check_is_rendered and symbol.is_rendered)

    if need_render and pos and pos.line >= top and pos.line <= bot then
      for _, method in pairs(symbol.allowed_methods) do
        log.debug('Count method', method, symbol_id)
        self:count_method(method, symbol_id, symbol.raw_symbol)
      end
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

  ---@param sorted_symbol_tree table Sorted response of `textDocument/documentSymbol`
  ---@param parent table sorted_symbol_tree item (symbol)
  ---@return table
  local function _walk(sorted_symbol_tree, parent)
    ---@type table<integer, string>
    local booked_lines = {}

    for _, symbol in ipairs(sorted_symbol_tree) do
      if symbol.children and not vim.tbl_isempty(symbol.children) then
        _walk(symbol.children, symbol)
      end

      local pos = u.get_position(symbol, self.opts)
      -- If not `pos`, the following actions are useless
      if not pos then
        goto continue
      end

      local allowed_methods = vim.tbl_filter(function(method)
        return self:is_need_count(symbol, method, parent)
      end, { 'references', 'definition', 'implementation' })

      -- Do not store symbols that do not need to be counted for all methods
      if #allowed_methods == 0 then
        goto continue
      end

      local symbol_id = table.concat({ parent.name or '', symbol.kind, symbol.name, symbol.detail or '' })

      local line_holder_id = booked_lines[pos.line]
      if not line_holder_id then
        booked_lines[pos.line] = symbol_id
      end

      local symbol_data = {
        is_stacked = line_holder_id ~= nil,
        stacked_count = 0,
        stacked_symbols = {},
        is_rendered = false, -- TODO: should I restore it?
        raw_symbol = symbol,
        version = self.buf_version,
        allowed_methods = allowed_methods,
      }

      -- Keep mark_id from previous symbol data if it exists
      symbol_data = vim.tbl_deep_extend('force', self.symbols[symbol_id] or {}, symbol_data)

      -- TODO: should I set pending text here?
      -- Set pending text
      if not (symbol_data.mark_id or symbol_data.is_stacked) and self.opts.request_pending_text then
        symbol_data.mark_id = self:set_extmark(symbol_id, pos.line)
      end

      if symbol_data.is_stacked then
        self.symbols[line_holder_id].stacked_symbols[symbol_id] = symbol_data
        self.symbols[line_holder_id].stacked_count = self.symbols[line_holder_id].stacked_count + 1
      end

      self.symbols[symbol_id] = symbol_data

      ::continue::
    end
  end

  _walk(symbol_tree, {})

  self:render_in_viewport(false)
  self:delete_outdated_symbols()
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
    log.warn('Unsupported method: "' .. method .. '" for "' .. self.client.name .. '"')
    return
  end

  local params = u.make_params(symbol, method, self.opts, self.bufnr)
  if not params then
    log.warn('Failed to make params for method: "' .. method .. '" for "' .. self.client.name .. '"')
    return
  end

  ---@param err lsp.ResponseError
  ---@param response any
  ---@param ctx lsp.HandlerContext
  local function handler(err, response, ctx)
    if err or not vim.api.nvim_buf_is_valid(self.bufnr) then
      log.warn('Failed to count method: "' .. method .. '" for "' .. self.client.name .. '"')
      return
    end

    -- If document was changed, break collecting
    if vim.fn.has('nvim-0.10') ~= 0 then
      if ctx.version ~= vim.lsp.util.buf_versions[self.bufnr] then
        log.info('Buffer version was changed during request')
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

return W
