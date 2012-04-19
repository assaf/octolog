Connect = require("connect")

server = Connect.createServer()
server.use (req, res)->
  res.setHeader "Content-Type", "application/json"
  res.end JSON.stringify(req.headers)

server.listen(3000)
