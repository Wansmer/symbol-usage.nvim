# symbol-usage.nvim

Plugin to display references, definitions, and implementations of document symbols with a view like JetBrains Idea.

<!--toc:start-->

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Setup](#setup)
- [Format text examples](#format-text-examples)
- [Filtering kinds](#filtering-kinds)
- [API](#api)
- [TODO](#todo)
- [Other sources with similar feature](#other-sources-with-similar-feature)
- [Known issues and restriction](#known-issues-and-restriction)
<!--toc:end-->

<img width="724" alt="Снимок экрана 2023-09-17 в 17 50 35" src="https://github.com/Wansmer/symbol-usage.nvim/assets/46977173/c13fb043-7cd1-47e3-8f20-8853a44c7067">

<img width="715" alt="Снимок экрана 2023-09-17 в 17 51 14" src="https://github.com/Wansmer/symbol-usage.nvim/assets/46977173/d5aeefdb-6147-48a5-9a70-fdfead151635">

<img width="712" alt="Снимок экрана 2023-09-17 в 17 51 47" src="https://github.com/Wansmer/symbol-usage.nvim/assets/46977173/578ab051-fd1f-4f70-98a5-f05307a5fb8b">

## Features

- Shows references, definitions, and implementations as virtual text;
- Three options for display virtual text: above the line, end of line or near with textwidth;
- Works with LSP servers even client do not support `textDocument/codeLens` feature;
- Fully customizable: can be customized for different languages or use with default config for all;
- Ignores unnecessary requests to LSP;

## Requirements

Neovim >= 0.9.0

## Installation

With `lazy.nvim`:

```lua
{
  'Wansmer/symbol-usage.nvim',
  event = 'BufReadPre', -- need run before LspAttach if you use nvim 0.9. On 0.10 use 'LspAttach'
  config = function()
    require('symbol-usage').setup()
  end
}
```

## Setup

Default options values:

```lua
local SymbolKind = vim.lsp.protocol.SymbolKind

---@type UserOpts
require('symbol-usage').setup({
  ---@type table<string, any> `nvim_set_hl`-like options for highlight virtual text
  hl = { link = 'Comment' },
  ---@type lsp.SymbolKind[] Symbol kinds what need to be count (see `lsp.SymbolKind`)
  kinds = { SymbolKind.Function, SymbolKind.Method },
  ---Additional filter for kinds. Recommended use in the filetypes override table.
  ---fiterKind: function(data: { symbol:table, parent:table, bufnr:integer }): boolean
  ---`symbol` and `parent` is an item from `textDocument/documentSymbol` request
  ---See: #filter-kinds
  ---@type table<lsp.SymbolKind, filterKind[]>
  kinds_filter = {},
  ---@type 'above'|'end_of_line'|'textwidth'|'signcolumn' `above` by default
  vt_position = 'above',
  vt_priority = nil, ---@type integer Virtual text priority (see `nvim_buf_set_extmark`)
  ---Text to display when request is pending. If `false`, extmark will not be
  ---created until the request is finished. Recommended to use with `above`
  ---vt_position to avoid "jumping lines".
  ---@type string|table|false
  request_pending_text = 'loading...',
  ---The function can return a string to which the highlighting group from `opts.hl` is applied.
  ---Alternatively, it can return a table of tuples of the form `{ { text, hl_group }, ... }`` - in this case the specified groups will be applied.
  ---If `vt_position` is 'signcolumn', then only a 1-2 length string or a `{{ icon, hl_group }}` table is expected.
  ---See `#format-text-examples`
  ---@type function(symbol: Symbol): string|table Symbol{ definition = integer|nil, implementation = integer|nil, references = integer|nil, stacked_count = integer, stacked_symbols = table<SymbolId, Symbol> }
  -- text_format = function(symbol) end,
  references = { enabled = true, include_declaration = false },
  definition = { enabled = false },
  implementation = { enabled = false },
  ---@type { lsp?: string[], filetypes?: string[], cond?: function[] } Disables `symbol-usage.nvim' for specific LSPs, filetypes, or on custom conditions.
  ---The function in the `cond` list takes an argument `bufnr` and returns a boolean. If it returns true, `symbol-usage` will not run in that buffer.
  disable = { lsp = {}, filetypes = {}, cond = {} },
  ---@type UserOpts[] See default overridings in `lua/symbol-usage/langs.lua`
  -- filetypes = {},
  ---@type 'start'|'end' At which position of `symbol.selectionRange` the request to the lsp server should start. Default is `end` (try changing it to `start` if the symbol counting is not correct).
  symbol_request_pos = 'end', -- Recommended redefine only in `filetypes` override table
  ---@type LoggerConfig
  log = { enabled = false },
})
```

<details>

<summary>see SymbolKind</summary>

From [LSP spec](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#symbolKind):

```lua
SymbolKind = {
  File = 1,
  Module = 2,
  Namespace = 3,
  Package = 4,
  Class = 5,
  Method = 6,
  Property = 7,
  Field = 8,
  Constructor = 9,
  Enum = 10,
  Interface = 11,
  Function = 12,
  Variable = 13,
  Constant = 14,
  String = 15,
  Number = 16,
  Boolean = 17,
  Array = 18,
  Object = 19,
  Key = 20,
  Null = 21,
  EnumMember = 22,
  Struct = 23,
  Event = 24,
  Operator = 25,
  TypeParameter = 26,
}
```

</details>

## Format text examples

### Plain text

<img width="535" alt="Снимок экрана 2023-10-13 в 02 57 45" src="https://github.com/Wansmer/symbol-usage.nvim/assets/46977173/230520c5-5ab2-4192-b31e-d7b9024b8733">

<details>

<summary>Implementation</summary>

```lua
local function text_format(symbol)
  local fragments = {}

  -- Indicator that shows if there are any other symbols in the same line
  local stacked_functions = symbol.stacked_count > 0
      and (' | +%s'):format(symbol.stacked_count)
      or ''

  if symbol.references then
    local usage = symbol.references <= 1 and 'usage' or 'usages'
    local num = symbol.references == 0 and 'no' or symbol.references
    table.insert(fragments, ('%s %s'):format(num, usage))
  end

  if symbol.definition then
    table.insert(fragments, symbol.definition .. ' defs')
  end

  if symbol.implementation then
    table.insert(fragments, symbol.implementation .. ' impls')
  end

  return table.concat(fragments, ', ') .. stacked_functions
end

require('symbol-usage').setup({
  text_format = text_format,
})
```

</details>

### Bubbles

<img width="534" alt="Снимок экрана 2023-10-13 в 02 08 52" src="https://github.com/Wansmer/symbol-usage.nvim/assets/46977173/3d5860a9-8dc7-44ce-a373-5baab1761ab2">

<details>

<summary>Implementation</summary>

```lua
local function h(name) return vim.api.nvim_get_hl(0, { name = name }) end

-- hl-groups can have any name
vim.api.nvim_set_hl(0, 'SymbolUsageRounding', { fg = h('CursorLine').bg, italic = true })
vim.api.nvim_set_hl(0, 'SymbolUsageContent', { bg = h('CursorLine').bg, fg = h('Comment').fg, italic = true })
vim.api.nvim_set_hl(0, 'SymbolUsageRef', { fg = h('Function').fg, bg = h('CursorLine').bg, italic = true })
vim.api.nvim_set_hl(0, 'SymbolUsageDef', { fg = h('Type').fg, bg = h('CursorLine').bg, italic = true })
vim.api.nvim_set_hl(0, 'SymbolUsageImpl', { fg = h('@keyword').fg, bg = h('CursorLine').bg, italic = true })

local function text_format(symbol)
  local res = {}

  local round_start = { '', 'SymbolUsageRounding' }
  local round_end = { '', 'SymbolUsageRounding' }

  -- Indicator that shows if there are any other symbols in the same line
  local stacked_functions_content = symbol.stacked_count > 0
      and ("+%s"):format(symbol.stacked_count)
      or ''

  if symbol.references then
    local usage = symbol.references <= 1 and 'usage' or 'usages'
    local num = symbol.references == 0 and 'no' or symbol.references
    table.insert(res, round_start)
    table.insert(res, { '󰌹 ', 'SymbolUsageRef' })
    table.insert(res, { ('%s %s'):format(num, usage), 'SymbolUsageContent' })
    table.insert(res, round_end)
  end

  if symbol.definition then
    if #res > 0 then
      table.insert(res, { ' ', 'NonText' })
    end
    table.insert(res, round_start)
    table.insert(res, { '󰳽 ', 'SymbolUsageDef' })
    table.insert(res, { symbol.definition .. ' defs', 'SymbolUsageContent' })
    table.insert(res, round_end)
  end

  if symbol.implementation then
    if #res > 0 then
      table.insert(res, { ' ', 'NonText' })
    end
    table.insert(res, round_start)
    table.insert(res, { '󰡱 ', 'SymbolUsageImpl' })
    table.insert(res, { symbol.implementation .. ' impls', 'SymbolUsageContent' })
    table.insert(res, round_end)
  end

  if stacked_functions_content ~= '' then
    if #res > 0 then
      table.insert(res, { ' ', 'NonText' })
    end
    table.insert(res, round_start)
    table.insert(res, { ' ', 'SymbolUsageImpl' })
    table.insert(res, { stacked_functions_content, 'SymbolUsageContent' })
    table.insert(res, round_end)
  end

  return res
end

require('symbol-usage').setup({
  text_format = text_format,
})
```

</details>

### Labels

<img width="528" alt="Снимок экрана 2023-10-13 в 02 52 00" src="https://github.com/Wansmer/symbol-usage.nvim/assets/46977173/cdc11cca-fc99-4cfb-a1f7-9ae4d1aaf8e8">

<details>

<summary>Implementation</summary>

```lua
local function h(name) return vim.api.nvim_get_hl(0, { name = name }) end

vim.api.nvim_set_hl(0, 'SymbolUsageRef', { bg = h('Type').fg, fg = h('Normal').bg, bold = true })
vim.api.nvim_set_hl(0, 'SymbolUsageRefRound', { fg = h('Type').fg })

vim.api.nvim_set_hl(0, 'SymbolUsageDef', { bg = h('Function').fg, fg = h('Normal').bg, bold = true })
vim.api.nvim_set_hl(0, 'SymbolUsageDefRound', { fg = h('Function').fg })

vim.api.nvim_set_hl(0, 'SymbolUsageImpl', { bg = h('@parameter').fg, fg = h('Normal').bg, bold = true })
vim.api.nvim_set_hl(0, 'SymbolUsageImplRound', { fg = h('@parameter').fg })

local function text_format(symbol)
  local res = {}

  -- Indicator that shows if there are any other symbols in the same line
  local stacked_functions_content = symbol.stacked_count > 0
      and ("+%s"):format(symbol.stacked_count)
      or ''

  if symbol.references then
    table.insert(res, { '󰍞', 'SymbolUsageRefRound' })
    table.insert(res, { '󰌹 ' .. tostring(symbol.references), 'SymbolUsageRef' })
    table.insert(res, { '󰍟', 'SymbolUsageRefRound' })
  end

  if symbol.definition then
    if #res > 0 then
      table.insert(res, { ' ', 'NonText' })
    end
    table.insert(res, { '󰍞', 'SymbolUsageDefRound' })
    table.insert(res, { '󰳽 ' .. tostring(symbol.definition), 'SymbolUsageDef' })
    table.insert(res, { '󰍟', 'SymbolUsageDefRound' })
  end

  if symbol.implementation then
    if #res > 0 then
      table.insert(res, { ' ', 'NonText' })
    end
    table.insert(res, { '󰍞', 'SymbolUsageImplRound' })
    table.insert(res, { '󰡱 ' .. tostring(symbol.implementation), 'SymbolUsageImpl' })
    table.insert(res, { '󰍟', 'SymbolUsageImplRound' })
  end

  if stacked_functions_content ~= '' then
    if #res > 0 then
      table.insert(res, { ' ', 'NonText' })
    end
    table.insert(res, { '󰍞', 'SymbolUsageImplRound' })
    table.insert(res, { ' ' .. tostring(stacked_functions_content), 'SymbolUsageImpl' })
    table.insert(res, { '󰍟', 'SymbolUsageImplRound' })
  end

  return res
end

require('symbol-usage').setup({
  text_format = text_format,
})
```

</details>

## Filtering kinds

Each LSP server processes requests and returns results differently. Therefore, it is impossible to set general settings that are completely suitable for every programming language.

For example, in `javascript` arrow functions are not defined as `SymbolKind.Function`, but as `SymbolKind.Variable` or `SymbolKind.Constant`.

I would like to know how many times an arrow function is used, but keeping track of all variables is not informative.
For this purpose, you can define additional filters that will check that the variable contains exactly the function and not some other value.

You can see implementation examples [here](lua/symbol-usage/langs.lua).

## API

Setup `symbol-usage`:

```lua
---Setup `symbol-usage`
---@param opts UserOpts
require('symbol-usage').setup(opts)
```

Toggle virtual text for current buffer:

```lua
require('symbol-usage').toggle()
```

Toggle virtual text for all buffers:

> After re-enabling, the virtual text will appear after `BufEnter`

```lua
---@return boolean True if active, false otherwise
require('symbol-usage').toggle_globally()
```

Refresh current buffer:

```lua
require('symbol-usage').refresh()
```

## TODO

- [x] Custom filter for symbol kinds;
- [x] Different highlighting groups for references, definitions, and implementations;
- [ ] Different symbol kinds for references, definitions, and implementations;
- [ ] First, query the data for the symbols that are currently on the screen;
- [ ] Option to show only on current line;

## Other sources with similar feature

1. Neovim built-in [codeLens](https://github.com/neovim/neovim/blob/211edceb4f4d4d0f6c41a6ee56891a6f9407e3a7/runtime/lua/vim/lsp/codelens.lua): implemented no in all servers;
2. Plugin [lsp-lens.nvim](https://github.com/VidocqH/lsp-lens.nvim): only `above` view;
3. Plugin [nvim-dr-lsp](https://github.com/chrisgrieser/nvim-dr-lsp): shows info in statusline;

## Known issues and restriction

- No shows virtual text above first line ([#16166](https://github.com/neovim/neovim/issues/16166));
- When virtual text ia above, uses `LineNr` instead of `CursorLineNr` for symbol's line even it current line (actual, if you use number with `statuscolumn`) (UPD: fixed at [#25277](https://github.com/neovim/neovim/pull/25277));
- Some clients don't recognize anonymous functions and closures like `SymbolKind.Function` (e.g., tsserver, rust-analyzer)
