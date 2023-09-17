local M = {}

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

return M
