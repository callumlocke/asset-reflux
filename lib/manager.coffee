# this is the main class, exported as require('asset-reflux').

path = require 'path'
_ = require 'lodash'
async = require 'async'
Builder = require './builder'
Source = require './source-file'
Target = require './target-file'
chalk = require 'chalk'

defaults =
  loadPaths: {}


module.exports = class Manager
  constructor: (options) ->
    options = _.assign {}, defaults, options
    @src = path.relative process.cwd(), options.src
    @dest = path.relative process.cwd(), options.dest
    @DEBUG = options.debug
    @crawl = options.crawl
    @rev = options.rev
    @process = options.process # user's hook for modifying stuff before it's finalised

    if options.concat is true
      @concat = Infinity
    else if !options.concat
      @concat = 1
    else if _.isNumber options.concat
      @concat = options.concat
    else if options.concat?
      throw new TypeError 'Unexpected type for options.concat'

    if _.isString options.loadPaths
      @loadPaths = {}
      @loadPaths[options.loadPaths] = '.'
    else if _.isArray options.loadPaths
      @loadPaths = {}
      for loadPath in options.loadPaths
        @loadPaths[loadPath] = '.'
    else @loadPaths = options.loadPaths

    @debug = options.debug
    @_builders = {}
    @_sources = {}

    _dest = @dest
    @Target = (options) ->
      Target.call this, _dest, options


  runWorkload: (sourcePaths, changedSourcePaths, callback) ->
    if @_ecRunning then throw new Error 'Execution cluster already running'
    @_ecRunning = true

    # nb: `sourcePaths` contains the paths to build; `changedSourcePaths` contains the paths that need to be purged from any caches (either reflux Sources' memoized `getContents` promises, or in-transform caches).

    # validate args
    if not _.isArray sourcePaths
      throw new TypeError 'Expected sourcePaths to be an array'
    for sp in sourcePaths
      if not _.isString sp
        throw new TypeError 'Expected all source paths to be strings'

    # delete any cached source contents
    for sourcePath in changedSourcePaths
      if @debug
        if @_sources[sourcePath]?._getContents?
          console.log chalk.magenta('deleting'), sourcePath
        else
          console.log chalk.magenta('not cached'), sourcePath

      delete @_sources[sourcePath]?._getContents

    # run an execution for each source in parallel, and collect the results
    async.concat sourcePaths, (sourcePath, done) =>
      # find/create all builders that might need to be run due to this source being added/changed/deleted, and execute them all
      relevantBuilders = []

      # first the builder for this one
      relevantBuilders[0] = @getOrCreateBuilder([sourcePath])

      ###
        this next bit doesn't work yet. it's for situations where this workload is for source path 'foo.css', and revving or concat is enabled, so any files that caused crawling of that one (index.html) would need to have their refs rewritten.

        in fact, thinking about it, it would probably be better to just re-run the job for the .html files instead (or part of it), which would result in the file being re-crawled and then, because its source has been deleted above, the job would be re-run.
      ###
      # # now add any extra builders that might already have executions that relied on this one
      # for builder in @_builders
      #   if builder is relevantBuilders[0] then continue
      #   # find the last complete execution
      #   execution = builder.getLastCompleteExecution()
      #   if execution?
      #     if execution.usedSourcePath(sourcePath)
      #       relevantBuilders.push(builder)

      async.map relevantBuilders, (builder, done) =>
        builder
          .execute(changedSourcePaths)
          .then((execution) ->
            done(null, execution)
            return
          )
      , done
      return

    , (err, executions) =>
      if err?
        @_ecRunning = false
        callback err
        return

      # call back with all the primary executions' results
      @_ecRunning = false
      callback null, executions.map((e) -> e.getResults())
      return

    return


  # caching instance-getters...

  getOrCreateBuilder: (files) ->
    id = Manager.getAssetId(files)

    if not @_builders[id]?
      @_builders[id] = new Builder
        files: files#.map (file) => @getOrCreateSource file
        crawl: @crawl
        concat: @concat
        manager: this
        id: id

    @_builders[id]

  getOrCreateSource: (file) ->
    if not _.isString(file)
      throw new TypeError 'Expected string, not ' + typeof file

    if not @_sources[file]?
      @_sources[file] = new Source
        path: file
        manager: this

    @_sources[file]


  hasBuilder: (files) ->
    @_builders[Manager.getAssetId(files)]?


# class helper methods
Manager.getAssetId = (files) ->
  '_' + files.join('\n')


module.exports.Target = Target
