# a builder instance is responsible for repeatedly building the same source file (or list of of source files, if they are to be concatenated) using consecutive Job instances.

_ = require 'lodash'
path = require 'path'
bufferEqual = require 'buffer-equal'
Promise = require 'bluebird'
Job = require './job'
Target = require './target-file'
helpers = require './helpers'
semicolonBuffer = new Buffer ';'
{EventEmitter} = require 'events'
chalk = require 'chalk'
URLSafeBase64 = require 'urlsafe-base64'
crypto = require 'crypto'

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
    @manager = options.manager
    @ext = path.extname @files[0]

    # get/create the source objects for this builder
    @sources = @files.map (file) => @manager.getOrCreateSource(file)

    @id = options.id

  # method to get the current job, whether it's running or finished.
  getJob: ->

    # start executing only if there has never been a job yet
    if not @job? then @execute()

    # return the current job (whether new or old)
    @job


  # gets a promise that resolves with an 'actioned' Job
  # instance, possibly one that has already been created. this method
  # ensures there is only one job going at a time.
  execute: (changedSourcePaths) ->

    # debounce jobs (leading:true, trailing:true)
    if @_executing
      console.log chalk.magenta('execute run while already running!'), @id
      throw new Error('Cannot execute this builder while it is already executing :(')
    @_executing = true

    # establish situation re: job instances
    @previousJob = @job
    @job = new Job
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
      filePath = 'concat-' + digest(new Buffer(@id)) + @ext
    else filePath = @sources[0].path

    if @rev && buffer?
      filePath = digest(buffer) + filePath

    filePath


  # gets the last completed job, or null
  getLastCompleteJob: ->
    if @job?._actioned?.isFulfilled()
      @job

    else if @previousJob?
      console.assert @previousJob._actioned.isFulfilled(), 'should be fulfilled at this point'
      @previousJob

    else null
