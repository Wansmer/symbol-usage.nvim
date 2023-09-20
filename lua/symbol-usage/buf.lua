local u = require('symbol-usage.utils')
local state = require('symbol-usage.state')
local worker = require('symbol-usage.worker')

local M = {}

---Set nested autocmd for buffer
---@param bufnr integer Buffer id
function M.set_buf_autocmd(bufnr)
  local opts = function(check_version)
    return {
      buffer = bufnr,
      group = u.NESTED_GROUP,
      nested = true,
      callback = function(e)
        for _, wkr in pairs(state.get(e.buf)) do
          wkr:run(check_version)
        end
      end,
    }
  end

  vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, opts(true))
  -- Force refresh on BufEnter because the symbol usage data may have changed in other buffers
  vim.api.nvim_create_autocmd('BufEnter', opts(false))

  if vim.fn.has('nvim-0.10') ~= 0 then
    local o = opts(true)
    o.callback = function(e)
      if e.data.method == 'textDocument/didOpen' then
        for _, wkr in pairs(state.get(e.buf)) do
          wkr:run(true)
        end
      end
    end
    vim.api.nvim_create_autocmd({ 'LspNotify' }, o)
  end
end

---Delete all related `symbol-usage` info for buffer
---@param bufnr integer Buffer id
function M.clear_buffer(bufnr)
  state.remove_buffer(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, u.NS, 0, -1)
  vim.api.nvim_clear_autocmds({ buffer = bufnr, group = u.NESTED_GROUP })
end

---Attach workers for buffer
---@param bufnr integer Buffer id
function M.attach_buffer(bufnr)
  local clients = {}
  if vim.fn.has('nvim-0.10') == 1 then
    clients = vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/documentSymbol' })
  else
    clients = vim.tbl_filter(function(c)
      return u.support_method(c, 'documentSymbol')
    end, vim.lsp.get_active_clients({ bufnr = bufnr }))
  end

  if vim.tbl_isempty(clients) then
    return
  end

  for _, client in pairs(clients) do
    local w = worker.new(bufnr, client)
    -- false if worker with this client for buffer already exists
    local need_run = state.add_worker(bufnr, w)
    if need_run then
      w:run(false)
    end
  end

  M.set_buf_autocmd(bufnr)
end

return M
