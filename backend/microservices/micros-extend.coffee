## Libs

_ = require 'underscore'
neo4j = require 'neo4j'
db = new neo4j.GraphDatabase 'http://neo4j:waynamic@localhost:7474'

## Code

MicroService = require('micros').MicroService
ms = new MicroService 'extend'
ms.$set 'api', 'ws'

# Extends the result with additional items by content based filtering
# for now only `keyword` of `picture`
extend = (req, res, next) ->
  req.count_cb += req.count_sb - res.length
  query =
    """
    START user=node({user_id})
    MATCH (user)-[i:interest]->()<--(media:#{req.type})
    WHERE
      not (user)-[:like]->(media)
      and i.like > 0
    WITH
      DISTINCT media,
      sum(i.like * i.like / ({dislike_fac}*i.dislike + i.like)) AS interests
    ORDER BY interests DESC
    RETURN
      DISTINCT id(media) AS _id,
      media.url AS url,
      'Passend zu Ihren Interessen' AS subtitle
    LIMIT {limit}
    """
  params =
    user_id: req.current_user_id
    limit: req.count_cb
    dislike_fac: req.dislike_fac
  db.cypher query:query, params:params, (err, mediaitems) ->
    sb_ids = _.map res, (item) -> item._id
    mediaitems = _.filter mediaitems, (m) -> not (m._id in sb_ids)
    res = res.concat mediaitems
    console.log res
    next req, res

ms.$install extend

## Module Export

module.exports = ms
