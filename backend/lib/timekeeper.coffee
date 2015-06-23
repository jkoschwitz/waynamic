TimeKeeper = exports? and exports or @TimeKeeper = {}

times = {}

TimeKeeper.start = (name) ->
  times[name] = new Date()
  console.info " ◷ START #{name}"

TimeKeeper.stop = (name) ->
  return console.log " ◷ ERROR: no '#{name}' registered" unless times[name]
  console.info " ◷ FINISHED #{name} in %dms", new Date() - times[name]

