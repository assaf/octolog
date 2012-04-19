# Github Connect

Using Github to single sign-on our servers.


## Say What?

We have a bunch of different apps deployed on EC2: Graphite for metrics, Sensu
for health checks, Kibana for logging, Vanity for split testing.  We wanted some
way to manage access control on all of these, without having to manage different
accounts on each service.

It came down to LDAP (yuck) and some SSO protocol like CAS or Webcookies (good?
bad? we never got to find out), or OAuth against some service that allows us to
maintain groups.  Like the group of all people who like to look at pretty
graphs.

Github does OAuth 2.0 (the easy OAuth) and version 3 of their API lets us check
team membership.  Bang.  All we needed is an authorization reverse proxy and so
Github Connect was born.


## As A Proxy

The easiest way to Github Connect your application is by running it as an HTTP/S
reverse proxy.  GHC supports HTTP/S 1.1 including streaming, Server Sent Events
and Web Sockets (basically anything the brilliant
[node-http-proxy](https://github.com/nodejitsu/node-http-proxy) can do).

To run as a proxy, create a configuration file with your Github application
credentials, authorized logins/teams, and the URL of the proxied application.

You can also indicate which URLs require authentication.  If unspecified,
authentication is required for all URLs (essentially `*`).

For example:

```
{ "application": "https://localhost:3000",
  "protect": [
    "/graphs*",
    "/settings*"
  ],
  "authorize": {
    "logins": ["assaf"]
  },
  "github": {
    "client_id":      "8fa9b2a82cb28fb664a4",
    "client_secret":  "204093f4739fbe8e9b07cfa16b5cfd70fca5bf66"
  },
  "cookies": {
    "expires": 60,
    "secret":  "9c7516780b8bc00b523c565bb20980ee0865dcfc"
  }
}
```

If the user authenticates, your application will see the following HTTP headers:

* `X-Github-Login` - The user's login
* `X-Github-Name` - Their full name
* `X-Github-Gravatar` - Their gravatar identifier
* `X-Github-Token` - Their OAuth token


## Configuration

The configuration options are:

* `application` - The URL for the application you're proxying.  Must specify the
  protocol, hostname and port.
* `protect` - Request paths that require authentication.  Can be a string or an
  array of strings.  An empty array is allowed.  However, if not specified, the
  default behavior is to protect all URLs (same as `["*"]`).
* `authorize.logins` - Authorize all users listed by their Github login.  Can be
  string or array of strings.
* `authorize.teams` - Authorize all teams listed by their team identifier.  Can
  be string or array of strings.
* `github.client_id` - The Github application's client identifier.
* `github.client_secret` - The Github application's client secret.
* `cookies.expires` - Sets how long (in minutes) before cookie expires and user has to login
  again.  If missing, cookie expires at the end of the session.
* `cookie.secret` - Secret value used to digitally sign the cookie.  If missing,
  uses a random value that may change when you re-install or upgrade the proxy.

For OAuth to work, you have to [register a Github
application](https://github.com/settings/applications) and use its client ID and
secret in the configuration.

The callback URL must be the same protocol, host and port as the proxy server.
For example, the test application is registered with the callback URL of
`http://localhost:8000`, and so you can only use it when the proxy is running on
localhost port 8000.


## Connect/Express Middleware

Most of the logic is handled by the `ConnectMe` function which returns a Connect
request handler.   You can use it inside your application instead of a proxy.

For example:

```
ConnectMe = require("github-connect")

connect = ConnectMe({
  authorize: {
    logins: "assaf"
  },
  "github": {
    "client_id":      "8fa9b2a82cb28fb664a4",
    "client_secret":  "204093f4739fbe8e9b07cfa16b5cfd70fca5bf66"
  }
})
server.use connect
```

If the user is authenticated, the user object becomes available from the request
property `_user`.  This object provides the Github `login`, full `name`,
`gravatar_id` and OAuth `token`.

For example:

```
<span class="user">
  <a href="https://github.com/<%= @user.login %>">
    <img src="https://secure.gravatar.com/avatar/<%= @user.gravatar_id %>"><%= @user.name %>
  </a>
</span>
```

To get users to Github Connect, redirect them to `/_github/connect`, for example:

```
function login(req, res, next) {
  if (req._user) {
    next();
  } else {
    res.redirect("/_github/connect");
  }
}

server.get("/settings", login, function(req, res) {
  ...
})
```

You can also kick, I mean, log them out by redirecting the user to
`_github/disconnect`.  Both redirects would take the user back to the URL they
were redirected from.


## Other

MIT license.
