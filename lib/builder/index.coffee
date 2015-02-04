###
  Builder

  a builder is a reusable object responsible for building a particular multisource.
  each 'act' of building is a job instance.
###

_ = require 'lodash'
urlPath = require 'path-browserify'
bufferEqual = require 'buffer-equal'
Promise = require 'bluebird'
Job = require '../job'
helpers = require '../helpers'
{EventEmitter} = require 'events'
chalk = require 'chalk'
URLSafeBase64 = require 'urlsafe-base64'
crypto = require 'crypto'
semicolonBuffer = new Buffer ';'

defaults = {}

digest = (buffer) ->
  hash = crypto.createHash('sha1')
  hash.update(buffer)
  URLSafeBase64.encode(hash.digest()).substring(0, 6)


module.exports = class Builder extends EventEmitter

  constructor: (_options) ->
    EventEmitter.call this

    # process options
    options = _.assign {}, defaults, _options
    @files = (if _.isString options.files then [options.files] else options.files)
    @engine = options.engine
    @ext = urlPath.extname @files[0]
    @concat = options.concat
    @isPrimary = options.isPrimary

    # get/create the source objects for this builder
    @sources = @files.map (file) => @engine.getOrCreateSource(file)

    @id = options.id

  # method to get the current job, whether it's running or finished.
  # the workload id, if supplied, is only used if there is no job.
  getJob: (workloadId) ->

    # start executing only if there has never been a job yet
    if not @job? then @execute(null, workloadId)

    # return the current job (whether new or old)
    @job


  # gets a promise that resolves with an 'actioned' Job
  # instance, possibly one that has already been created. this method
  # ensures there is only one job running at a time.
  execute: (changedSourcePaths, workloadId) ->

    # debounce jobs (leading:true, trailing:true)
    if @_executing
      @log 'execute was run while already running!'
      throw new Error 'cannot execute this builder while it is already executing'
    @_executing = true

    # establish situation re: job instances
    if not workloadId? then throw new Error 'expected workloadId'
    @previousJob = @job if @job?

    @job = new Job
      workloadId: workloadId
      builder: this
      changedSourcePaths: changedSourcePaths

    new Promise (resolve, reject) =>
      @job.actioned().then (targets, refs) =>
        @_executing = false
        resolve(@job)
      , reject


  # gets the appropriate output file path for this builder - either something like `concat-2iyo8a.ext` or the file path, revved if necessary
  getPrimaryTargetPath: (buffer) ->
    if @sources.length > 1
      sourcePathsJoined = _.pluck(@sources, 'path').join('\n')
      filePath = 'concat-' + digest(new Buffer(sourcePathsJoined)) + @ext
    else filePath = @sources[0].path

    if @engine.rev && !@isPrimary
      if !buffer? then throw new Error 'trying to rev a builder without providing buffer! this should never happen'
      filePath = digest(buffer) + filePath

    filePath


  # # gets the last completed job, or null
  # getLastCompleteJob: ->
  #   if @job?._actioned?.isFulfilled()
  #     @job

  #   else if @previousJob?
  #     console.assert @previousJob._actioned.isFulfilled(), 'should be fulfilled at this point'
  #     @previousJob

  #   else null


  getParentBuilders: ->
    # return any immediate parents of this builder, based on the last job. i.e. builders that have children including this one. they will be child jobs, and we can see if this is the builder for those jobs.

    parents = []
    for own builderId, builder of @engine._builders
      continue if builder == this

      job = builder.job || builder.previousJob

      if !job?
        @engine.log 'no job or previousJob found in builder', builderId
      # console.assert job._actioned.isFulfilled()

      children = job?._getChildren?.value()

      if children?
        for child in children
          if child.job.builder == this
            parents.push builder

    parents
