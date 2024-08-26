local spy = require('luassert.spy')
local stub = require('luassert.stub')
local match = require('luassert.match')
local logger = require('symbol-usage.logger')

describe('logger', function()
  before_each(function()
    logger:update_config({
      enabled = true,
      level = 'DEBUG',
      log_file = {
        enabled = false,
        path = '',
      },
      stdout = {
        enabled = false,
        hl = {},
      },
      notify = {
        enabled = false,
      },
    })
  end)

  describe('update_config', function()
    it('updates config', function()
      logger:update_config({
        stdout = { enabled = true },
      })
      assert.equal(true, logger.config.stdout.enabled)
    end)
  end)

  describe('_stringify', function()
    it('formats string with placeholders', function()
      local msg = logger._stringify('Hello, %s! You are %d years old.', 'John', 30)
      assert.equal('Hello, John! You are 30 years old.', msg)
    end)

    it('concatenates arguments', function()
      local msg = logger._stringify('Hello', 'World', 1, 2, true)
      assert.equal('Hello World 1 2 true', msg)
    end)

    it('inspects non-string/number arguments', function()
      local tbl = { a = 1, b = 2 }
      local msg = logger._stringify('Table:', tbl)
      assert.equal('Table: { a = 1, b = 2 }', msg)
    end)

    it('correct conversion to a string with all argument types', function()
      local msg = logger._stringify('%s %s', 'one:', { one = 'one' }, 'two', 3)
      assert.equal('one: { one = "one" } two 3', msg)
    end)
  end)

  describe('log', function()
    it('logs message to stdout', function()
      logger:update_config({
        stdout = { enabled = true },
      })
      local stdout_spy = spy.on(vim.api, 'nvim_echo')
      logger:log('INFO', 'Hello, world!')
      assert.spy(stdout_spy).was_called()
    end)

    it('logs message to log file', function()
      local writefile_stub = stub(vim.fn, 'writefile').returns(0)
      local writefile_stub_spy = spy.on(vim.fn, 'writefile')
      logger:update_config({
        log_file = {
          enabled = true,
          path = 'test.log',
        },
      })
      logger:log('DEBUG', 'Debug message')
      assert.spy(writefile_stub_spy).was_called()
      writefile_stub:revert()
    end)

    it('logs message to notify', function()
      local notify_spy = spy.on(vim, 'notify')
      logger:update_config({
        notify = { enabled = true },
      })
      logger:log('WARN', 'Warning message')
      assert.spy(notify_spy).was_called()
      assert.spy(notify_spy).was_called_with(match.is_string(), vim.log.levels.WARN)
    end)

    it('respects log level', function()
      logger:update_config({
        level = 'DEBUG',
        stdout = { enabled = true },
      })
      local stdout_spy = spy.on(vim.api, 'nvim_echo')
      logger:log('TRACE', 'Trace message')
      logger:log('DEBUG', 'Debug message')
      logger:log('INFO', 'Info message')
      assert.spy(stdout_spy).was_called(2)
    end)
  end)
end)
