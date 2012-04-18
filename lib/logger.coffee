# Logging.  Exports the application's default logger.
#
# The logger supports the logging methods debug, info, warning, error and alert.


Path    = require("path")
Winston = require("winston")
TTY     = require("tty")
# Vendor Winston Syslog handler with a patch
# require "../vendor/winston-syslog"


node_env = process.env.NODE_ENV.toLowerCase()
debug = !!process.env.DEBUG
colorize = TTY.isatty(process.stdout.fd)

# Use syslog logging levels.
Winston.setLevels Winston.config.syslog.levels

# Use debug level in development or when DEBUG environment variable is set.
if node_env == "development" || debug
  level = "debug"
else
  level = "info"


# Log to file based on the current environment.
filename = Path.resolve(__dirname, "../log/#{node_env}.log")
Winston.remove Winston.transports.Console
Winston.add Winston.transports.File,
  filename:   filename
  level:      level
  json:       false
  timestamp:  true


# Log to console in development, and in test when DEBUG environment variable is
# set.  Use Syslog in production, if configured.
switch node_env
  when "development"
    # Log to file and console.
    Winston.add Winston.transports.Console, level: level, colorize: colorize
  when "test"
    # Log to console only when running with DEBUG
    if debug
      Winston.add Winston.transports.Console, level: level, colorize: colorize
  when "production"
    if process.env.SYSLOG_HOST
      # Use Syslog
      Winston.add Winston.transports.Syslog,
        host: process.env.SYSLOG_HOST
        port: parseInt(process.env.SYSLOG_PORT, 10) || 514


module.exports = Winston
