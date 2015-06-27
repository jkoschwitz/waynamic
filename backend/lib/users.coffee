Users = exports? and exports or @Users = {}

_ = require 'underscore'
neo4j = require 'neo4j'
db = new neo4j.GraphDatabase 'http://neo4j:waynamic@localhost:7474'

Users.all = (cb) ->
  query =
    """
    MATCH (user:user)
    RETURN
      id(user) AS _id,
      user.firstName AS firstName,
      user.lastName AS lastName
    ORDER BY _id ASC
    LIMIT {limit};
    """
  params = limit: 1000
  db.cypher query:query, params:params, cb

Users.one = (_id, cb) ->
  query =
    """
    START user = node({user_id})
    WHERE labels(user) = ['user']
    RETURN
      id(user) AS _id,
      user.firstName AS firstName,
      user.lastName AS lastName;
    """
  params = user_id:parseInt(_id)
  db.cypher query:query, params: params, (err, result) ->
      if err
        console.log "ERROR in users.coffee Users.one: #{err.message}"
        return cb null, {}
      cb null, result[0]

Users.history = (_id, type, cb) ->
  query =
    """
    START user = node({user_id})
    WHERE labels(user) = ['user']
    MATCH (user)-[like:like]->(media:#{type})
    RETURN
      id(media) AS _id,
      media.title AS title, media.url AS url, like.updated AS updated
    ORDER BY updated DESC;
    """
  params = user_id: parseInt(_id)
  db.cypher query:query, params:params, (err, result) ->
    result = _.map result, (r) -> r.url = r.url.replace /\.jpg$/, '_s.jpg'; r
    cb err, result

Users.friends = (_id, cb) ->
  db.cypher
  query =
    """
    START user=node({user_id})
    MATCH (user)-[:knows]->(friends)
    RETURN
      DISTINCT id(friends) AS _id,
      friends.firstName AS firstName,
      friends.lastName AS lastName
    ORDER BY _id ASC;
    """
  params = user_id:parseInt(_id)
  db.cypher query:query, params:params, cb


