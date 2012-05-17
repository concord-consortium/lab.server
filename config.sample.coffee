module.exports =
  database:
    # password for admin account on CouchDB install
    username: 'username'
    password: 'password'
    prefix:   'CHANGEME' # choose a prefix that will uniquely identify the local CouchDB install
  session:
    secret: 'not very secret secret'