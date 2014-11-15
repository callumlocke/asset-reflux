path = require 'path'
_ = require 'lodash'
async = require 'async'
chalk = require 'chalk'

Builder = require '../builder'
Workload = require '../workload'
Source = require '../source-file'
Destination = require '../destination'

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
    @rev = options.rev
    @inline = options.inline
    @debug = options.debug

    if @debug
      @log = (args...) =>
        args.unshift chalk[logColours[@id] || 'white']("engine_#{@id}")
        console.log.apply null, args
    else @log = (->)

    @readHook = options.readHook
    @processHook = options.processHook
    @writeHook = options.writeHook

    @destination = new Destination(this)

    if options.concat is true
      @concat = Infinity
    else if !options.concat
      @concat = 1
    else if _.isNumber options.concat
      @concat = options.concat
    else if options.concat?
      throw new TypeError 'Unexpected type for options.concat'

    @_builders = {}
    @_sources = {}


  getWorkloadId: ->
    if !@_lastId? then @_lastId = 1
    @_lastId++

  # method to get a Workload instance configured to use this engine
  workload: (buildPaths, changedPaths) ->
    console.assert Array.isArray buildPaths
    console.assert Array.isArray changedPaths

    new Workload this, buildPaths, changedPaths

  # caching instance-getters...
  getOrCreateBuilder: (files, isPrimary=false) ->
    id = Engine.getAssetId(files)

    if not @_builders[id]?
      @_builders[id] = new Builder
        files: files
        crawl: @crawl
        concat: @concat
        engine: this
        id: id
        isPrimary: isPrimary

    @_builders[id]

  getOrCreateSource: (file) ->
    @log 'getOrCreateSource', file

    if typeof file isnt 'string'
      throw new TypeError 'Expected string, not ' + typeof file

    if !@_sources[file]?
      @_sources[file] = new Source
        path: file
        engine: this

    @_sources[file]


  hasBuilder: (files) ->
    @_builders[Engine.getAssetId(files)]?


  purgeSource: (sourcePath) ->
    @log 'purgeSource', sourcePath, ' - exists:', @_sources[sourcePath]?

    if typeof sourcePath isnt 'string'
      throw new TypeError 'Expected string'

    # we delete the contents promise, not the sourceloader itself.
    @_sources[sourcePath]?_getContents = null

    # we should also unset the job on any builders for this source, forcing the next 'getJob' to make a new one (makes children work)
    for builderId, builder of @_builders
      if builder.files.indexOf(sourcePath) > -1
        @log "deleting builder.job for #{builderId} as part of purgeSource(#{sourcePath})"
        builder.previousJob = builder.job
        builder.job = null


  getReferringAncestorsOf: (childPath) ->
    # looking at all the latest builder jobs, find any that are referring ancestors of
    # the given childPath.

    # this could be recursive, but in reality it can only have parents and grandparents
    # (css image > css file > html file) so we just do it in 2 steps

    # first find any builders that directly use the given child path.
    childBuilders = []
    for own builderId, builder of @_builders
      if builder.files.indexOf(childPath) > -1
        childBuilders.push builder

    # now build an array of ancestor builders
    ancestors = []
    for childBuilder in childBuilders
      parents = childBuilder.getParentBuilders()
      for parent in parents
        ancestors.push parent unless ancestors.indexOf(parent) > -1

        grandparents = parent.getParentBuilders()
        for grandparent in grandparents
          ancestors.push grandparent unless ancestors.indexOf(grandparent) > -1

    ancestorPaths = []
    for ancestor in ancestors
      for file in ancestor.files
        ancestorPaths.push file

    return ancestorPaths


# class helper methods
Engine.getAssetId = (files) ->
  '_' + files.join(path.delimiter)
