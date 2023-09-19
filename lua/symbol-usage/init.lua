local u = require('symbol-usage.utils')
local options = require('symbol-usage.options')
local state = require('symbol-usage.state')
local worker = require('symbol-usage.worker')

local group = u.GROUP
local nested = u.NESTED_GROUP

local function clear()
  local bufnr = vim.api.nvim_get_current_buf()
  state.remove_buffer(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, u.NS, 0, -1)
  vim.api.nvim_clear_autocmds({ buffer = bufnr, group = nested })
end

local M = {}

function M.attach()
  vim.api.nvim_create_autocmd({ 'LspAttach' }, {
    group = group,
    callback = function(event)
      local client = vim.lsp.get_client_by_id(event.data.client_id)

      if not (client and u.support_method(client, 'documentSymbol')) then
        return
      end

      local w = worker.new(event.buf, client)
      local need_run = state.add_worker(event.buf, w)
      if need_run then
        w:run(false)
      end

      vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
        buffer = event.buf,
        group = nested,
        nested = true,
        callback = function(e)
          for _, wkr in pairs(state.get(e.buf)) do
            wkr:run(true)
          end
        end,
      })

      if vim.fn.has('nvim-0.10') ~= 0 then
        vim.api.nvim_create_autocmd({ 'LspNotify' }, {
          buffer = event.buf,
          group = nested,
          nested = true,
          callback = function(e)
            if e.event == 'LspNotify' and e.data.method ~= 'textDocument/didOpen' then
              return
            end
            for _, wkr in pairs(state.get(e.buf)) do
              wkr:run(true)
            end
          end,
        })
      end

      -- Force refresh on BufEnter
      vim.api.nvim_create_autocmd('BufEnter', {
        buffer = event.buf,
        group = nested,
        nested = true,
        callback = function(e)
          for _, wkr in pairs(state.get(e.buf)) do
            wkr:run(false)
          end
        end,
      })
    end,
  })

  vim.api.nvim_create_autocmd('LspDetach', {
    group = group,
    callback = function(event)
      -- state.remove_buffer(event.buf)
      -- vim.api.nvim_clear_autocmds({ buffer = event.buf, group = nested })
      clear()
    end,
  })
end

function M.setup(opts)
  options.update(opts or {})
  M.attach()
end

function M.refresh()
  clear()

  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/documentSymbol' })
  for _, client in pairs(clients) do
    local w = worker.new(bufnr, client)
    w:run(false)
  end
end

return M
