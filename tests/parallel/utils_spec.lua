local utils = require('symbol-usage.utils')
local stub = require('luassert.stub')

describe('utils', function()
  describe('support_method', function()
    local client = {
      supports_method = function(method)
        return method == 'textDocument/definition'
      end,
    }

    it('returns true if client supports method', function()
      assert.is_true(utils.support_method(client, 'definition'))
    end)

    it('returns false if client does not support method', function()
      assert.is_false(utils.support_method(client, 'references'))
    end)
  end)

  describe('some', function()
    it('returns true if any item satisfies the condition', function()
      local tbl = { 1, 2, 3, 4, 5 }
      local condition = function(item)
        return item % 2 == 0
      end
      assert.is_true(utils.some(tbl, condition))
    end)

    it('returns false if no item satisfies the condition', function()
      local tbl = { 1, 3, 5, 7, 9 }
      local condition = function(item)
        return item % 2 == 0
      end
      assert.is_false(utils.some(tbl, condition))
    end)
  end)

  describe('every', function()
    it('returns true if all items satisfy the condition', function()
      local tbl = { 2, 4, 6, 8, 10 }
      local condition = function(item)
        return item % 2 == 0
      end
      assert.is_true(utils.every(tbl, condition))
    end)

    it('returns false if any item does not satisfy the condition', function()
      local tbl = { 2, 4, 6, 8, 9 }
      local condition = function(item)
        return item % 2 == 0
      end
      assert.is_false(utils.every(tbl, condition))
    end)
  end)

  describe('sort', function()
    it('returns a sorted copy of the table', function()
      local tbl = { 5, 2, 8, 1, 9 }
      local sorted_tbl = utils.sort(tbl, function(a, b)
        return a < b
      end)
      assert.are_same({ 1, 2, 5, 8, 9 }, sorted_tbl)
    end)
  end)

  describe('get_nested_key_value', function()
    it('returns the value of the target key if found', function()
      local tbl = { a = 1, b = { c = 2, d = 3 } }
      assert.are_same(2, utils.get_nested_key_value(tbl, 'c'))
    end)

    it('returns nil if the target key is not found', function()
      local tbl = { a = 1, b = { c = 2, d = 3 } }
      assert.is_nil(utils.get_nested_key_value(tbl, 'e'))
    end)
  end)

  describe('get_position', function()
    it('returns the position from selectionRange if available', function()
      local symbol = { selectionRange = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 5 } } }
      local position = utils.get_position(symbol)
      assert.are_same({ line = 0, character = 5 }, position)
    end)

    it('returns the position from range if selectionRange is not available', function()
      local symbol = { range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 5 } } }
      local position = utils.get_position(symbol)
      assert.are_same({ line = 0, character = 0 }, position)
    end)

    it('returns nil if neither selectionRange nor range are available', function()
      local symbol = {}
      local position = utils.get_position(symbol)
      assert.is_nil(position)
    end)
  end)

  describe('make_extmark_opts', function()
    it('returns opts for `nvim_buf_set_extmark` with end_of_line position', function()
      local text = { { '1 usage', 'SymbolUsageText' } }
      local opts = utils.make_extmark_opts(text, {
        vt_position = 'end_of_line',
        vt_priority = 100,
      }, 0, 1, 1)
      assert.are_same({
        virt_text_pos = 'eol',
        virt_text = text,
        id = 1,
        hl_mode = 'combine',
        priority = 100,
      }, opts)
    end)

    it('returns opts for `nvim_buf_set_extmark` with signcolumn position', function()
      local text = { { '⚠', 'SymbolUsageText' } }
      local opts = utils.make_extmark_opts(text, { vt_position = 'signcolumn' }, 0, 1, 1)
      assert.are_same({
        sign_text = '⚠',
        sign_hl_group = 'SymbolUsageText',
        id = 1,
        hl_mode = 'combine',
      }, opts)
    end)

    it('returns opts for `nvim_buf_set_extmark` with textwidth position', function()
      local text = { { 'symbol', 'SymbolUsageText' } }
      local nvim_get_option_value_stub = stub(vim.api, 'nvim_get_option_value').returns('80')
      local opts = utils.make_extmark_opts(text, { vt_position = 'textwidth' }, 0, 1, 1)
      assert.are_same({
        virt_text = text,
        virt_text_win_col = 73,
        id = 1,
        hl_mode = 'combine',
      }, opts)
      nvim_get_option_value_stub:revert()
    end)

    it('returns opts for `nvim_buf_set_extmark` with above position', function()
      local text = { { 'no usage', 'SymbolUsageText' } }
      local buffer_lines = { '  function name()end' }
      local buffer_lines_stub = stub(vim.api, 'nvim_buf_get_lines')
      buffer_lines_stub.returns(buffer_lines)
      local opts = utils.make_extmark_opts(text, { vt_position = 'above' }, 0, 1, 1)
      assert.are_same({
        virt_lines = { { { '  ', 'NonText' }, { 'no usage', 'SymbolUsageText' } } },
        virt_lines_above = true,
        id = 1,
        hl_mode = 'combine',
      }, opts)
      buffer_lines_stub:revert()
    end)
  end)

  describe('make_params', function()
    it('returns params for lsp method request', function()
      local symbol = {
        selectionRange = {
          start = { line = 0, character = 0 },
          ['end'] = { line = 0, character = 5 },
        },
      }

      local uri_from_bufnr_stub = stub(vim, 'uri_from_bufnr').returns('file:///path/to/file')

      local params = utils.make_params(symbol, 'references', { references = { include_declaration = true } }, 1)
      assert.are_same({
        position = { line = 0, character = 5 },
        textDocument = { uri = 'file:///path/to/file' },
        context = { includeDeclaration = true },
      }, params)
      uri_from_bufnr_stub:revert()
    end)

    it('returns nil if symbol does not have selectionRange or range', function()
      local symbol = {}
      local params = utils.make_params(symbol, 'references', { references = { include_declaration = true } }, 1)
      assert.is_nil(params)
    end)
  end)
end)
