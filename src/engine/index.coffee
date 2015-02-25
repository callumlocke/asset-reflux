path = require 'path'
_ = require 'lodash'
async = require 'async'
chalk = require 'chalk'

Builder = require '../builder'
Workload = require '../workload'

defaults =
  crawl: false
  concat: false
  rev: false
  inline: false

# colours for different engine IDs
logColours =
  1: 'magenta'
  2: 'cyan'
  3: 'green'
  4: 'blue'
  5: 'gray'


module.exports = class Engine
  constructor: (options) ->
    options = _.assign {}, defaults, options

    @id = options.id || 999
    @crawl = options.crawl
    @concat = options.concat
    @verboseConcat = options.verboseConcat
    @rev = options.rev
    @inline = options.inline
    @debug = options.debug

    if @debug
      @log = (args...) =>
        args.unshift chalk[logColours[@id] || 'white']("engine_#{@id}")
        console.log.apply null, args
    else @log = (->)

    @readFile = options.readFile
    @finalise = options.finalise

    if options.concat is true
      @concat = Infinity
    else if !options.concat
      @concat = 1
    else if _.isNumber options.concat
      @concat = options.concat
    else if options.concat?
      throw new TypeError 'Unexpected type for options.concat'

    # hash of builders (with ids as keys)
    @_builders = {}

    # hash to act as a record of which outfiles were output by which builder(s) - used to determine 'orphaned' outfiles which need deleting
    # (key is outfile path; value is an array of builders)
    @_outfileBuilders = {}

  getWorkloadId: ->
    if !@_lastId? then @_lastId = 1
    @_lastId++

  # method to get a Workload instance configured to use this engine
  createWorkload: (entryPaths, purgePaths) ->
    console.assert Array.isArray entryPaths
    console.assert Array.isArray purgePaths

    new Workload this, entryPaths, purgePaths


  getOrCreateBuilder: (files, isEntry=false) ->
    id = Engine.getAssetId(files)

    if not @_builders[id]?
      @_builders[id] = new Builder
        files: files
        crawl: @crawl
        concat: @concat
        engine: this
        id: id
        isEntry: isEntry

    @_builders[id]


Engine.getAssetId = (files) ->
  '_' + files.join(path.delimiter)
