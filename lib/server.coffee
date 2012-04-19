process.env.NODE_ENV ||= "development"


Connect       = require("connect")
Cookies       = require("cookies")
File          = require("fs")
QS            = require("querystring")
Keygrip       = require("keygrip")
Request       = require("request")
URL           = require("url")
logger        = require("./logger")
octolog       = require("./octolog")
{ HttpProxy } = require("http-proxy")

###
var options = {
  https: {
    key: fs.readFileSync('path/to/your/key.pem', 'utf8'),
    cert: fs.readFileSync('path/to/your/cert.pem', 'utf8')
  }
};
###


config = JSON.parse(File.readFileSync(process.argv[2], "utf-8"))


# These are the HTTP headers we send to the back-end resource when a user it
# authenticated.  The values are the corresponding Github user property.
HEADERS =
  "x-github-login":     "login"
  "x-github-name":      "name"
  "x-github-gravatar":  "gravatar_id"
  "x-github-token":     "token"


# The reverse proxy
url = URL.parse(config.application)
proxy = new HttpProxy(
  target:
    host:   url.hostname
    port:   url.port
    https:  url.protocol == "https:"
)

# The Web server
server = Connect.createServer()


# Log all requests.
server.use (req, res, next)->
  start = Date.now()
  end_fn = res.end
  res.end = ->
    remote_addr = req.socket && (req.socket.remoteAddress || (req.socket.socket && req.socket.socket.remoteAddress))
    ua = req.headers["user-agent"] || "-"
    logger.info "#{remote_addr} - \"#{req.method} #{req.originalUrl} HTTP/#{req.httpVersionMajor}.#{req.httpVersionMinor}\" #{res.statusCode} \"#{ua}\" - #{Date.now() - start} ms"
    res.end = end_fn
    end_fn.apply(res, arguments)
  next()


# Authentication, authorization and all that jazz
config.logger = logger
server.use octolog(config)


# Proxy request to back-end application
server.use (req, res)->
  if user = req._user
    # Send all headers corresponding to user object
    for header, prop of HEADERS
      req.headers[header] = user[prop]
  else
    # Make sure these headers are not filled up by client and proxied
    for header of req.headers
      if /^x-github/i.test(header)
        delete req.headers[header]
  # Forward
  proxy.proxyRequest(req, res)


server.listen 8000
