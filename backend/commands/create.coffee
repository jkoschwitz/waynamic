#!/usr/bin/env coffee
Create = exports? and exports or @Create = {}

### modules/includes ###
_ = require "underscore"
async = require "async"
neo4j = require "neo4j"
db = new neo4j.GraphDatabase url: 'http://neo4j:waynamic@localhost:7474'
dict = require "./dictionary.json"
config = require "./config.json"

#--- nodes ---------------------------------------------------------------------
userCache = []

getRandomExistingUser = (currentUser) ->
  if userCache.length > 1
    list = _.filter userCache, (u) -> u._id isnt currentUser?._id
    i = _.random(0, list.length - 1)
    return userCache[ i ]
  else
    return null

createUserNode = (cb) ->
  query = """
    CREATE (u:User {properties})
    SET u.createdAt = timestamp()
    RETURN u
    """
  params =
    properties:
      firstName: dict.firstNames[ _.random(0,dict.firstNames.length) ] # first names: http://deron.meranda.us/data/census-derived-all-first.txt
      lastName: dict.lastNames[ _.random(0,dict.lastNames.length) ] # last names: http://www.census.gov/genealogy/www/data/1990surnames/dist.all.last
      age: _.random(16,70)
  db.cypher query:query, params:params, (err, nodes) ->
    user = nodes[0].u
    # user.index "User", "id", user.id, ->
    userCache.push user
    target = getRandomExistingUser(user)
    if target
      user.createRelationshipTo target, "faof:knows", {}, cb
    else
      cb? null, false

createRandomEdge = (cb) ->
  u1 = getRandomExistingUser()
  u2 = getRandomExistingUser u1
  if u1 and u2
    u1.createRelationshipTo u2, "foaf:knows", {}, cb
  else
    cb? null, false

createSomeEdges = (k, cb) ->
  async.timesSeries k, ((iterator, next) ->
    createRandomEdge (err, edge) -> next(err, edge)
  ), cb

connectNeighbors = (p, cb) ->
  query = """
    START a=node(*)
    MATCH (a:User)-->(b:User)--(c:User)
    WHERE NOT (a)--(c)
    RETURN a, c LIMIT 10';
    """ # limiting triangle connection possibilities to achieve linear runtime. Remove the limit for more accurate results
  db.cypher query:query, (err, pairs) ->
    async.each pairs, ((pair, callback) ->
      if Math.random() <= p
        {a, c} = pair
        a.createRelationshipTo c, "foaf:knows", {}, callback
      else
        callback null
    ), cb

createSomeUsers = (n, k, p, cb) ->
  async.timesSeries n, (iterator, next) ->
    console.log "iteration: ", iterator, n
    createUserNode (err, user) ->
      createSomeEdges k, (err, edges) ->
        connectNeighbors p, ->
          next err, user
  , cb

### actual command ###
Create.run = (userCount) ->
  # import parameters for the algorithm
  n = config.create.userLimit
  k = config.create.randomEdges
  p = config.create.connectivityProbability

  # ensure indexes for users and "foaf:knows"-edges
  # db.createIndex label:"User", property:"_id", (err) ->
  #   db.createIndex "foaf:knows", ->

  console.log "Creating user graph with #{n} users"
  createSomeUsers n, k, p, (err, users) ->
    if err
      console.log "!!! ERROR: Couldn't create Users: ", err
    else
      console.log ">>> Created #{n} Users."

### when started directly as script ###
if process.argv[1] is __filename
  Create.run()
