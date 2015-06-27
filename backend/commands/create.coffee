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
  query =
    """
    CREATE (user:user {properties})
    SET user.createdAt = timestamp()
    RETURN user
    """
  params =
    properties:
      firstName: dict.firstNames[ _.random(0,dict.firstNames.length) ] # first names: http://deron.meranda.us/data/census-derived-all-first.txt
      lastName: dict.lastNames[ _.random(0,dict.lastNames.length) ] # last names: http://www.census.gov/genealogy/www/data/1990surnames/dist.all.last
      age: _.random(16,70)
  db.cypher query:query, params:params, (err, nodes) ->
    user = nodes[0].user
    # user.index "user", "_id", user._id, ->
    userCache.push user
    target = getRandomExistingUser(user)
    connectUsers user, target, ->
      cb err, user # do never return created relationship – but return user

#--- relationships -------------------------------------------------------------
connectUsers = (user1, user2, cb) ->
  return cb? null, false unless user1? and user2?
  query =
    """
    START user1=node({from_id}), user2=node({to_id})
    MERGE (user1)-[knows:knows]->(user2)
    RETURN knows;
    """
  params =
    from_id: user1._id
    to_id: user2._id
  db.cypher query:query, params:params, cb

createSomeRandomEdges = (k, cb) ->
  async.timesSeries k, ((iterator, next) ->
    u1 = getRandomExistingUser()
    u2 = getRandomExistingUser u1
    connectUsers u1, u2, (err, edge) -> next(err, edge)
  ), cb

# connects for each iteration …………………
connectNeighbors = (p, cb) ->
  query = # here be dragons: the original code matches only triangle relationships with the first user
    """
    START a=node(*)
    MATCH (a:user)-->(b:user)--(c:user)
    WHERE NOT (a)--(c) AND NOT a = c
    RETURN a, c LIMIT 10;
    """ # limiting triangle connection possibilities to achieve linear runtime. Remove the limit for more accurate results
  db.cypher query:query, (err, pairs) ->
    async.each pairs, ((pair, cb) ->
      if Math.random() <= p
        {a, c} = pair
        connectUsers a, c, cb
      else
        cb null
    ), cb

createSomeUsers = (n, k, p, cb) ->
  async.timesSeries n, (iterator, next) ->
    console.log "iteration: ", iterator, n
    createUserNode (err, user) ->
      createSomeRandomEdges k, (err, edges) ->
        connectNeighbors p, ->
          next err, user
  , cb

#--- actual command ------------------------------------------------------------
Create.run = (userCount) ->
  # import parameters for the algorithm
  n = config.create.userLimit
  k = config.create.randomEdges
  p = config.create.connectivityProbability

  # ensure indexes for users and `knows`-edges
  # db.createIndex label:"user", property:"_id", (err) ->
  #   db.createIndex `knows`, ->

  console.log "Creating user graph with #{n} users"
  createSomeUsers n, k, p, (err, users) ->
    if err
      console.log "!!! ERROR: Couldn't create Users: ", err
    else
      console.log ">>> Created #{n} Users."

#--- when started directly as script -------------------------------------------
if process.argv[1] is __filename
  Create.run()
