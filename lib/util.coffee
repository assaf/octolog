URL = require("url")


Util =
  # Given configuration object, return suitable port number for the proxy.
  port: (config)->
    port = config.port
    port ||= 443 if config.ssl
    return port || 80

  # Given configuration object, request, optional path and query, return a URL
  # for redirecting back to proxy (e.g. redirect user to connect or OAuth
  # callback)
  url: (config, req, params)->
    protocol = if config.ssl then "https:" else "http:"
    host = req.headers["x-forwarded-host"] || req.headers.host
    return URL.format(
      protocol: protocol
      host:     host
      pathname: params.pathname || "/"
      query:    params.query
    )

  # Convert value to array of strings.  Value may be a string or null.
  toArray: (value)->
    if value instanceof Array
      return value.map((i)-> i.toString())
    else if value
      return [value.toString()]
    else
      return []


module.exports = Util
