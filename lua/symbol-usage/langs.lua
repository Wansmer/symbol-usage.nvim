local SymbolKind = vim.lsp.protocol.SymbolKind

---Checs if ts attached to buffer
---@param bufnr integer Buffer id
---@return boolean
local function is_ts(bufnr)
  local ok, _ = pcall(vim.treesitter.get_parser, bufnr)
  return ok
end

local filter_js_vars = {
  function(data)
    local symbol, _, bufnr = data.symbol, data.parent, data.bufnr
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      return
    end
    if is_ts(bufnr) then
      local pos = { symbol.range.start.line, symbol.range.start.character }
      -- Treesitter may still lose buffer context
      local ok, node = pcall(vim.treesitter.get_node, { bufrn = bufnr, pos = pos })
      if (ok and node) and node:type() == 'identifier' and node:parent():type() == 'variable_declarator' then
        local value = node:parent():field('value')[1]
        return vim.tbl_contains({ 'arrow_function', 'function' }, value and value:type() or '')
      end
      return false
    else
      -- Fallback to check if treesitter is not attached
      local ln = symbol.range.start.line
      local text = vim.api.nvim_buf_get_lines(bufnr, ln, ln + 1, true)[1] or ''
      return text:find('function') or text:find('=>')
    end
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
          -- Its name will be something like "[1]".
          local symbol = data.symbol
          if symbol.name:match('%[%d%]') then
            return false
          end
          return true
        end,
        function(data)
          -- Looks like in `lua_ls`, anonymous arguments are prefixed with `->` in the
          -- `detail` field. The anonymous function itself can be passed as an argument. Or it
          -- can be assigned to an anonymous table field. So we check both the function and
          -- the parent.
          local details = { data.symbol.detail, data.parent.detail }
          for _, detail in ipairs(details) do
            if detail and vim.startswith(detail, '->') then
              return false
            end
          end

          -- If anonymous table with function is returned (e.g., lazy plugin spec)
          if
            data.parent.detail and (vim.startswith(data.parent.detail, '{') and vim.endswith(data.parent.detail, '}'))
          then
            return false
          end
          return true
        end,
        function(data)
          -- If the function returns an anonymous function, the name of the anonymous function is
          -- defined as `return`
          return data.symbol.name ~= 'return'
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
