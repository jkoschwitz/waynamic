Users = exports? and exports or @Users = {}

_ = require 'underscore'
neo4j = require 'neo4j'
db = new neo4j.GraphDatabase 'http://neo4j:waynamic@localhost:7474'

Users.all = (cb) ->
  query =
    """
    MATCH (User:User)
    RETURN
      id(User) AS _id,
      User.firstName AS firstName,
      User.lastName AS lastName
    ORDER BY _id ASC
    LIMIT {limit};
    """
  params = limit: 1000
  db.cypher query:query, params:params, cb

Users.one = (_id, cb) ->
  query =
    """
    START User = node({userID})
    WHERE labels(User) = ['User']
    RETURN
      id(User) AS _id,
      User.firstName AS firstName,
      User.lastName AS lastName;
    """
  params = userID:parseInt(_id)
  db.cypher query:query, params: params, (err, result) ->
      if err
        console.log "ERROR in users.coffee Users.one: #{err.message}"
        return cb null, {}
      cb null, result[0]

Users.history = (_id, type, cb) ->
  query =
    """
    START User = node({userID})
    WHERE labels(User) = ['User']
    MATCH (User)-[like:`like`]->(Media:#{type})
    RETURN id(Media) AS _id, Media.title AS title, Media.url AS url, like.updated AS updated
    ORDER BY updated DESC;
    """
  params = userID: parseInt(_id)
  db.cypher query:query, params:params, (err, result) ->
    result = _.map result, (r) -> r.url = r.url.replace /\.jpg$/, '_s.jpg'; r
    cb err, result

Users.friends = (_id, cb) ->
  db.cypher
  query =
    """
    START User=node({userID})
    MATCH (User)-[:`foaf:knows`]->(Friends)
    RETURN DISTINCT id(Friends) AS _id, Friends.firstName AS firstName, Friends.lastName AS lastName
    ORDER BY _id ASC;
    """
  params = userID:parseInt(_id)
  db.cypher query:query, params:params, cb


