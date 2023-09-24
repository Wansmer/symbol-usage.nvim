local SymbolKind = vim.lsp.protocol.SymbolKind

local filter_js_vars = {
  function(data)
    local symbol, _, bufnr = data.symbol, data.parent, data.bufnr
    local ln = symbol.range.start.line
    local text = vim.api.nvim_buf_get_lines(bufnr, ln, ln + 1, true)[1]
    if text:find('function') or text:find('=>') then
      return true
    end
    return false
  end,
}

local javascript = {
  kinds = {
    SymbolKind.Function,
    SymbolKind.Method,
    SymbolKind.Variable,
    SymbolKind.Constant,
  },
  kinds_filter = {
    [SymbolKind.Variable] = filter_js_vars,
    [SymbolKind.Constant] = filter_js_vars,
    [SymbolKind.Function] = {
      function(data)
        -- If an anonymous function has been passed as an argument, its name contains `() callback` in it
        if data.symbol.name:find('() callback') then
          return false
        end
        return true
      end,
    },
  },
}

return {
  lua = {
    kinds_filter = {
      [SymbolKind.Function] = {
        function(data)
          -- If function is inside a list-like table, its usage will always be 0.
          -- It's useless and doesn't need to be counted.
          -- It's name will be something like "[1]".
          local symbol = data.symbol
          if symbol.name:match('%[%d%]') then
            return false
          end
          return true
        end,
        function(data)
          -- It looks like in lua_ls, anonymous arguments are prefixed with `->` in the
          -- `detail` field. The anonymous function itself can be passed as an argument. Or it
          -- can be assigned to an anonymous table field. So we check both the function and
          -- the parent.
          local details = { data.symbol.detail, data.parent.detail }
          for _, detail in ipairs(details) do
            if detail and vim.startswith(detail, '->') then
              return false
            end
          end

          -- If anonymous table with function is returned (e.g. lazy plugin spec)
          if data.parent.detail and (vim.startswith(data.parent.detail, '{') and vim.endswith(data.parent.detail, '}')) then
            return false
          end
          return true
        end,
      },
    },
  },
  vue = javascript,
  javascript = javascript,
  typescript = javascript,
  typescriptreact = javascript,
  javascriptreact = javascript,
}
