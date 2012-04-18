process.env.NODE_ENV ||= "development"


Connect = require("connect")
Cookies = require("cookies")
QS      = require("querystring")
Keygrip = require("keygrip")
Request = require("request")
URL     = require("url")
logger  = require("./logger")

{ HttpProxy } = require("http-proxy")

###
var options = {
  https: {
    key: fs.readFileSync('path/to/your/key.pem', 'utf8'),
    cert: fs.readFileSync('path/to/your/cert.pem', 'utf8')
  }
};
###


proxy = new HttpProxy(
  target:
    host: "localhost"
    port: 3000
)


# These are the HTTP headers we send to the back-end resource when a user it
# authenticated.  The values are the corresponding Github user property.
HEADERS =
  "x-github-login":     "login"
  "x-github-name":      "name"
  "x-github-gravatar":  "gravatar_id"
  "x-github-token":     "token"

# If set, only authorize members of this team
team_id = process.env.GITHUB_TEAM_ID
# If set, only authorize specified logins
logins = process.env.GITHUB_LOGINS?.split(/,\s*/)


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


keys = null
server.use Cookies.connect(new Keygrip(keys))

# Get user form cookie and set request headers (passed to proxy)
server.use (req, res, next)->
  if cookie = req.cookies.get("user", signed: true)
    req._user = JSON.parse(cookie)
  next()


# OAuth callback
server.use (req, res, next)->
  uri = URL.parse(req.url)
  if uri.pathname == "/oauth/callback"

    query = QS.parse(uri.search.slice(1))
    # Exchange OAuth code for access token
    params =
      url: "https://github.com/login/oauth/access_token"
      json:
        code:           query.code
        client_id:      process.env.GITHUB_CLIENT_ID
        client_secret:  process.env.GITHUB_CLIENT_SECRET
    Request.post params, (error, response, json)->
      return next(error) if error
      # If we got OAuth error, just show it.
      if json && json.error
        logger.warning json.error
        #req.flash "error", json.error
        res.redirect "/"
        return

      # Get the user name and gravatar ID, so we can display those.
      token = json.access_token
      url = "https://api.github.com/user?access_token=#{token}"
      Request.get url, (error, response, body)->
        return next(error) if error
        { login, name, gravatar_id } = JSON.parse(body)
        user = # we only care for these fields
          name:         name
          login:        login
          gravatar_id:  gravatar_id

        if team_id
          # Easiest way to determine if user is member of a team:
          # "In order to list members in a team, the authenticated user must be a member of the team."
          # -- http://developer.github.com/v3/orgs/teams/
          url = "https://api.github.com/teams/#{team_id}/members?access_token=#{token}"
          Request.get url, (error, response, body)->
            return next(error) if error
            if response.statusCode == 200
              members = JSON.parse(body).map((m)-> m.login)
            if members && members.indexOf(login) >= 0
              log_in(user)
            else
              fail(user)
        else if logins
          # Authorization based on Github login
          if logins.indexOf(login) >= 0
            log_in(user)
          else
            fail(user)
        else
          # Default is to deny all
          fail(user)

    log_in = (user)->
      logger.info "#{user.login} logged in successfully"
      logger.debug "Logged in", user
      # Set the user cookie for the session
      res._user = user
      res.cookies.set "user", JSON.stringify(user), signed: true
      # We use this to redirect back to where we came from
      res.setHeader "Location", query.return_to || "/"
      res.statusCode = 303
      res.end("Redirecting you back to application")

    fail = (user)->
      logger.warning "Access denied for", user
      req.flash "error", "You are not authorized to access this application"
      # Can't redirect back to protected resource, only place to go is home
      res.redirect "/"
  else
    next()


# Protect resource by requiring authentication
server.use (req, res, next)->
  if req._user
    next()
  else
    # Pass return_to parameter to callback
    redirect_uri = "http://#{req.headers.host}/oauth/callback?return_to=#{req.url}"
    logger.info redirect_uri
    # You need 'repo' scope to list team members
    scope = "repo" if team_id
    url = "https://github.com/login/oauth/authorize?" +
      QS.stringify(client_id: process.env.GITHUB_CLIENT_ID, redirect_uri: redirect_uri, scope: scope)
    # This takes us to Github
    res.setHeader "Location", url
    res.statusCode = 303 # Follow URL with a GET request
    res.end("Authentication required, you are being redirected")


# Proxy request to back-end application
server.use (req, res)->
  if user = req._user
    # Send all headers corresponding to user object
    for header, prop of HEADERS
      req.headers[header] = user[prop]
  else
    # Make sure these headers are not filled up by client
    for header of req.headers
      if /^x-github/i.test(header)
        delete req.headers[header]
  # Forward
  proxy.proxyRequest(req, res)


server.listen 8000
