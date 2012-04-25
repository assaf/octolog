# Example for proxy and HTTPS


## Echo server

To run the echo server:

```
node example/echo.js 
```

If you open your browser to [http://localhost:3000/](http://localhost:3000/) you
will see that it just echoes the HTTP request headers.  They may look something
like this:

```
{ host: "localhost:3000",
  connection: "keep-alive",
  cache-control: "max-age=0",
  user-agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_3) AppleWebKit/535.19 (KHTML, like Gecko) Chrome/18.0.1025.163 Safari/535.19",
  accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  accept-encoding: "gzip,deflate,sdch",
  accept-language: "en-US,en;q=0.8",
  accept-charset: "ISO-8859-1,utf-8;q=0.7,*;q=0.3"
}
```


## Proxy

Edit the configuration file `example/proxy.json` to make sure your Github
login is listed as authorized login.

Now run the Octolog server with this configuration:

```
./bin/octolog example/proxy.json
```

If you open your browser to [http://localhost:8000/](http://localhost:8000/) you
will notice that it's simply proxying to the echo server, so you get the same
set of headers, plus the `x-forwarded` headers added by the proxy.

Now sign in with your Github account by visiting
[/_octolog/connect](http://localhost:8000/_octolog/connect)
and you will notice that four more `x-github` headers show up.

Sign out by going to
[/_octolog/disconnect](http://localhost:8000/_octolog/disconnect) and you will
notice these headers are no longer there.


## HTTPS

Edit the configuration file `example/https.json` to make sure your Github
login is listed as authorized login.

Now run the Octolog server with this configuration:

```
sudo ./bin/octolog example/https.json
```

You will need `sudo` in order to listen on both ports 80 and 443.

If you open your browser to [http://localhost/](http://localhost/) you will be
redirected immediately to [https://localhost/](https://localhost/).  Since the
example SSL certificate is self-signed, you will see a warning message.

If you instruct the browser to proceed, it will make the same request again only
this time using HTTPS and the request will hit the proxy.  The rest (connecting
and disconnecting) should work as above.

In production, when you use a proper SSL certificate, this redirect flow is
transparent to the user.

