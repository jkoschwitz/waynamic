Feedback = exports? and exports or @Feedback = {}

neo4j = require 'neo4j'
db = new neo4j.GraphDatabase 'http://neo4j:waynamic@localhost:7474'

Feedback.clear = (cb) ->
  db.cypher query:"MATCH (:user)-[r:like|dislike|interest]->() DELETE r", cb

Feedback.click = (user_id, media_id, cb) ->
  rating = +1
  Feedback.feedback user_id, media_id, rating, 'like', cb

Feedback.ignore = (user_id, media_id, cb) ->
  recommendations = 12
  rating = 1.0 / recommendations
  Feedback.feedback user_id, media_id, rating, 'dislike', cb

Feedback.feedback = (user_id, media_id, rating, ratingtype, cb) ->
  throw new Error "no callback defined" unless cb
  query = "START media=node({media_id}) RETURN labels(media)[0] AS mediatype;"
  params = media_id:media_id
  db.cypher query:query, params:params, (err, mediatype) ->
    if err
      console.log "ERROR in feedback.coffee Feedback.feedback: #{err.message}"
      return cb null
    fn = switch mediatype[0].mediatype
      when 'picture' then Picture
      when 'video'   then Video
      when 'movie'   then Movie
      when 'music'   then Music
    fn user_id, media_id, rating, ratingtype, cb

Picture = (user_id, picture_id, rating, ratingtype, cb) ->
  if ratingtype is "like" then query =
    """
    START user=node({user_id}), picture=node({picture_id})
    MERGE (user)-[l:like]->(picture)
    ON CREATE SET
      l.created = timestamp(),
      l.updated = timestamp(),
      l.rating = {rating}
    ON MATCH SET
      l.updated = timestamp(),
      l.rating = l.rating + {rating}
    WITH user, picture
    MATCH (picture)-->(keyword:keyword)
    MERGE (user)-[i:interest]->(keyword)
    ON CREATE SET
      i.created = timestamp(),
      i.updated = timestamp(),
      i.like = {rating},
      i.dislike = 0
    ON MATCH SET
      i.updated = timestamp(),
      i.like = i.like + {rating};
    """
  else if ratingtype is "dislike" then query =
    """
    START user=node({user_id}), picture=node({picture_id})
    MERGE (user)-[d:dislike]->(picture)
    ON CREATE SET
      d.created = timestamp(),
      d.updated = timestamp(),
      d.rating = {rating}
    ON MATCH SET
      d.updated = timestamp(),
      d.rating = d.rating + {rating}
    WITH user, picture
    MATCH (picture)-->(keyword:keyword)
    MERGE (user)-[i:interest]->(keyword)
    ON CREATE SET
      i.created = timestamp(),
      i.updated = timestamp(),
      i.like = 0,
      i.dislike = {rating}
    ON MATCH SET
      i.updated = timestamp(),
      i.dislike = i.dislike + {rating};
    """
  params =
    user_id: user_id
    picture_id:picture_id
    rating:rating
  db.cypher query:query, params:params, cb



Video = (user, video, rating, ratingtype, cb) -> return cb new Error "not yet implemented"

Movie = (user, movie, rating, ratingtype, cb) -> return cb new Error "not yet implemented"

Music = (user, music, rating, ratingtype, cb) -> return cb new Error "not yet implemented"
