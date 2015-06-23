#!/usr/bin/env coffee
Clear = exports? and exports or @Clear = {}

neo4j = require "neo4j"
db = new neo4j.GraphDatabase 'http://neo4j:waynamic@localhost:7474'

### actual command ###
Clear.run = ->
  console.log "deleting database..."
  query = """
    MATCH (n)
    OPTIONAL MATCH (n)-[r]-()
    DELETE r,n;
    """
  db.cypher query:query, ->
    console.log "database CLEAR!"

### when started directly as script ###
if process.argv[1] is __filename
  Clear.run()
