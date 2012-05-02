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
store = new express.session.MemoryStore()

app.use express.cookieParser 'not very secret secret'
app.use express.session
  store: store
  secret: 'not very secret secret'

#
# requests for model data
#
app.get '/model-config', (req, res, net) ->
  db.get 'example-1', (err, doc) ->
    req.session._id = doc._id
    delete doc._id
    req.session._rev = doc._rev
    delete doc._rev
    console.log "returning\n\n#{util.inspect doc}\n\n"
    res.json doc

app.get '/model-config/:docName', (req, res, next) ->
  db.get req.params.docName, (error, doc) ->
    if error
      console.error "Couldn't get #{req.url}\n\n#{error}\n\n"
      return next error
    req.session._id = doc._id
    delete doc._id
    req.session._rev = doc._rev
    delete doc._rev
    console.log "returning\n\n#{util.inspect doc}\n\n"
    res.json doc

app.put '/model-config', (req, res, next) ->
  docBody = ''

  req.on 'data', (val) -> docBody += val

  req.on 'end', ->
    docBody = JSON.parse docBody
    docBody._rev = req.session._rev
    docBody._id  = req.session._id

    opts =
      db: dbName
      method: 'PUT'
      doc: 'example-1'
      body: docBody

    nano.request opts, (err, body) ->
      console.log "CouchDB response:\n\n#{util.inspect body}\n\n"
      if body.ok
        res.json body
        req.session._rev = body.rev
      else
        next "Document update error: \n\n#{util.inspect body}\n\n"

app.post '/model-configs', (req, res, next) ->
  docBody = null
  counter = null

  # get an id
  request.post "#{dbPrefix}/#{dbName}/_design/app/_update/bump/counter",  (error, response, body) ->
    if error
      next error
    else if response.statusCode isnt 201
      next "unexpected status code from bump/counter: #{response}"
    else
      console.log "ok: body = #{body}"
      counter = parseInt body, 10
      trySave()

  # stream in the POST body
  docStream = ''
  req.on 'data', (val) -> docStream += val
  req.on 'end', ->
    try
      docBody = JSON.parse docStream
    catch error
      next "couldn't parse body as JSON:\n\n#{docStream}\n\n"
      return
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

    nano.request opts, (err, body) ->
      console.log "CouchDB response:\n\n#{util.inspect body}\n\n"
      if body.ok
        res.setHeader 'Location', "/model-config/#{docName}"
        res.json docBody, 201
      else
        next "Document update error: \n\n#{util.inspect body}\n\n"

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
