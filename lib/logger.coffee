# Logging.  Exports the application's default logger.
#
# The logger supports the logging methods debug, info, warning, error and alert.


Path    = require("path")
Winston = require("winston")
TTY     = require("tty")
# Vendor Winston Syslog handler with a patch
# require "../vendor/winston-syslog"


# Use syslog logging levels.
Winston.setLevels Winston.config.syslog.levels

# Use debug level in development or when DEBUG environment variable is set.
if process.env.DEBUG
  level = "debug"
else
  level = "info"
colorize = TTY.isatty(process.stdout.fd)


# Log to file based on the current environment.
Winston.remove Winston.transports.Console
Winston.add Winston.transports.Console, level: level, colorize: colorize


module.exports = Winston
