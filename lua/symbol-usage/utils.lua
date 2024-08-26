local M = {}

M.NS = vim.api.nvim_create_namespace('__symbol__')
M.GROUP = vim.api.nvim_create_augroup('__symbol__', { clear = true })
M.NESTED_GROUP = vim.api.nvim_create_augroup('__symbol_nested__', { clear = true })

M.is_list = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

---Check if client supports method
---@param client vim.lsp.Client
---@param method string
---@return boolean
function M.support_method(client, method)
  return client.supports_method('textDocument/' .. method)
end

function M.some(tbl, cb)
  if not M.is_list(tbl) or vim.tbl_isempty(tbl) then
    return false
  end

  for _, item in ipairs(tbl) do
    if cb(item) then
      return true
    end
  end

  return false
end

function M.every(tbl, cb)
  if not M.is_list(tbl) or vim.tbl_isempty(tbl) then
    return false
  end

  for _, item in ipairs(tbl) do
    if not cb(item) then
      return false
    end
  end

  return true
end

---Get sorted copy of table
---@param tbl table<integer, any>
---@param predicat function(any, any): boolean
---@return table
function M.sort(tbl, predicat)
  local res = vim.deepcopy(tbl)
  table.sort(res, predicat)
  return res
end

---Recursively finding key in table and return its value if found or nil
---@param tbl table|nil Dict-like table
---@param target_key string Name of target key
---@return any|nil
function M.get_nested_key_value(tbl, target_key)
  if not tbl or M.is_list(tbl) then
    return nil
  end
  local found
  for key, val in pairs(tbl) do
    if key == target_key then
      return val
    end
    if type(val) == 'table' and not M.is_list(val) then
      found = M.get_nested_key_value(val, target_key)
    end
    if found then
      return found
    end
  end
  return nil
end

---Get effective position of symbol.
---First, it searches for 'selectionRange' and takes the position of the last letter of the symbol
---name as the position for subsequent queries. If 'selectionRange' is not found, it looks for
---'range' and takes the position of the first letter of the symbol name. If nothing is found, nil
---is returned.
---Explanation: Different clients return symbol data with different structures.
---@param symbol table Item from 'textDocument/documentSymbol' response
---@param opts? UserOpts Lang opts
---@return { line: integer, character: integer }?
function M.get_position(symbol, opts)
  opts = opts or {}
  -- First search 'selectionRange' because it gives range to name the symbol
  local position = M.get_nested_key_value(symbol, 'selectionRange')
  -- If 'selectionRange' is found, use last character of name as point to send request
  local place = opts.symbol_request_pos or 'end'
  if not position then
    -- If 'selectionRange' does not exist, search 'range' (range includes whole body of symbol)
    position = M.get_nested_key_value(symbol, 'range')
    -- For 'range' need to use 'start' range
    place = 'start'
  end

  return position and position[place]
end

---@class MethodParams
---@field position { line: integer, character: integer }
---@field textDocument { uri: string }
---@field context? { includeDeclaration: boolean }

---Make params for lsp method request
---@param symbol table Item from 'textDocument/documentSymbol' response
---@param method Method Method name without 'textDocument/', e.g. 'references'|'definition'|'implementation'
---@param opts UserOpts
---@param bufnr number
---@return MethodParams? returns nil if symbol have not 'selectionRange' or 'range' field
function M.make_params(symbol, method, opts, bufnr)
  local position = M.get_position(symbol, opts)
  if not position then
    return
  end

  local params = { position = position, textDocument = { uri = vim.uri_from_bufnr(bufnr) } }

  if method == 'references' then
    params.context = { includeDeclaration = opts.references.include_declaration }
  end

  return params
end

---Return length of all virtual text
---@param vt table
---@return integer
local function get_vt_length(vt)
  local res = 0
  for _, val in ipairs(vt) do
    -- Need 'strdisplaywidth' for correct counts icon length
    res = res + vim.fn.strdisplaywidth(val[1])
  end
  return res
end

---Make opts for extmark according opts.vt_position
---@param text string|table Virtual text
---@param opts UserOpts
---@param line integer 0-index line number
---@param bufnr integer Buffer id
---@param id integer|nil Extmark id
---@return table Opts for |nvim_buf_set_extmark()|
function M.make_extmark_opts(text, opts, line, bufnr, id)
  local is_tbl = type(text) == 'table'
  local vtext = is_tbl and text or { { text, 'SymbolUsageText' } }

  local modes = {
    end_of_line = function()
      return { virt_text_pos = 'eol', virt_text = vtext }
    end,
    signcolumn = function()
      local sign = vim.fn.strcharpart(vtext[1][1], 0, 2)
      local hl = vtext[1][2]
      return { sign_text = sign, sign_hl_group = hl }
    end,
    textwidth = function()
      local shift = not is_tbl and #text or get_vt_length(vtext --[[@as table]])
      return {
        virt_text = vtext,
        virt_text_win_col = tonumber(vim.api.nvim_get_option_value('textwidth', { buf = bufnr })) - (shift + 1),
      }
    end,
    above = function()
      -- |vim.fn.indent()| is not convenient because it can't be specified for a specific buffer.
      -- Buffer can be another if this function is called
      local ok, l = pcall(vim.api.nvim_buf_get_lines, bufnr, line, line + 1, true)
      local indent = ''
      if ok and l and not vim.tbl_isempty(l) then
        indent = l[1]:match('^(%s*)')
      end
      table.insert(vtext --[[@as table]], 1, { indent, 'NonText' })
      return { virt_lines = { vtext }, virt_lines_above = true }
    end,
  }

  return vim.tbl_extend(
    'force',
    modes[opts.vt_position](),
    { id = id, hl_mode = 'combine', priority = opts.vt_priority }
  )
end

function M.debounce(cb, ms)
  local timer ---@type uv_timer_t?
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
      timer:close()
    end

    timer = vim.defer_fn(function()
      timer = nil
      cb(unpack(args))
    end, ms)
  end
end

return M
