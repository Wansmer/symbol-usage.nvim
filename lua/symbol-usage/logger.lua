---@alias LogLevel 'TRACE'|'DEBUG'|'INFO'|'WARN'|'ERROR'
---@alias LogLevelLowercase 'trace'|'debug'|'info'|'warn'|'error'

---@type table<LogLevel, 0|1|2|3|4|5>
local levels = vim.deepcopy(vim.log.levels)

---@class LoggerConfig
---@field enabled boolean
---@field level LogLevel
---@field stdout { enabled: boolean, hl: table<LogLevel, string> }
---@field log_file { enabled: boolean, path: string }
---@field notify { enabled: boolean }
local defaut_config = {
  enabled = false,
  level = 'INFO',
  log_file = {
    enabled = true,
    path = vim.fs.joinpath(vim.fn.stdpath('cache'), 'symbol-usage.log'),
  },
  stdout = {
    enabled = false,
    hl = { TRACE = 'None', DEBUG = 'Debug', INFO = 'DiagnosticHint', WARN = 'WarningMsg', ERROR = 'ErrorMsg' },
  },
  notify = { enabled = false }, -- should be use `vim.notify` or not
}

---@class Logger
---@field config LoggerConfig
---@field [LogLevelLowercase] function(...):void
local Logger = {}
Logger.__index = Logger

---Create new logger
---@param config LoggerConfig?
---@return Logger
function Logger.new(config)
  local logger = setmetatable({
    config = vim.tbl_deep_extend('force', defaut_config, config or {}),
  }, Logger)

  for level, _ in pairs(levels) do
    Logger[level:lower()] = function(...)
      Logger.log(logger, level, ...)
    end
  end

  return logger
end

function Logger._stringify(...)
  local args = { ... }
  local message_to_format = ''
  local function to_string(val)
    return vim.list_contains({ 'string', 'number', 'boolean' }, type(val)) and tostring(val)
      or vim.inspect(val, { indent = '', newline = ' ' })
  end

  if type(args[1]) == 'string' then
    message_to_format = table.remove(args, 1)
    local idx = message_to_format:find('%%%w')
    while idx do
      local arg = to_string(table.remove(args, 1))
      message_to_format = message_to_format:sub(1, idx - 1) .. arg .. message_to_format:sub(idx + 2)
      idx = message_to_format:find('%%%w', idx + 1)
    end
  end

  local res = { message_to_format }
  for _, val in ipairs(args) do
    table.insert(res, to_string(val))
  end
  return table.concat(res, ' ')
end

---Log message according to level
---@param level LogLevel
---@vararg any[]
function Logger:log(level, ...)
  if not self.config.enabled or levels[level] < levels[self.config.level] then
    return
  end

  local timestamp = os.date('%Y-%m-%d %H:%M:%S')
  local msg = string.format('%s [%s] %s', timestamp, level, Logger._stringify(...))

  if self.config.log_file and self.config.log_file.path ~= '' then
    vim.fn.writefile({ msg }, self.config.log_file.path, 'a')
  end

  if self.config.stdout.enabled then
    vim.api.nvim_echo({ { msg, self.config.stdout.hl[level] or 'None' } }, true, {})
  end

  if self.config.notify.enabled then
    vim.notify(msg, levels[level])
  end
end

function Logger:update_config(new_config)
  self.config = vim.tbl_deep_extend('force', self.config, new_config)
end

-- Logger singleton. Will be enabled in `setup()` with `update_config()`
local logger = Logger.new()

return logger
