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

return M
