local SymbolKind = vim.lsp.protocol.SymbolKind

---@class ReferencesOpts
---@field enabled boolean
---@field include_declaration? boolean Add number of declaration to count of usage

---@class DefinitionOpts
---@field enabled boolean

---@class ImplementationOpts
---@field enabled boolean

---@alias Formater function(symbol: Symbol): string
---@alias VTPosition 'above'|'end_of_line'|'textwidth'

---User options to `symbol-usage.nvim`
---@class UserOpts
---@field hl? table<string, any> `nvim_set_hl`-like options for highlight virtual text
---@field kinds? lsp.SymbolKind[] Symbol kinds what need to be count (see `lsp.SymbolKind`)
---@field text_format? Formater Function to format virtual text
---@field references? ReferencesOpts Opts for references
---@field definition? DefinitionOpts Opts for definitions
---@field implementation? ImplementationOpts Opts for implementations
---@field vt_position? VTPosition Virtual text position (`above` by default)
---@field filetypes UserOpts[] To override opts for specific filetypes. Missing field came from common opts

local S = {}

---@type UserOpts
S._default_opts = {
  hl = { link = 'Comment' },
  kinds = { SymbolKind.Function, SymbolKind.Method },
  vt_position = 'above',
  text_format = function(symbol)
    -- keep it first `nil` for correct concat
    local refs, defs, impls

    if symbol.references then
      local usage = symbol.references <= 1 and 'usage' or 'usages'
      local num = symbol.references == 0 and 'no' or symbol.references
      refs = ('%s %s'):format(num, usage)
    end

    if symbol.definition then
      defs = symbol.definition .. ' defs'
    end

    if symbol.implementation then
      impls = symbol.implementation .. ' impls'
    end

    return table.concat({ refs, defs, impls }, ', ')
  end,
  references = { enabled = true, include_declaration = false },
  definition = { enabled = false },
  implementation = { enabled = false },
  filetypes = {},
}

S.opts = {}

function S.update(user_opts)
  -- To avoid mergins with link
  local hl = user_opts.hl
  S.opts = vim.tbl_deep_extend('force', S._default_opts, user_opts)
  if not hl then
    hl = S.opts.hl
  end
  vim.api.nvim_set_hl(0, 'SymbolUsageText', hl)
end

---Get opts for filetype if exists or return default options
---@param bufnr integer Buffer id
---@return UserOpts
function S.get_ft_or_default(bufnr)
  local ft = vim.api.nvim_buf_get_option(bufnr, 'filetype')

  return vim.tbl_deep_extend('force', S.opts, S.opts.filetypes[ft] or {})
end

return S
