###
  Workload constructor

  new Workload engine, buildPaths, changedPaths

  engine - the engine this workload belongs to (used for hooks).
  buildPaths - array of file paths to use as infiles for this workload.
  changedPaths - array of file paths that should be purged from any caches (often
  the same as buildPaths, but not always, e.g. you might have main.js in
  buildPaths but module.js in changedPaths).

  todo: move most caching/purging logic out of AR. only builder jobs need to be
  cached in AR, and these should be purgeable in one well defined place
###


Args = require 'args-js'
{EventEmitter} = require 'events'
Engine = require '../engine'
chalk = require 'chalk'

module.exports = class Workload extends EventEmitter
  constructor: ->
    EventEmitter.call this

    # validate arguments
    args = Args [
        engine: Args.OBJECT | Args.Required
        # _type: Engine
      ,
        buildPaths: Args.ARRAY | Args.Required
        _check: (arr) ->
          for item in arr
            return false if typeof item isnt 'string'
          true
      ,
        changedPaths: Args.ARRAY | Args.Required
        _check: (arr) ->
          for item in arr
            return false if typeof item isnt 'string'
          true
    ], arguments

    # configure this instance
    @engine = args.engine
    @id = @engine.getWorkloadId()
    @buildPaths = args.buildPaths
    @changedPaths = args.changedPaths

    if @engine.debug
      @log = =>
        @engine.log.apply @engine, [
          chalk.yellow("workload_#{@id}"),
          [].slice.call(arguments).map((arg) -> chalk.gray(JSON.stringify(arg))).join(' ')
        ]
    else @log = (->)

  # methods
  run: require './run'
