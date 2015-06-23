#!/usr/bin/env coffee
TimeKeeper = require '../lib/timekeeper'
MediaApi = require '../lib/media_api'
Flickr = MediaApi.Flickr('0969ce0028fe08ecaf0ed5537b597f1e')

run = ->
  TimeKeeper.start "flickr cache filter"
  console.log "pictures before: #{do Flickr.cache.count}"
  Flickr.cache.filter ->
    TimeKeeper.stop "flickr cache filter"
    console.log "pictures after: #{do Flickr.cache.count}"

# ––– when started directly as script ––– npm run flickr:cache –––
if process.argv[1] is __filename
  do run
