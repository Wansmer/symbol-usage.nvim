local M = {}

M.NS = vim.api.nvim_create_namespace('__symbol__')
M.GROUP = vim.api.nvim_create_augroup('__symbol__', { clear = true })
M.NESTED_GROUP = vim.api.nvim_create_augroup('__symbol_nested__', { clear = true })

M.is_list = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

---Check if a table contains a value
---@param tbl table
---@param x any
---@return boolean
function M.table_contains(tbl, x)
  local found = false
  for _, v in pairs(tbl) do
    if v == x then
      found = true
    end
  end
  return found
end

---Check if client supports method
---@param client lsp.Client
---@param method string
---@return boolean
function M.support_method(client, method)
  return client.supports_method('textDocument/' .. method)
end

---Make params form 'textDocument/references' request
---@param ref table
---@return table
function M.make_params(ref)
  return {
    context = { includeDeclaration = false },
    position = ref.selectionRange['end'],
    textDocument = { uri = vim.uri_from_bufnr(0) },
  }
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
---@return table?
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
---@param pos VTPosition
---@param line integer 0-index line number
---@param bufnr integer Buffer id
---@param id integer|nil Extmark id
---@return table Opts for |nvim_buf_set_extmark()|
function M.make_extmark_opts(text, pos, line, bufnr, id)
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
      local shift = not is_tbl and #text or get_vt_length(vtext)
      return { virt_text = vtext, virt_text_win_col = tonumber(vim.bo[bufnr].textwidth) - (shift + 1) }
    end,
    above = function()
      -- |vim.fn.indent()| is not convenient because it can't be specified for a specific buffer.
      -- Buffer can be another if this function is called
      local ok, l = pcall(vim.api.nvim_buf_get_lines, bufnr, line, line + 1, true)
      local indent = ''
      if ok and l and not vim.tbl_isempty(l) then
        indent = l[1]:match('^(%s*)')
      end
      vtext[1][1] = indent .. (is_tbl and text[1][1] or text)
      return { virt_lines = { vtext }, virt_lines_above = true }
    end,
  }

  return vim.tbl_extend('force', modes[pos](), { id = id, hl_mode = 'combine' })
end

return M
