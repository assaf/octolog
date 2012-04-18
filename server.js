// Up workers load this file, and via this file server.coffee and the rest of
// the application (JS and CS files).
var coffee = require("coffee-script");
var File = require("fs");
if (!require.extensions[".coffee"]) {
  require.extensions[".coffee"] = function (module, filename) {
    var source = coffee.compile(File.readFileSync(filename, "utf8"));
    return module._compile(source, filename);
  };
}
module.exports = require(__dirname + "/lib/server.coffee")
