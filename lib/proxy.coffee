Connect       = require("connect")
File          = require("fs")
HTTP          = require("http")
HTTPS         = require("https")
SPDY          = require("spdy")
QS            = require("querystring")
URL           = require("url")
logger        = require("./logger")
octolog       = require("./octolog")
Util          = require("./util")
{ HttpProxy } = require("http-proxy")

###
var options = {
  https: {
    key: fs.readFileSync('path/to/your/key.pem', 'utf8'),
    cert: fs.readFileSync('path/to/your/cert.pem', 'utf8')
  }
};
###


# These are the HTTP headers we send to the back-end resource when a user it
# authenticated.  The values are the corresponding Github user property.
HEADERS =
  "x-github-login":     "login"
  "x-github-name":      "name"
  "x-github-gravatar":  "gravatar_id"
  "x-github-token":     "token"


# This function returns a function matcher that, when called with a pathname,
# will return true if it matches the argument.
matcher = (match)->
  if match[match.length - 1] == "*"
    match = match.slice(0, match.length - 1)
    return (path)->
      return path.slice(0, match.length) == match
  else
    return (path)->
      return path == match

# This function returns an object consisting of a matcher (property match) and a
# protect flag (property protect) indicating whether or not to protect access to
# the resource.  That matcher is a function called with a pathname and returns
# true or false.
mapPath = (path)->
  if path[0] == "-"
    return { match: matcher(path.slice(1)), protect: false }
  else if path[0] == "+"
    return { match: matcher(path.slice(1)), protect: true }
  else
    return { match: matcher(path), protect: true }


# This function creates and starts up a new HTTP(S) proxy server
proxy = (config)->
  unless config.application
    throw new Error("Expecting application URL (config.application)")

  # The protected resources
  paths = Util.toArray(config.protect || "*").map((p)-> mapPath(p))


  # Logging
  if config.syslog
    logger.add logger.transports.Syslog, config.syslog

  # The reverse proxy
  url = URL.parse(config.application)
  rev_proxy = new HttpProxy(
    target:
      host:   url.hostname
      port:   url.port
      https:  url.protocol == "https:"
  )

  # The Connect server
  # By default listen on port 80, 443 for HTTPS
  port= Util.port(config)
  if config.ssl
    options =
      key:  File.readFileSync(config.ssl.key, "utf8")
      cert: File.readFileSync(config.ssl.cert, "utf8")
      rejectUnauthorized: false
    server= Connect()
    HTTPS.createServer(options, server).listen(port)
    logger.info "server= #{server}"
  else if config.spdy
    options =
      key:  File.readFileSync(config.spdy.key, "utf8")
      cert: File.readFileSync(config.spdy.cert, "utf8")
      ca: File.readFileSync(config.spdy.csr, "utf8")
      rejectUnauthorized: false
    server= Connect()
    SPDY.createServer(options, server).listen(port)
    logger.info "server= #{server}"
  else
    server= Connect()
    HTTP.createServer(options, server).listen(port)
  logger.info "Listening on port #{port}"

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
  server.use octolog(config, logger)


  # Manage paths that require authentication
  server.use (req, res, next)->
    pathname = URL.parse(req.url).pathname
    if user = req._user
      next()
      return

    for path in paths
      # Look for and stop at the first match
      if path.match(pathname)
        if path.protect
          # This path requires authentication
          return_to = Util.url(config, req, URL.parse(req.url, true))
          res.setHeader "Location", Util.url(config, req, pathname: "/_octolog/connect", query: { return_to: return_to })
          res.statusCode = 303 # Follow URL with a GET request
          res.end("You need to login with Github and authorize to access this page")
        else
          # This path does not require authentication, we're all good
          next()
        return

    # We're good
    next()
      

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
    # Support HTTP Basic authentication is specified in the application URL
    if url.auth
      req.headers["Authorization"] = "Basic #{new Buffer(url.auth).toString("base64")}"
    # Forward
    rev_proxy.proxyRequest(req, res)


  server.on "error", (err) ->
   logger.info "server error #{err}"


  # List on port 80 and redirect traffic to HTTPS port
  if config.ssl?.force
    http = HTTP.createServer()
    http.on "request", (req, res)->
      unless req.headers.host
        res.writeHead 400, "Bad Request",
        res.end("Missing Host header")
        return

      { pathname, search } = URL.parse(req.url)
      redirect = URL.format(
        protocol: "https:"
        hostname:  req.headers.host.split(":")[0]
        port:      port
        pathname:  pathname
        search:    search
      )
      res.writeHead 301, "Redirecting",
        "Location": redirect
      res.end()
    http.listen 80, ->
      logger.info "Listening in port 80 and redirecting to #{port}"


  return server


module.exports = proxy
