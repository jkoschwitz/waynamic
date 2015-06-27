## Libs

neo4j = require 'neo4j'
db = new neo4j.GraphDatabase 'http://neo4j:waynamic@localhost:7474'
_ = require 'underscore'
async = require 'async'

## Code

MicroService = require('micros').MicroService
ms = new MicroService 'user'
ms.$set 'api', 'ws'

user = (req, res, next) ->
  console.log "user"
  next req, res

# expects:
#   req.user_id
#   req.type
# returns (example):
#   interests: {
#     keyword: [
#       {metadata_name:'sun', likes:0.5},  # like interval 0..1
#       {metadata_name:'sea', likes:0.4}   # sort by likes descending
#     ]
#   }
user.interests = (req, res, next) ->
  query =
    """
    START user=node({user_id})
    MATCH (user)-[i:interest]->(metadata)
    WHERE (metadata)<--(:#{req.type})
      and i.like > 0
    RETURN
      labels(metadata)[0] AS metadata_type,
      metadata.name AS metadata_name,
      i.like AS like,
      i.dislike AS dislikes
    ORDER BY like DESC;
    """
  params = user_id:req.user_id
  db.cypher query:query, params:params, (err, interests) ->

    # group by type of metadata (for now only `keyword` of `picture`)
    # and handle each type for its own
    interests = _.groupBy interests, (interest) -> interest.metadata_type
    for metadata_type, metadata_list of interests

      # calculate normalized interestlevel
      max = metadata_list[0].like * 1.0
      max = 1.0 if max is 0
      metadata_list = _.map metadata_list, (metadata_item) ->
        # relevance dislikes
        metadata_item.dislikes *= req.dislike_fac
        # combine like and disklike
        metadata_item.like = metadata_item.like * metadata_item.like / (metadata_item.like + metadata_item.dislikes)
        # normalize
        metadata_item.like /= max
        # sanitize
        delete metadata_item.metadata_type
        delete metadata_item.dislikes
        return metadata_item

      # sort and write back
      metadata_list = _.sortBy metadata_list, (metadata_item) -> - metadata_item.like
      metadata_list = metadata_list[0...50]
      interests[metadata_type] = metadata_list

    req.interests = interests
    next req, res

# The Friends from a user: req.user_id as a Scatter
user.sfriends = (req, res, next) ->
  query =
    """
    START user=node({user_id})
    MATCH (user)-[:knows]->(Friends)
    RETURN
      DISTINCT id(Friends) AS _id,
      Friends.firstName AS firstName,
      Friends.lastName AS lastName
    """
  params = user_id:req.user_id
  db.cypher query:query, params:params, (err, friends) ->
    reqres = []
    if friends.length is 0
      # Modify the chain if no aggregate is needed
      do next.chain.pop    # Pop the filter out
      do next.chain.pop    # Pop item.aggregate out
      # Only the extend service will requested
      reqres.push req
    else
      for friend in friends
        nreq = _.clone req
        nreq.current_user_id = nreq.user_id
        nreq.user_id = friend.friend_id
        nreq.firstName = friend.firstName
        nreq.lastName = friend.lastName
        reqres.push nreq

    reqres.push res
    next.apply @, reqres

# The Activities from a user: req.user_id
user.activities = (req, res, next) ->
  query =
    """
    START friend=node({friend_id}), user=node({user_id})
    MATCH (friend)-[like:like]->(media:#{req.type})-[:metadata]->(metadata)<-[interest:interest]-(user)
    WHERE
      not (user)-[:like]->(media)  // only media that the user does not yet like
      and interest.like > 0        // only metadata matching current's interests
    RETURN
      id(media) AS _id,
      media.title AS title,
      media.url AS url,
      collect(metadata.name) AS metadata_name,
      like.rating AS rating,
      like.updated AS updated
    ORDER BY updated DESC
    LIMIT 100
    """
  params =
    friend_id:req.user_id
    user_id:req.current_user_id
  db.cypher query:query, params:params, (err, likes) ->
    # weight by last visit date
    amount = likes.length
    max = 0
    for like, i in likes
      like.rating *= 1.0*(amount-i)/amount
      max = like.rating if like.rating > max
    # normalize
    for like in likes
      like.rating /= max

    req.activities = likes
    next req, res


ms.$install user

## Module Export

module.exports = ms
