Cookies = require("cookies")
Keygrip = require("keygrip")
Request = require("request")
URL     = require("url")
Util    = require("./util")


# The cookie name
COOKIE = "_octolog"
# This path starts the OAuth flow
CONNECT_PATH = "/_octolog/connect"
# This path ends the OAuth flow
CALLBACK_PATH = "/_octolog/callback"
# This path is the equivalent of logout
DISCONNECT_PATH = "/_octolog/disconnect"


# This is where the magic happen.  Given a configuration object, we get back a
# Connect request handler.
octolog = (config, logger)->
  # Validate configuration
  unless config.github.client_id
    throw new Error("OAuth not going to work without github.client_id")
  unless config.github.client_secret
    throw new Error("OAuth not going to work without github.client_secret")

  # Authorize these logins and teams
  logins = Util.toArray(config.authorize.logins)
  teams = Util.toArray(config.authorize.teams)
  unless logins || teams
    throw new Error("You must authorize at least one user or team")

  # We use this to sign the cookies
  keys = Util.toArray(config.cookies?.secret)
  keygrip = new Keygrip(keys)

  if logger
    if logins.length > 0
      logger.info "Authorized access to logins #{logins.join(", ")}"
    if teams.length > 0
      logger.info "Authorized access to teams #{teams.join(", ")}"


  # Success!  Since the user authenticated, we're going to give them the prize
  # cookie and redirect to a better place.
  logIn = (req, res, user)->
    logger.info "Successfully logged in #{user.name} (#{user.login})" if logger
    sendCookie(req, res, user)
    redirect(req, res)


  # Send the user back to where they came from (the return_to query parameter),
  # of back to a safe place (/).
  redirect = (req, res)->
    # All this to get the return_to query parameter
    url = URL.parse(req.url, true)
    return_to = url.query.return_to || Util.url(config, req, pathname: "/")

    res.setHeader "Location", return_to
    res.statusCode = 303 # Follow URL with a GET request
    res.end()


  # Start the OAuth flow
  startFlow = (req, res, next, url)->
    # At the end of the flow, we're going to take the user to the URL
    # specified by the query parameter or where they just came from
    return_to = url.query.return_to || req.headers.referer || "/"
    redirect_uri = Util.url(config, req, pathname: CALLBACK_PATH, query: { return_to: return_to })

    # We need 'repo' scope to list team members
    scope = "repo" if teams.length > 0
    query = { client_id: config.github.client_id, redirect_uri: redirect_uri, scope: scope }
    url = URL.format(protocol: "https", host: "github.com", pathname: "/login/oauth/authorize", query: query)
      
    # This takes us to Github
    res.setHeader "Location", url
    res.statusCode = 303 # Follow URL with a GET request
    res.end("We're sending you to authenticate with Github")


  # Got a response form the OAuth server
  callback = (req, res, next, url)->
    # Let's exchange OAuth code for access token
    request =
      url: "https://github.com/login/oauth/access_token"
      json:
        code:           url.query.code
        client_id:      config.github.client_id
        client_secret:  config.github.client_secret
    Request.post request, (error, response, json)->
      # If we got OAuth error, just show it.
      if json?.error
        error = new Error(json.error)
      if error
        logger.error error if logger
        next(error)
        return

      # We win one OAuth access token
      token = json.access_token
      # Get the login, user name and gravatar ID
      url = "https://api.github.com/user?access_token=#{token}"
      Request.get url, (error, response, body)->
        if error
          logger.error error if logger
          next(error)
          return

        { login, name, gravatar_id } = JSON.parse(body)
        user = # From the response, we only care for these fields
          name:         name
          login:        login
          gravatar_id:  gravatar_id
          token:        token

        if logins.indexOf(login) >= 0
          logger.debug "#{login} is an authorized login" if logger
          # Authorized based on Github login
          logIn(req, res, user)
          return

        checkTeams user, teams, (error, team_id)->
          if team_id
            # Authorized based on Github team membership
            logIn(req, res, user)
          else
            logger.warning "Denied access to #{user.name} (#{user.login})" if logger
            error ||= new Error("Sorry #{name}, you are not authorized to access this application")
            next(error)


  # Check if user is a member of any of the list teams.  If the user is a
  # member, pass the team identifier to the callback.  If the user is not a
  # member of any team, pass null.
  checkTeams = (user, teams, callback)->
    if teams.length == 0
      # No more teams ...
      callback null, null
      return

    # Easiest way to determine if user is member of a team:
    # "In order to list members in a team, the authenticated user must be a member of the team."
    # -- http://developer.github.com/v3/orgs/teams/
    team_id = teams[0]
    url = "https://api.github.com/teams/#{team_id}/members?access_token=#{user.token}"
    Request.get url, (error, response, body)->
      if error
        callback(error)
        return
      if response.statusCode == 200
        try
          members = JSON.parse(body).map((m)-> m.login)
          if members.indexOf(user.login) >= 0
            logger.debug "#{user.login} is a member of team #{team_id}" if logger
            callback null, team_id
            return
        catch error # you can never tell wh
          callback(error)
      # On to the next team
      checkTeams(user, teams.slice(1), callback)


  # Log user out and redirect them to a better place.
  logout = (req, res, next)->
    cookies = new Cookies(req, res, keygrip)
    cookies.set(COOKIE, null)
    redirect(req, res)


  # If authenticated, return user from the cookie (also extends expiration)
  getUser = (req, res)->
    # We're looking for a digitally signed cookie
    cookies = new Cookies(req, res, keygrip)
    cookie = cookies.get(COOKIE, signed: true)
    if cookie
      user = JSON.parse(cookie)
      # And one that has not expired yet
      unless user.expires && new Date(user.expires) < Date.now()
        sendCookie(req, res, user)
        return user


  # Create and send a user cookie
  sendCookie = (req, res, user)->
    cookies = new Cookies(req, res, keygrip)
    # If expiration is set, we tell the cookie when to expire, but also make
    # sure old cookie gets ignored
    if config.cookies?.expires
      expires = Date.now() + config.expires * 60000 # minutes to ms
      user.expires = new Date(expires).toISOString()
    cookies.set COOKIE, JSON.stringify(user), signed: true, expires: expires


  # All the magic happens here
  handler = (req, res, next)->
    url = URL.parse(req.url, true)
    switch url.pathname
      when CONNECT_PATH
        startFlow(req, res, next, url)
      when CALLBACK_PATH
        callback(req, res, next, url)
      when DISCONNECT_PATH
        logout(req, res, next)
      else
        # Any other resource, if we're authenticated make user object available
        # to next handler
        req._user = getUser(req, res)
        # Onwards to the next handler, whatever it be
        next()

  # This function has only one positive outcome
  return handler


module.exports = octolog
