# The Octolog

Using Github for single sign-on.


## Say What?

We have a bunch of apps deployed on the cloud: Graphite for metrics, Sensu for
checks, Kibana for logging, Vanity for split testing, and a few more.  We wanted
some way to log into each service without having to manage accounts on each and
every server.

We looked at open source SSO protocols like CAS, CoSign and Pubcookie but they
all looked so ... complicated.  Editing XML files?  Setting up CGI scripts?
Building code with Maven?  No thank you.

What if there was an existing service users can authenticate with, and it uses
OAuth so they can authorize individual application, and it has a way of editing
users into roles, so we can manage access by role instead of individual logins? 

Well, everyone on the team uses Github so they're already logged into that site,
and Github supports OAuth 2.0 (the easy OAuth) and its V3 API allows us to check
whether a person belongs to a team.  So all that's left is building a simple
sign-on reverse proxy, and so Octolog was born.


## How Does It Work?

You setup Octolog as reverse proxy in front of your Web application, that same
way you would use Nginx or Apache as reverse proxy, but with less to configure.

Octolog supports HTTP/S 1.1 including wonderful features like streaming, Server
Sent Events and Web Sockets.  Basically anything the wonderful
[node-http-proxy](https://github.com/nodejitsu/node-http-proxy) can do.  And
it's written in Node.js, so expect great performance and as many open
connections as you need.

When a request hits Octolog, it looks for a signed cookie that tells it you're
authenticated and authorized.  If the cookie is not there, it redirects you to
Github and asks you to login there and authorize the application.

Github then redirects back to Octolog, which checks that the token is valid, and
that you're account is listed as one of the authorized logins, or belongs to one
of the authorized teams.

If either checks passes, it sends back a signed cookie with account details and
redirect you to the original request you made.  Since future requests will send
back the same cookie, you are now authorized until the cookie expires.


## As A Proxy

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
    "login": ["assaf"]
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

The configuration options are as follows:

* `port` - The port this proxy is listening on.  Defaults to 80 (HTTP) or 443
  (HTTPS).
* `ssl` - If you want to use SSL (HTTPS), set `ssl.key` and `ssl.cert` to the
  paths of the SSL key and certificate files respectively.
* `ssl.force` - If true, listens on port 80 and redirect all traffic to the
  specified port (default to 443).
* `application` - The URL for the application you're proxying.  Must specify the
  protocol, hostname and port, for example: "http://localhost:3000".
* `protect` - Request paths that require authentication.  Can be a string or an
  array of strings.  If not specified, the default behavior is to protect all
  URLs (same as `["*"]`).
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

When specifying which resources to protect:
- Exact paths are matched against the URL.
- Partial matches are allowed by ending the path with `*`.
- You can require authentication for a path by prefixing it with `+`
- You can ignore authentication for a path by prefixing it with `-`
- The first match takes precedence

For example, to require authentication for all paths except API and home page:

```
"protect": [
  "-/",
  "-/api",
  "*"
]
```


## Using HTTPS

You can tell the proxy to use HTTPS by setting `ssl.cert` and `ssl.key` to the
paths of the SSL certificate and key files respectively.  If unspecified, it
will default to using port 443.

You can also set the `ssl.force` option to true.  This will tell the Octolog to
listen on port 80, but redirect all requests to use HTTPS instead.

For example:

```
{ "application": "https://localhost:3000",
  "protect": [
    "/graphs*",
    "/settings*"
  ],
  "ssl": {
    "cert":   "ssl.cert",
    "key":    "ssl.key",
    "force":  true
  },
  "authorize": {
    "login": ["assaf"]
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


## Connect/Express Middleware

Most of the logic is handled by the `octolog` function which returns a Connect
request handler.   You can use it inside your application instead of a proxy.

For example:

```
octolog = require("octolog")

server.use octolog({
  authorize: {
    logins: "assaf"
  },
  "github": {
    "client_id":      "8fa9b2a82cb28fb664a4",
    "client_secret":  "204093f4739fbe8e9b07cfa16b5cfd70fca5bf66"
  }
});
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

To get users to Github connect, redirect them to `/_octolog/connect`, for example:

```
function login(req, res, next) {
  if (req._user) {
    next();
  } else {
    res.redirect("/_octolog/connect");
  }
}

server.get("/settings", login, function(req, res) {
  ...
})
```

You can also kick, I mean, log them out by redirecting the user to
`_octolog/disconnect`.  Both redirects would take the user back to the URL they
were redirected from.


## License

MIT license.
