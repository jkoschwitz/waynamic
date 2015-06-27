Pictures = exports? and exports or @Pictures = {}

_ = require 'underscore'
neo4j = require 'neo4j'
db = new neo4j.GraphDatabase 'http://neo4j:waynamic@localhost:7474'

Pictures.all = (cb) ->
  query =
    """
    MATCH (picture:picture)-->(keyword:keyword)
    RETURN
      id(picture) AS _id,
      picture.url AS url,
      picture.title AS title,
      collect(keyword.name) AS keywords;
    """
  db.cypher query:query, cb

Pictures.random = (limit, cb) ->
  query =
    """
    MATCH (picture:picture)
    OPTIONAL MATCH (picture:picture)<--(user:user)
    WITH DISTINCT picture, count(user) AS used
    ORDER BY used ASC
    LIMIT {prelimit}
    WITH picture, rand() AS rand
    ORDER BY rand
    MATCH (picture)-->(keyword:keyword)
    RETURN
      id(picture) AS _id,
      picture.url AS url,
      picture.title AS title,
      collect(keyword.name) AS keywords
    LIMIT {limit};
    """
  params =
    limit:limit
    prelimit:2*limit+100
  db.cypher query:query, params:params, (err, pictures) ->
    if err
      console.log "ERROR in pictures.coffee Pictures.random: #{err.message}"
      return cb null, {}
    else
      return cb err, pictures

Pictures.one = (_id, cb) ->
  query =
    """
    START picture = node({picture_id})
    WHERE labels(picture) = ['picture']
    WITH picture
    MATCH (picture)-->(keyword:keyword)
    RETURN
      id(picture) AS _id,
      picture.url AS url,
      picture.title AS title,
      collect(keyword.name) AS keywords;
    """
  params = picture_id:parseInt(_id)
  db.cypher query:query, params:params, (err, picture) ->
    if err
      console.log "ERROR in pictures.coffee Pictures.one: #{err.message}"
      return cb null, {}
    return cb null, picture[0]

Pictures.add = (picture, cb) ->
  query =
    """
    MERGE (picture:picture {url:{url}})
    ON CREATE
      SET picture.title = {title}, picture.created = timestamp(), picture.new = 1
      WITH picture
      WHERE picture.new = 1
      UNWIND {keywords} AS keyword_name
        MERGE (keyword:keyword {name: keyword_name})
        MERGE (picture)-[:metadata]->(keyword)
      REMOVE picture.new;
    """
  params = _.pick picture, 'url', 'title', 'keywords'
  db.cypher query:query, params:params, cb

Pictures.get_id = (picture, cb) ->
  query =
    """
    MATCH (picture:picture {url:{url}})-->(keyword:keyword)
    RETURN
      id(picture) AS _id,
      picture.url AS url,
      picture.title AS title,
      collect(keyword.name) AS keywords;
    """
  params = url:picture.url
  db.cypher query:query, params:params, cb

