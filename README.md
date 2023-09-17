# symbol-usage.nvim

Plugin to display references, definitions and implementations of document symbols with a view like JetBrains Idea.

<img width="724" alt="Снимок экрана 2023-09-17 в 17 50 35" src="https://github.com/Wansmer/symbol-usage.nvim/assets/46977173/c13fb043-7cd1-47e3-8f20-8853a44c7067">

<img width="715" alt="Снимок экрана 2023-09-17 в 17 51 14" src="https://github.com/Wansmer/symbol-usage.nvim/assets/46977173/d5aeefdb-6147-48a5-9a70-fdfead151635">

<img width="712" alt="Снимок экрана 2023-09-17 в 17 51 47" src="https://github.com/Wansmer/symbol-usage.nvim/assets/46977173/578ab051-fd1f-4f70-98a5-f05307a5fb8b">

## Features

- Shows references, definitions and implementations as virtual text;
- Three options for display virtual text: above the line, end of line or near with colorcolumn;
- Works with Lsp servers even client do not support `textDocument/codeLens` feature;
- Fully customizable: can be customized for different languages or use with default config for all;
- Ignores unnecessary requests to Lsp;

## Installation

With `lazy.nvim`:

```lua
{
  'Wansmer/symbol-usage.nvim',
  event = 'LspAttach',
  config = function()
    require('symbol-usage').setup()
  end
}
```

## Setup

Default options values:

```lua
local SymbolKind = vim.lsp.protocol.SymbolKind

local default_opts = {
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
```

<details>

<summary>see SymbolKind</summary>

From: https://github.com/neovim/neovim/blob/211edceb4f4d4d0f6c41a6ee56891a6f9407e3a7/runtime/lua/vim/lsp/protocol.lua#L119

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

## TODO

- [ ] Different highlighting groups for references, definitions and implementations;
- [ ] Different symbol kinds  for references, definitions and implementations;
- [ ] Custom filter for symbol kinds;
- [ ] First, query the data for the symbols that are currently on the screen;
- [ ] Option to show only on current line;

## Other sources with similar feature

1. Neovim built-in [codeLens](https://github.com/neovim/neovim/blob/211edceb4f4d4d0f6c41a6ee56891a6f9407e3a7/runtime/lua/vim/lsp/codelens.lua): implemented no in all servers;
2. Plugin [lsp-lens.nvim](https://github.com/VidocqH/lsp-lens.nvim): only `above` view;
3. Plugin [nvim-dr-lsp](https://github.com/chrisgrieser/nvim-dr-lsp): shows info in statusline;

## Known issues and restriction

- No shows virtual text above first line ([#16166](https://github.com/neovim/neovim/issues/16166));
- When virtual text ia above, uses `LineNr` instead of `CursorLineNr` for symbol's line even it current line (actual, if you use number with `statuscolumn`);
- Some clients don't recognize anonymous functions and closures like `SymbolKind.Function` (e.g., tsserver, rust-analyzer)
