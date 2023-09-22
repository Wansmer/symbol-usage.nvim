local u = require('symbol-usage.utils')
local o = require('symbol-usage.options')

local ns = u.NS

---@alias Method 'references'|'definition'|'implementation'

---@class Symbol
---@field mark_id integer Is of extmark
---@field references? integer Count of references
---@field definition? integer Count of definitions
---@field implementation? integer Count of implementations

---@class Worker
---@field bufnr number Buffer id
---@field client lsp.Client
---@field opts UserOpts
---@field symbols table<string, Symbol>
---@field buf_version integer
local W = {}
W.__index = W

---New worker for buffer and client
---@param bufnr integer Buffer id
---@param client lsp.Client
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
---@param check_version? boolean|nil
function W:run(check_version)
  if check_version then
    -- Run only if buffer was changed
    if self.buf_version ~= vim.lsp.util.buf_versions[self.bufnr] then
      self.buf_version = vim.lsp.util.buf_versions[self.bufnr]
      self:collect_symbols()
    end
  else
    -- Force refresh
    self:collect_symbols()
  end
end

---Collect textDocument symbols
function W:collect_symbols()
  local function handler(_, response, ctx)
    if not response or vim.tbl_isempty(response) then
      -- When the entire buffer content is deleted
      self:clear_unused_symbols({})
      return
    end

    if vim.fn.has('nvim-0.10') ~= 0 then
      if ctx.version ~= vim.lsp.util.buf_versions[self.bufnr] then
        return
      end
    end

    local actual = self:traversal(response)
    self:clear_unused_symbols(actual)
  end

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
  end
end

---Check if the current symbol needs to be counted
---@param symbol table
---@param method Method
---@return boolean
function W:is_need_count(symbol, method)
  if not self.opts[method].enabled then
    return false
  end

  local kind = symbol.kind

  local kinds = self.opts[method].kinds or self.opts.kinds
  ---@diagnostic disable-next-line: param-type-mismatch
  return vim.tbl_contains(kinds, kind)
end

---Add empty table to symbol_id in symbols
---@param symbol_id string
---@param pos table
function W:mock_symbol(symbol_id, pos)
  local mock = {}
  if self.opts.request_pending_text then
    -- Book a place for a virtual text
    mock = { mark_id = self:set_extmark(symbol_id, pos.line) }
  end
  self.symbols[symbol_id] = mock
end

---Traverse and collect document symbols
---@param symbol_tree table
---@return table
function W:traversal(symbol_tree)
  local function _walk(data, prefix, actual)
    for _, symbol in ipairs(data) do
      local pos = u.get_position(symbol)
      -- If not `pos`, the following actions are useless
      if pos then
        local symbol_id = table.concat({ prefix, symbol.kind, symbol.name })

        for _, method in ipairs({ 'references', 'definition', 'implementation' }) do
          if self:is_need_count(symbol, method) then
            -- If symbol is new, add mock
            if not self.symbols[symbol_id] then
              self:mock_symbol(symbol_id, pos)
            end

            -- Collect actual symbols to remove irrelevant ones afterwards
            actual[symbol_id] = true

            self:count_method(method, symbol_id, symbol)
          end
        end
      end

      if symbol.children and not vim.tbl_isempty(symbol.children) then
        _walk(symbol.children, symbol.name, actual)
      end
    end

    return actual
  end

  return _walk(symbol_tree, '', {})
end

---Set or update extmark.
---@param symbol_id string Symbol id
---@param line integer 0-index line number
---@param count table<Method, integer>|nil
---@param id integer|nil
---@return integer? Extmark id
function W:set_extmark(symbol_id, line, count, id)
  local text = self.opts.request_pending_text
  if self.symbols[symbol_id] and count then
    count = vim.tbl_deep_extend('force', self.symbols[symbol_id], count)
    text = self.opts.text_format(count)
  end

  if not text then
    return
  end

  local opts = u.make_extmark_opts(text, self.opts.vt_position, line, self.bufnr, id)
  return vim.api.nvim_buf_set_extmark(self.bufnr, ns, line, 0, opts)
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
    if err then
      return
    end

    -- If document was changed, break collecting
    if vim.fn.has('nvim-0.10') ~= 0 then
      if ctx.version ~= vim.lsp.util.buf_versions[self.bufnr] then
        return
      end
    end

    -- Some clients return `nil` if there are no references (e.g. `lua_ls`)
    local count = response and #response or 0
    local record = self.symbols[symbol_id]
    local id

    if record and record.mark_id then
      id = record.mark_id
    end

    id = self:set_extmark(symbol_id, params.position.line, { [method] = count }, id)
    if record and id then
      record.mark_id = id
      record[method] = count
    end
  end

  self.client.request('textDocument/' .. method, params, handler, self.bufnr)
end

---Make params for lsp method request
---@param symbol table
---@param method Method Method name without 'textDocument/', e.g. 'references'|'definition'|'implementation'
---@return table? returns nil if symbol have not 'selectionRange' or 'range' field
function W:make_params(symbol, method)
  local position = u.get_position(symbol)
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
