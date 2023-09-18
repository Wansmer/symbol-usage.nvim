local u = require('symbol-usage.utils')
local options = require('symbol-usage.options')
local state = require('symbol-usage.state')
local worker = require('symbol-usage.worker')

local group = vim.api.nvim_create_augroup('__symbol__', { clear = true })
local nested = vim.api.nvim_create_augroup('__symbol_nested__', { clear = true })

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
            wkr:run(false, e.event)
          end
        end,
      })
    end,
  })

  vim.api.nvim_create_autocmd('LspDetach', {
    group = group,
    callback = function(event)
      state.remove_buffer(event.buf)
      vim.api.nvim_clear_autocmds({ buffer = event.buf, group = nested })
    end,
  })
end

function M.setup(opts)
  options.update(opts or {})
  M.attach()
end

return M
