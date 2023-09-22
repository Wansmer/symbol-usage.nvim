local M = {}

M.NS = vim.api.nvim_create_namespace('__symbol__')
M.GROUP = vim.api.nvim_create_augroup('__symbol__', { clear = true })
M.NESTED_GROUP = vim.api.nvim_create_augroup('__symbol_nested__', { clear = true })

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
  if not vim.tbl_islist(tbl) or vim.tbl_isempty(tbl) then
    return false
  end

  for _, item in ipairs(tbl) do
    if cb(item) then
      return true
    end
  end

  return false
end

---Recursively finding key in table and return its value if found or nil
---@param tbl table|nil Dict-like table
---@param target_key string Name of target key
---@return any|nil
function M.get_nested_key_value(tbl, target_key)
  if not tbl or vim.tbl_islist(tbl) then
    return nil
  end
  local found
  for key, val in pairs(tbl) do
    if key == target_key then
      return val
    end
    if type(val) == 'table' and not vim.tbl_islist(val) then
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
---@return table?
function M.get_position(symbol)
  -- First search 'selectionRange' because it gives range to name the symbol
  local position = M.get_nested_key_value(symbol, 'selectionRange')
  -- If 'selectionRange' is found, use last character of name as point to send request
  local place = 'end'
  if not position then
    -- If 'selectionRange' does not exist, search 'range' (range includes whole body of symbol)
    position = M.get_nested_key_value(symbol, 'range')
    -- For 'range' need to use 'start' range
    place = 'start'
  end

  return position and position[place]
end

---Make opts for extmark according opts.vt_position
---@param text string Virtual text
---@param pos VTPosition
---@param line integer 0-index line number
---@param bufnr integer Buffer id
---@param id integer|nil Extmark id
---@return table Opts for |nvim_buf_set_extmark()|
function M.make_extmark_opts(text, pos, line, bufnr, id)
  local vtext = { { text, 'SymbolUsageText' } }

  local modes = {
    end_of_line = function()
      return { virt_text_pos = 'eol', virt_text = vtext }
    end,
    textwidth = function()
      return { virt_text = vtext, virt_text_win_col = tonumber(vim.bo[bufnr].textwidth) - (#text + 1) }
    end,
    above = function()
      -- |vim.fn.indent()| is not convenient because it can't be specified for a specific buffer.
      -- Buffer can be another if this function is called
      local ok, l = pcall(vim.api.nvim_buf_get_lines, bufnr, line, line + 1, true)
      local indent = ''
      if ok then
        indent = l[1]:match('^(%s*)')
      end
      vtext[1][1] = indent .. text
      return { virt_lines = { vtext }, virt_lines_above = true }
    end,
  }

  return vim.tbl_extend('force', modes[pos](), { id = id, hl_mode = 'combine' })
end

return M
