###
  Workload constructor
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
        entryPaths: Args.ARRAY | Args.Required
        _check: (arr) ->
          for item in arr
            return false if typeof item isnt 'string'
          true
      ,
        purgePaths: Args.ARRAY | Args.Required
        _check: (arr) ->
          for item in arr
            return false if typeof item isnt 'string'
          true
    ], arguments

    # configure this instance
    @engine = args.engine
    @id = @engine.getWorkloadId()
    @entryPaths = args.entryPaths
    @purgePaths = args.purgePaths

    @filesOutput = []

    if @engine.debug
      @log = =>
        @engine.log.apply @engine, [
          chalk.yellow("workload_#{@id}"),
          [].slice.call(arguments).map((arg) -> chalk.gray(JSON.stringify(arg))).join(' ')
        ]
    else @log = (->)


  _outputFile: require './_output-file'
  run: require './run'
