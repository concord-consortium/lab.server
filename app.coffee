
http      = require 'http'
util      = require 'util'
express   = require 'express'
httpProxy = require 'http-proxy'
io        = require 'socket.io'
nano      = require('nano')('http://localhost:5984')

# Choose a port and listen
port = 3000 unless process.env.NODE_PORT
if process.env.NODE_PORT then port = parseInt process.env.NODE_PORT, 10

console.log "about to listen on port #{port}"
app = express.createServer()
server = app.listen port

# Listen for socket.io requests from client
# see https://github.com/LearnBoost/socket.io/issues/843
io = io.listen server

# the CouchDB database we will use
configs = nano.use 'model-configs'

#
# handle model data here
#

app.get '/model-config', (req, res) ->
  configs.get('example-1').pipe res


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
