local u = require('symbol-usage.utils')

local M = {}

function M.get_extmarks(bufnr, from, to)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, u.NS, { from, 0 }, { to, 0 }, { details = true })
  return vim
    .iter(marks)
    :map(function(v)
      local virt_text = unpack(v[4].virt_lines)
      return {
        line = v[2],
        text = vim.iter(virt_text):fold('', function(acc, group)
          return acc .. group[1]
        end),
      }
    end)
    :totable()
end

return M
