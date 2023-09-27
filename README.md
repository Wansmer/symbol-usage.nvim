# symbol-usage.nvim

Plugin to display references, definitions, and implementations of document symbols with a view like JetBrains Idea.

<!--toc:start-->

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Setup](#setup)
- [Filter kinds](#filtering-kinds)
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
local default_opts = {
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
  ---@type 'above'|'end_of_line'|'textwidth' above by default
  vt_position = 'above',
  ---Text to display when request is pending. If `false`, extmark will not be
  ---created until the request is finished. Recommended to use with `above`
  ---vt_position to avoid "jumping lines".
  ---@type string|false
  request_pending_text = 'loading...',
  ---@type function(symbol: Symbol): string Symbol{ definition = integer|nil, implementation = integer|nil, references = integer|nil }
  text_format = function(symbol)
    local fragments = {}

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

    return table.concat(fragments, ', ')
  end,
  references = { enabled = true, include_declaration = false },
  definition = { enabled = false },
  implementation = { enabled = false },
  ---@type UserOpts[] See default overridings in `lua/symbol-usage/langs.lua`
  -- filetypes = {},
}
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

## Filtering kinds

Each LSP server processes requests and returns results differently. Therefore, it is impossible to set general settings that are completely suitable for every programming language.

For example, in `javascipt` arrow functions are not defined as `SymbolKind.Function`, but as `SymbolKind.Variable` or `SymbolKind.Constant`.

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

Refresh current buffer:

```lua
require('symbol-usage').refresh()
```

## TODO

- [x] Custom filter for symbol kinds;
- [ ] Different highlighting groups for references, definitions, and implementations;
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
