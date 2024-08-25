local h = require('tests.helpers')

describe('`symbol-usage`', function()
  local su = require('symbol-usage')
  su.setup()
  local opts = require('symbol-usage.options').opts

  local VH = 19 -- tty viewport height with nvim --headles

  vim.cmd.edit('./tests/sample/init.lua')
  local bufnr = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  -- Give the lua_ls the time
  vim.wait(1500, function() end)

  it('buffer is attached', function()
    local worker = require('symbol-usage.state').get_buf_workers(bufnr)[1]
    assert.equal(worker.bufnr, bufnr)
  end)

  it('`lua_ls` is a client in the worker', function()
    local worker = require('symbol-usage.state').get_buf_workers(bufnr)[1]
    assert.equal('lua_ls', worker.client.name)
  end)

  it('found 8 convenient symbols to counting', function()
    local worker = require('symbol-usage.state').get_buf_workers(bufnr)[1]

    assert.equal(8, vim.tbl_count(worker.symbols))
  end)

  it('expected extmarks in the viewport were set with correct counting', function()
    local expected = {
      { line = 2, text = '1 usage' },
      { line = 6, text = '2 usages' },
      { line = 7, text = '  1 usage' },
      { line = 11, text = 'no usage | +2' },
    }
    local result = h.get_extmarks(bufnr, 0, VH)
    assert.are.same(expected, result)
  end)

  it('expected extmarks outside the viewport were set with `pending` text', function()
    local pending = opts.request_pending_text
    local expected = { { line = 20, text = pending }, { line = 21, text = '  ' .. pending } }

    local lines_count = vim.api.nvim_buf_line_count(bufnr)
    local result = h.get_extmarks(bufnr, VH, lines_count)

    assert.are.same(expected, result)
  end)

  it('extmarks outside of the viewport were counted after entering the viewport', function()
    vim.api.nvim_win_set_cursor(win, { 22, 0 }) -- to move viewport

    -- I don't know why 'WinScrolled' is not triggered, so I restart worker manually
    local worker = require('symbol-usage.state').get_buf_workers(bufnr)[1]
    worker:run(false)

    -- Give the lua_ls the time
    vim.wait(300, function() end)

    local expected = { { line = 20, text = '1 usage' }, { line = 21, text = '  no usage' } }
    local lines_count = vim.api.nvim_buf_line_count(bufnr)
    local result = h.get_extmarks(bufnr, VH, lines_count)

    assert.are.same(expected, result)
  end)

  it('update symbols list after buffer change', function()
    local added_lines = 3
    local expected = vim
      .iter({ 2, 6, 7, 11, 11, 11, 20, 21 }) -- original symbol's lines
      :map(function(line)
        return line + added_lines
      end)
      :totable()

    vim.api.nvim_buf_set_lines(bufnr, 0, 0, true, { '', '', '' })

    local worker = require('symbol-usage.state').get_buf_workers(bufnr)[1]
    worker:run(true)

    -- Give the lua_ls the time
    vim.wait(300, function() end)

    local result = vim.iter(worker.symbols):fold({}, function(acc, _, symbol)
      table.insert(acc, symbol.raw_symbol.range.start.line)
      return acc
    end)

    table.sort(result)

    assert.are.same(expected, result)
  end)

  it('clear all extmarks if symbols were deleted', function()
    -- remove all symbols
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { '' })
    local worker = require('symbol-usage.state').get_buf_workers(bufnr)[1]
    worker:run(true)

    vim.wait(300, function() end)

    local NS = require('symbol-usage.utils').NS
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, { 0, 0 }, { -1, -1 }, { details = true })

    assert.are.same({}, marks)
  end)
end)
