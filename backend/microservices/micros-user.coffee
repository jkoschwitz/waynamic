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
#   req.user
#   req.type
# returns (example):
#   interests: {
#     'dc:keywords': [
#       {name:'sun', likes:0.5},       # like interval 0..1
#       {name:'sea', likes:0.4}        # sort by likes descending
#     ]
#   }
user.interests = (req, res, next) ->
  query =
    """
    START User=node({userID})
    MATCH (User)-[i:`foaf:interest`]->(Metatag)
    WHERE (Metatag)<--(:#{req.type})
      and i.like > 0
    RETURN labels(Metatag)[0] AS metatype, Metatag.name AS name, i.like AS like, i.dislike AS dislikes
    ORDER BY like DESC;
    """
  params = userID:req.user
  db.cypher query:query, params:params, (err, result) ->
    interests = _.groupBy result, (meta) -> meta.metatype
    for metatype, metataglist of interests
      max = metataglist[0].like * 1.0
      max = 1.0 if max is 0
      metataglist = _.map metataglist, (metatag) ->
        # normalize by likes
        metatag.like /= max
        metatag.dislikes /= max
        # relevance dislikes
        metatag.dislikes *= req.dislike_fac
        # combine like and disklike
        metatag.like = metatag.like * metatag.like / (metatag.like + metatag.dislikes)
        # sanitize
        delete metatag.metatype
        delete metatag.dislikes
        metatag
      metataglist = _.sortBy metataglist, (metatag) -> - metatag.like
      metataglist = metataglist[0...50]
      interests[metatype] = metataglist
    req.interests = interests
    # console.log interests
    next req, res

# The Friends from a user: req.user as a Scatter
user.sfriends = (req, res, next) ->
  query =
    """
    START User=node({userID})
    MATCH (User)-[:`foaf:knows`]->(Friends)
    RETURN
      DISTINCT id(Friends) AS _id
      Friends.firstName AS firstName
      Friends.lastName AS lastName
    """
  params = userID:req.user
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
        nreq.current_user = nreq.user
        nreq.user = friend._id
        nreq.firstName = friend.firstName
        nreq.lastName = friend.lastName
        reqres.push nreq

    reqres.push res
    console.log friends
    next.apply @, reqres

# The Activities from a user: req.user
user.activities = (req, res, next) ->
  query =
    """
    START Friend=node({friend}), Current=node({user})
    MATCH (Friend)-[like:`like`]->(Media:#{req.type})-[:metatag]->(Metatag)<-[interest:`foaf:interest`]-(Current)
    WHERE not (Current)-[:`like`]->(Media)  // only media not yet clicked
          and interest.like > 0             // only metatags matching current's interests
          and (Current)-[:`foaf:interest`]->()<-[:metatag]-(Media)
    RETURN
      id(Media) AS _id,
      Media.title AS title,
      Media.url AS url,
      collect(Metatag.name) AS metatags,
      like.rating AS rating,
      like.updated AS updated
    ORDER BY updated DESC
    LIMIT 100
    """
  params =
    friend:req.user
    user:req.current_user
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
    # console.log req.activities
    next req, res


ms.$install user

## Module Export

module.exports = ms
