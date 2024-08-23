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
  enabled = true,
  level = 'DEBUG',
  stdout = {
    enabled = true,
    hl = { TRACE = 'None', DEBUG = 'Debug', INFO = 'DiagnosticHint', WARN = 'WarningMsg', ERROR = 'ErrorMsg' },
  }, -- should log to stdout or not
  log_file = {
    enabled = true,
    path = vim.fs.joinpath(vim.fn.stdpath('cache'), 'symbol-usage.log'),
  },
  notify = { enabled = false }, -- should be use `vim.notify` or not
}

---Log message according to level
---@param Logger Logger
---@param level LogLevel
---@vararg any[]
local function logger(Logger, level, ...)
  if not Logger.config.enabled or levels[level] < levels[Logger.config.level] then
    return
  end

  local timestamp = os.date('%Y-%m-%d %H:%M:%S')
  local msg = string.format('%s [%s] %s', timestamp, level, vim.inspect(...))

  if Logger.config.log_file and Logger.config.log_file.path ~= '' then
    vim.fn.writefile({ timestamp .. ' ' .. msg }, Logger.config.log_file.path, 'a')
  end

  if Logger.config.stdout then
    vim.api.nvim_echo({ { msg, Logger.config.stdout.hl[level] or 'None' } }, true, {})
  end

  if Logger.config.notify then
    vim.notify(msg, levels[level])
  end
end

---@class Logger
---@field config LoggerConfig
---@field [LogLevelLowercase] function(...):void
local M = {}
M.__index = function(self, index)
  local maybe_level = string.upper(index)
  if levels[maybe_level] then
    return function(...)
      return logger(self, maybe_level, ...)
    end
  else
    return self[index]
  end
end

---Create new logger
---@param config LoggerConfig?
---@return Logger
function M.new(config)
  return setmetatable({
    config = vim.tbl_deep_extend('force', defaut_config, config or {}),
  }, M)
end

return M
