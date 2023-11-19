local u = require('symbol-usage.utils')
local options = require('symbol-usage.options')
local state = require('symbol-usage.state')
local buf = require('symbol-usage.buf')

local M = {}

---Setup `symbol-usage`
---@param opts UserOpts
function M.setup(opts)
  options.update(opts or {})

  vim.api.nvim_create_autocmd({ 'LspAttach' }, {
    group = u.GROUP,
    callback = function(event)
      buf.attach_buffer(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd('LspDetach', {
    group = u.GROUP,
    callback = function(event)
      buf.clear_buffer(event.buf)
    end,
  })
end

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  if state.get_buf_workers(bufnr) then
    buf.clear_buffer(bufnr)
  else
    buf.attach_buffer(bufnr)
  end
end

function M.refresh()
  local bufnr = vim.api.nvim_get_current_buf()
  buf.clear_buffer(bufnr)
  buf.attach_buffer(bufnr)
end

return M
