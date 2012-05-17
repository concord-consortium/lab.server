http       = require 'http'
util       = require 'util'
express    = require 'express'
httpProxy  = require 'http-proxy'
io         = require 'socket.io'
cradle     = require 'cradle'

app = express.createServer()

# Choose a port and listen
port = 3000 unless process.env.NODE_PORT
if process.env.NODE_PORT then port = parseInt process.env.NODE_PORT, 10

# load configuration details

try
  config = require './config'
catch err
  if err.toString().indexOf('Cannot find module') >= 0
    console.error """
      ***
        You need to set up a 'config.coffee' file for this Lab server.

        First, choose a meaningful prefix for your installation. This prefix will be
        used to namespace the models you create in this instance. For example, if you
        choose the prefix 'hm' (for Happy Modeler) then models you save will have CouchDB
        ids 'hm-1', 'hm-2', etc. When you replicate models from your local database to
        another database (say the main dev instance), this namespacing will help prevent
        document update conflicts.

        Now, copy config.sample.coffee to config.coffee. Edit the file with the database
        prefix, and an admin username and password for your CouchDB install.

        If you have left CouchDB in 'admin party' mode (no authentication required
        to create databases!), make the values for 'username' and 'password' the
        empty string.

        On a public facing server, you should also choose a session 'secret' string. This
        is used by Connect to secure user sessions against cookie hijacking.
      ***
    """
  else
    console.error """
      ***
        Aborting! There was an error reading the config.coffee file. The error was:

        #{err}
      ***
    """

  process.exit 1


if config.database.prefix is 'CHANGEME'
  console.error """
    ***
      Aborting! The current database.prefix in your config.coffee file is "CHANGEME".

      You need to choose a meaningful prefix for your installation. This prefix will be
      used to namespace the models you create in this instance. For example, if you
      choose the prefix 'hm' (for Happy Modeler) then models you save will have CouchDB
      ids 'hm-1', 'hm-2', etc. When you replicate models from your local database to
      another database (say the main dev instance), this namespacing will help prevent
      document update conflicts.

      Once you have chosen a prefix unique to your installation, edit the config.coffee
      file with that prefix.
    ***
  """

  process.exit 1


# Things are apparently OK.

app.configure 'development', ->
  console.log "Development env starting on port #{port}"
app.configure 'production', ->
  console.log "Production env starting on port #{port}"

# get at the server; needed by socket.io per https://github.com/LearnBoost/socket.io/issues/843
server = app.listen port

# listen for socket.io requests from client
io = io.listen server


args = {}
if config.database.username
  args =
    auth:
      username: config.database.username
      password: config.database.password

conn = new cradle.Connection args

dbName   = 'models'
db = conn.database dbName

counterDbName = 'lab-counter'
counterDb = conn.database counterDbName

counterDb.exists (error, exists) ->
  nextStep = makeCounterDoc

  if error
    console.error "Couldn't check for existence of counter db!\n#{util.inspect error}"
    process.exit 1
  if exists
    nextStep()
  else
    console.log 'creating counter db...'
    counterDb.create (err, res) ->
      if err
        console.error "Couldn't create counter db!\n#{util.inspect err}"
        process.exit 1
      nextStep()

makeCounterDoc = ->
  nextStep = updateCounterDesignDoc

  counterDb.get 'counter', (error, response) ->
    if not error
      nextStep()
    else
      console.log "counterdb counter document not found; creating"
      counterDb.save 'counter', { value: 0 }, (error, response) ->
        if error
          console.error "Could not create counter db document!"
          process.exit 1
        else
          nextStep()

updateCounterDesignDoc = ->
  nextStep = makeModelDb

  # This is a so-called "document update function" that will be passed to CouchDB
  # It will update the 'value' field of the document it's called on.
  designDoc =
    views: {}
    updates:
      bump: (doc, req) ->
        doc.value++
        [doc, ''+doc.value]

  counterDb.get '_design/app', (err, res) ->
    # ignore error which will occur _design/app doesn't exist yet (we're force updating)
    if not err
      console.log "Force-updating counterDb's _design/app; _rev = #{res.json._rev}"
      designDoc._rev = res.json._rev

    counterDb.save '_design/app', designDoc, (err, res) ->
      if err
        console.error "couldn't save counterDb's _design/app!"
        process.exit 1

      nextStep()

makeModelDb = (cont) ->
  nextStep = setupApp

  db.exists (error, exists) ->
    if error
      console.error "Couldn't check for existence of models db!\n#{util.inspect error}"
      process.exit 1
    if exists
      nextStep()
    else
      console.log 'creating models db...'
      db.create (err, res) ->
        if err
          console.error "Couldn't create models db!\n#{util.inspect err}"
          process.exit 1
        nextStep()

setupApp = ->

  #
  # session support
  #

  # TODO use a persistent CouchDB session store
  store = new express.session.MemoryStore()

  app.use express.cookieParser config.session.secret
  app.use express.session
    store: store
    secret: config.session.secret

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

  app.post '/model-configs', (req, res, next) ->
    docBody = null
    counter = null

    # get an id
    counterDb.update 'app/bump', 'counter', (error, response) ->
      if error
        return next "Error bumping counter:\n\n#{util.inspect error}\n\n#{response}\n\n"
      counter = parseInt response.json, 10
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
      docName = "#{config.database.prefix}-#{counter}"

      console.log "PUTting to doc #{docName} in db #{dbName}:\n\n#{util.inspect docBody}"
      db.save docName, docBody, (error, couchRes) ->
        if error
          return next "Error updating doc #{docName} in db #{dbName}:\n\n#{util.inspect couchRes}\n\n"
        res.setHeader 'Location', "/model-config/#{docName}"
        res.json 201, docBody
        # and don't forget to remember the _rev
        req.session._rev = couchRes.rev

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

  console.log "ready"
