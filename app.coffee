http       = require 'http'
util       = require 'util'
express    = require 'express'
httpProxy  = require 'http-proxy'
io         = require 'socket.io'
nanoModule = require 'nano'
request    = require 'request'

app = express.createServer()

# Choose a port and listen
port = 3000 unless process.env.NODE_PORT
if process.env.NODE_PORT then port = parseInt process.env.NODE_PORT, 10

app.configure 'development', ->
  console.log "Development env starting on port #{port}"
app.configure 'production', ->
  console.log "Production env starting on port #{port}"

# get at the server; needed by socket.io per https://github.com/LearnBoost/socket.io/issues/843
server = app.listen port

# listen for socket.io requests from client
io = io.listen server

# the CouchDB database we will use
dbPrefix = 'http://localhost:5984'
dbName   = 'model-configs'
nano     = nanoModule dbPrefix
db       = nano.use dbName

# TODO create a reasonably-likely-to-be-unique value of dbServerInstance if the couchdb instance
# doesn't have one. Store it in a separate db so it doesn't get replicated.

# A unique id for the CouchDB instance we're talking to, to namespace its counter
dbServerInstance = 'test'

#
# session support
#

# TODO use a persistent CouchDB session store
store = new express.session.MemoryStore()

app.use express.cookieParser 'not very secret secret'
app.use express.session
  store: store
  secret: 'not very secret secret'

#
# requests for model data
#
app.get '/model-config/:docName', (req, res, next) ->
  db.get req.params.docName, (error, doc) ->
    if error
      return next "Couldn't get #{req.url}\n\n#{error}\n\n"
    req.session._rev = doc._rev
    delete doc._rev
    console.log "For request #{req.url}:\n  _rev = #{req.session._rev}\ndoc:\n\n#{util.inspect doc}\n\n"
    res.json doc

app.put '/model-config/:docName', (req, res, next) ->
  docStream = ''
  req.on 'data', (val) -> docStream += val
  req.on 'end', ->
    try
      docBody = JSON.parse docStream
    catch error
      return next "Couldn't parse body of client request as JSON:\n\n#{docStream}\n\n"

    docBody._rev = req.session._rev

    opts =
      db: dbName
      method: 'PUT'
      doc: docName
      body: docBody

    console.log "PUTting to doc #{docName} in db #{dbName}:\n\n#{util.inspect docBody}"
    nano.request opts, (error, body) ->
      if error
        return next "Error updating doc #{docName} in db #{dbName}:\n\n#{util.inspect body}\n\n"
      res.json docBody
      # bump the _rev
      req.session._rev = body.rev

app.post '/model-configs', (req, res, next) ->
  docBody = null
  counter = null

  # get an id
  request.post "#{dbPrefix}/#{dbName}/_design/app/_update/bump/counter",  (error, response, body) ->
    if error
      return "Error bumping counter:\n\n#{error}\n\n#{response}\n\n"
    counter = parseInt body, 10
    trySave()

  # stream in the POST body
  docStream = ''
  req.on 'data', (val) -> docStream += val
  req.on 'end', ->
    try
      docBody = JSON.parse docStream
    catch error
      return next "Couldn't parse body of client request as JSON:\n\n#{docStream}\n\n"
    trySave()

  # Promises pattern would be useful here
  trySave = ->
    return unless docBody and counter
    docName = "#{dbServerInstance}-#{counter}"
    opts =
      db    : dbName
      method: 'PUT'
      doc   : docName
      body  : docBody

    console.log "PUTting to doc #{docName} in db #{dbName}:\n\n#{util.inspect docBody}"
    nano.request opts, (error, body) ->
      if error
        return next "Error updating doc #{docName} in db #{dbName}:\n\n#{util.inspect body}\n\n"
      res.setHeader 'Location', "/model-config/#{docName}"
      res.json docBody, 201
      # and don't forget to remember the _rev
      req.session._rev = body.rev

#
# client-side logging
#
io.sockets.on 'connection', (socket) ->
  socket.emit 'news', hello: 'world'
  socket.on 'my other event', (data) ->
    console.log(data)

  socket.on 'log', (logData) ->
    console.log "log from client: \n#{util.inspect logData}\n"

#
# proxies and static serving (last so we can override their handling)
#
app.use '/couchdb', httpProxy.createServer 'localhost', 5984
app.use express.static "#{__dirname}/public"
