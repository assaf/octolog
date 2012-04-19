var server = require("connect").createServer();

server.use(function(req, res) {
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(req.headers));
})

server.listen(3000)
