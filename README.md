Node.js + CouchDB backend for [Lab](http://github.com/concord-consortium/lab)

# Getting started

0. Install [CouchDB](http://couchdb.apache.org/) and [Node.js](http://nodejs.org/) if you haven't already. (Node.js is required to build the Lab project so we will assume you have that installed already.) On an OS X machine with Homebrew installed, this should work:

    ```
    brew doctor     # fix issues if needed
    brew update     # if you haven't run it in the last 24 hours
    brew install couchdb
    ```

1. Clone this repository. The recommended location is to the `lab.server` directory in the base directory of the [Lab repo](http://github.com/concord-consortium/lab).

2. (Optionally) install [nodemon](http://github.com/remy/nodemon), which will automatically restart the Node server when you make changes:

    ```
    (sudo) npm install -g nodemon
    ```

3. Install [CoffeeScript](http://coffeescript.org/) If you haven't already:

    ```
    (sudo) npm install -g coffee-script
    ```

4. Symlink the `dist` folder of the Lab repo into the `public` directory. The symlink is not included in this project so that you can customize it if you desire. However, if you cloned this repo into the Lab repo, this is just:

    ```
    cd lab.server
    ln -s ../dist public
    ```

5. Start CouchDB (optionally using `-b` to start it as a background process):

    ```
    couchdb -b
    ```

6. Run the app.coffee server (optionally using nodemon to restart after changes):

    ```
    nodemon app.coffee
    ```

7. Visit the Lab app at [http://localhost:3000/](http://localhost:3000/)


# Replicating CouchDB database from developer machine to dev server, or vice versa

1. Set up an ssh tunnel to the deploy server, to access the remote CouchDB instance at
   [http://localhost:5985/](http://localhost:5985)

    ```
    ssh -fN -L5985:127.0.0.1:5984 deploy@ec2-50-17-17-189.compute-1.amazonaws.com
    ```

    This will leave the tunnel open in the background. Leave off the `-fN` if you don't mind keeping
    a terminal window open to the EC2 machine (perhaps you just want to replicate once and close the
    tunnel by issuing a Ctrl-C.)


2. With the ssh tunnel up, to replicate from the EC2 server to your local machine, issue the
   following replication command (at the command line):

    ```
    curl -X POST http://username:password@127.0.0.1:5984/_replicate -d '{"source":"http://localhost:5985/models", "target":"models", "continuous":false}' -H "Content-Type: application/json"
    ```

  The `username` and `password` are only required if you set up an admin account on your local machine.

  To replicate from your machine to the EC2 server, you need only swap target and source keys, and provide
  the CouchDB admin password for the EC2 server rather than your local password, as folloows:

    ```
    curl -X POST http://127.0.0.1:5984/_replicate -d '{"source":"models", "target":"http://username:password@localhost:5985/models", "continuous":false}' -H "Content-Type: application/json"
    ```

# Deploying updated versions to the EC2 server

    ```
    ssh deploy@ec2-50-17-17-189.compute-1.amazonaws.com "cd /var/www; git pull; sudo restart lab.dev.concord.org"
    ```
