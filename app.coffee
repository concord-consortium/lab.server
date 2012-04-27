
http      = require 'http'
util      = require 'util'
express   = require 'express'
httpProxy = require 'http-proxy'
io        = require 'socket.io'

DEFAULT_PORT = 3000
port = if process.env.NODE_PORT then parseInt(process.env.NODE_PORT, 10) else DEFAULT_PORT
console.log "about to listen on port #{port}"
app = express.createServer()
server = app.listen port

# see https://github.com/LearnBoost/socket.io/issues/843
io = io.listen server

#
# handle model data here
#

app.get '/model-config', (req, res, next) ->
  options =
    host: 'localhost'
    port: 5984
    path: '/model-configs/example-1'

  couch = http.get options, (couchResponse) ->
    val = ""

    if couchResponse.statusCode isnt 200
      next """
           There was a #{couchResponse.statusCode} error reading from the CouchDB server:

           #{util.inspect couchResponse.headers}
           """

    couchResponse.on 'data', (data) -> val += data
    couchResponse.on 'end', -> res.send val

  couch.on 'error', (err) ->
    next "There was an error connecting to the CouchDB server:\n\n#{util.inspect err}"

#
# handle client-side logging here
#

io.sockets.on 'connection', (socket) ->
  socket.emit 'news', hello: 'world'
  socket.on 'my other event', (data) ->
    console.log(data)

  socket.on 'log', (logData) ->
    console.log "log from client: \n#{util.inspect logData}\n"

#
# handle proxies here
#

app.use '/couchdb', httpProxy.createServer 'localhost', 5984

app.configure 'development', ->
   console.log "Development env starting"

app.configure 'production', ->
  console.log "Production env starting"

app.use express.static "#{__dirname}/public"
