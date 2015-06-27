MediaApi = exports? and exports or @MediaApi = {}

async = require 'async'
_ = require 'underscore'
fs = require 'fs'



# === helper ===================================================================

querystring = require 'querystring'
https = require 'https'

JSON.readFileSync = (path) ->
  if path[0] isnt '/' then path = __dirname + '/' + path
  raw = fs.readFileSync path, 'utf8'
  parsed = JSON.parse raw
  parsed

JSON.writeFileSync = (path, data) ->
  if path[0] isnt '/' then path = __dirname + '/' + path
  fs.writeFileSync path, JSON.stringify(data, null, 2)+'\n'

request = (url, parameters..., cb) ->
  url += '?' + querystring.stringify _.extend parameters...
  # console.log "GET #{url}"
  https.get url, (res) ->
    data = ''
    res.on 'data', (chunk) -> data += chunk
    res.on 'end', ->
      try
        json = JSON.parse data
      catch err
        return cb err
      cb null, json

https.head = (url, cb) ->
  splitted = url.match /^https?:\/\/(.*?)(\/.*)/
  options =
    method: 'HEAD'
    hostname: splitted[1]
    path: splitted[2]
    agent: false
  do (https.request options, cb).end

# format date to string
yyyymmdd = (date) ->
  yyyy = date.getFullYear().toString()
  mm = (date.getMonth()+1).toString(); if mm.length is 1 then mm = '0'+mm
  dd = date.getDate().toString(); if dd.length is 1 then dd = '0'+dd
  "#{yyyy}-#{mm}-#{dd}"



# === flickr ===================================================================

MediaApi.Flickr = (api_key) ->
  Flickr = {}

  # --- filter -----------------------------------------------------------------

  filter = (pic, cb) ->
    async.waterfall [
      ((cb) -> cb null, pic)
      , filter.correctness
      , filter.picture_exists # >200ms/pic series == 99,9% of execution time
      , filter.keywords_censored
      , filter.keywords_synomity
      , filter.keywords_double
      , filter.keywords_useless
      , filter.keywords_count
    ], cb

  filter.correctness = (pic, cb) ->
    return cb new Error "SKIPPED: picture not valide" unless (
      pic? and
      typeof pic.url is 'string' and
      typeof pic.title is 'string' and
      # /[\w]{2,}/.test pic.title and
      pic.keywords instanceof Array)
    return cb null, pic

  filter.picture_exists = (pic, cb) ->
    https.head pic.url, (res) ->
      size = parseInt res.headers['content-length']
      # console.log "#{pic.url} | #{size} bytes"
      return cb new Error "FILTERED: picture is to small" unless size > 15000
      return cb null, pic

  filter.keywords_censored = (pic, cb) ->
    censored = require '../data/keywords_censored'
    if (_.reduce pic.keywords, ((memo, curr) -> memo or curr in censored), false)
      return cb new Error "FILTERED: picture contains explicit content"
    return cb null, pic

  filter.keywords_synomity = (pic, cb) ->
    synomity = require '../data/keywords_synomity'
    pic.keywords = _.map pic.keywords, (keyword) -> synomity[keyword] or keyword
    return cb null, pic

  filter.keywords_double = (pic, cb) ->
    checker = {}
    pic.keywords = _.filter pic.keywords, (keyword) ->
      return false if checker[keyword]?
      return checker[keyword] = true
    return cb null, pic

  filter.keywords_useless = (pic, cb) ->
    useless = require '../data/keywords_useless'
    pic.keywords = _.filter pic.keywords, (keyword) ->
      not (keyword in useless) and
      not (/[\d\W]/.test keyword) and
      not (keyword.length > 15) and
      not (keyword.length < 3)
    return cb null, pic

  filter.keywords_count = (pic, cb) ->
    return cb new Error "FILTERED: too little keywords" if pic.keywords.length < 3
    return cb null, pic

  # --- cache ------------------------------------------------------------------

  # cached are hot pics from:   05.07.14 - 08.07.14
  Flickr.cache = (opts, cb) ->
    opts.limit ?= Infinity
    pictures = require '../data/flickr_backup'
    return cb null, pictures[0...opts.limit]

  Flickr.cache.get_all = ->
    JSON.readFileSync '../data/flickr_backup.json'

  Flickr.cache.write_all = (pictures) ->
    JSON.writeFileSync '../data/flickr_backup.json', pictures

  Flickr.cache.count = ->
    Flickr.cache.get_all().length

  Flickr.cache.add = (new_pics) ->
    pictures = do Flickr.cache.get_all
    count = pictures.length
    new_pics = [new_pics] unless new_pics instanceof Array
    for new_pic in new_pics
      unless _.filter(pictures, (picture) -> picture.url is new_pic.url).length
        pictures.unshift _.pick new_pic, 'url', 'title', 'keywords'
    console.log "         added new to cache: #{pictures.length-count}"
    Flickr.cache.write_all pictures

  Flickr.cache.rm = (rm_urls) ->
    pictures = do Flickr.cache.get_all
    rm_urls = [rm_urls] unless rm_urls instanceof Array
    pictures = _.filter pictures, (pic) -> not (pic.url in rm_urls)
    Flickr.cache.write_all pictures

  Flickr.cache.filter = (done) ->
    pictures = do Flickr.cache.get_all
    async.reduce pictures, [], (pictures, picture, cb) ->
      filter picture, (err, picture) ->
        return cb null, pictures if err
        return cb null, pictures.concat picture
    , (err, result) ->
      Flickr.cache.write_all result
      do done

  # --- get pictures -----------------------------------------------------------

  Flickr.hot = (opts, cb) ->
    opts.limit ?= 1
    opts.random = not opts.date?
    opts.date ?= new Date Date.now() - 1000*60*60*24 * parseInt(Math.random()*356)
    opts.date = yyyymmdd(opts.date)
    get 'interestingness.getList', date:opts.date, per_page: 500, (err, result) ->
      return cb err if err
      return cb null, [] if result.stat isnt 'ok' or opts.limit is 0
      result.photos.photo = _.shuffle result.photos.photo if opts.random
      collect err, result.photos.photo, opts.limit, opts.date, cb

  Flickr.find = (opts, cb) ->
    opts.limit ?= 1
    opts.keywords ?= []
    keywords = opts.keywords.join ','
    get 'photos.search', per_page:500, keyword_mode: 'AND', keywords:keywords, (err, result) ->
      return cb err if err
      return cb null, [] if result.stat isnt 'ok' or opts.limit is 0
      result.photos.photo = _.shuffle result.photos.photo
      collect err, result.photos.photo, opts.limit, keywords, cb

  collect = (err, data, limit, infostring, cb) ->
    pictures = []
    crawled = 0
    add_one = ->
      if data.length is 0
        return cb null, pictures
        console.log "         wanted: #{amount} | crawled: #{crawled} | returned: #{pictures.length}"
      id = (do data.shift).id
      crawl id, (err, picture) ->
        crawled += 1
        return cb err if err
        filter picture, (err, picture) ->
          return do add_one if err
          pictures.push picture
          if pictures.length is amount
            console.log "         wanted: #{amount} | crawled: #{crawled} | returned: #{pictures.length}"
            return cb null, pictures
    available = data.length
    amount = Math.min limit, available
    console.log "pictures available: #{available} (#{infostring}) | limit: #{limit}"
    return cb null, [] if available is 0 or amount is 0
    async.times amount, add_one

  crawl = (id, cb) ->
    async.parallel
      sizes: (cb) ->
        get 'photos.getSizes', photo_id:id, (err, result) ->
          return cb err if err
          url = (_.filter result.sizes.size, (u) -> u.label is 'Medium')[0].source
          return cb null, url: url
      info: (cb) ->
        get 'photos.getInfo', photo_id:id, (err, result) ->
          return cb err if err
          return cb null,
            title: result.photo.title._content
            keywords: (obj._content for obj in result.photo.keywords.keyword when obj._content)
      , (err, all) ->
        return cb err if err
        return cb null, _.extend(all.sizes, all.info)

  get = (method, opts, cb) ->
    url = "https://api.flickr.com/services/rest/"
    request url, method:"flickr.#{method}", api_key:api_key, format:'json', nojsoncallback:1, opts, cb

  Flickr


# === youtube ==================================================================

MediaApi.Youtube = ->
  youtubeSearch = require 'youtube-search'
  Youtube = {}

  Youtube.find = (opts, cb) ->
    return unless cb
    opts.limit ?= 9
    opts.term ?= ''
    youtubeSearch.search opts.term, {maxResults:opts.limit, startIndex:1}, (err, results) ->
      return cb null, [] if err
      return cb null, (for video in results
        url: video.url
        title: video.title
        category: video.category
        author: video.author
        thumbnail: video.thumbnails[0].url
        )

  Youtube


# === itunes ===================================================================

MediaApi.iTunes = ->
  config =
    country: 'de'
    explicit: 'No'

  iTunes = {}
  iTunes.find = (opts, cb) ->
    return unless cb
    opts.term ?= ''
    opts.limit ?= 9
    request 'https://itunes.apple.com/search', config, media:'all', term:opts.term, limit:opts.limit, cb

  # --- music ------------------------------------------------------------------

  iTunes.music = {}
  iTunes.music.find = (opts, cb) ->
    return unless cb
    opts.term ?= ''
    opts.limit ?= 9
    request 'https://itunes.apple.com/search', config, media:'music', term:opts.term, limit:opts.limit, (err, result) ->
      return cb err if err
      # return cb err, result.results # full output
      return cb null, (for track in result.results
        wrapperType: track.wrapperType
        kind: track.kind
        preview: track.previewUrl
        artwork: track.artworkUrl100
        track:
          id: track.trackId
          name: track.trackName
          view: track.trackViewUrl
        artist:
          id: track.artistId
          name: track.artistName
          view: track.artistViewUrl
        collection:
          id: track.collectionId
          name: track.collectionName
          view: track.collectionViewUrl
        collection_artist:
          id: track.collectionArtistId
          name: track.collectionArtistName
        genre: track.primaryGenreName
        )

  # --- movie ------------------------------------------------------------------

  iTunes.movie = {}
  iTunes.movie.find = (opts, cb) ->
    return unless cb
    opts.term ?= ''
    opts.limit ?= 9
    request 'https://itunes.apple.com/search', config, media:'movie', term:opts.term, limit:opts.limit, (err, result) ->
      return cb err if err
      # return cb err, result.results # full output
      return cb null, (for movie in result.results
        wrapperType: movie.wrapperType
        kind: movie.kind
        preview: movie.previewUrl
        artwork: movie.artworkUrl100
        track:
          id: movie.trackId
          name: movie.trackName
          view: movie.trackViewUrl
        artist:
          name: movie.artistName
        collection:
          id: movie.collectionId
          name: movie.collectionName
          view: movie.collectionViewUrl
        collection_artist:
          id: movie.collectionArtistId
          view: movie.collectionArtistViewUrl
        genre: movie.primaryGenreName
        contentAdvisoryRating: movie.contentAdvisoryRating
        )

  iTunes
