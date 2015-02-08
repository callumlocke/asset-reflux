###
  Builder

  a builder is a reusable object responsible for building a particular *post-concat* file.

  a builder is [re]used by calling .execute(), which uses a Job instance to manage the whole build process.
###

_ = require 'lodash'
path = require 'path'
urlPath = require 'path-browserify'
bufferEqual = require 'buffer-equal'
Promise = require 'bluebird'
Job = require '../job'
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
    @engine = options.engine
    @ext = urlPath.extname @files[0]
    @concat = options.concat
    @isEntry = options.isEntry

    # validate
    for filePath in @files
      console.assert filePath.charAt(1) isnt '.' and filePath.charAt(1) isnt '/', "invalid: #{filePath}"

    @id = options.id

  # method to get the current job, whether it's running or finished.
  # the workload id, if supplied, is only used if there is no job.
  getJob: (workload) ->

    # start executing only if there has never been a job yet
    if not @job? then @execute(null, workload)

    # return the current job (whether new or old)
    @job


  # gets a promise that resolves with an 'actioned' Job
  # instance, possibly one that has already been created. this method
  # ensures there is only one job running at a time.
  execute: (purgePaths, workload) ->

    # debounce jobs (leading:true, trailing:true)
    if @_executing
      @log 'execute was run while already running!'
      throw new Error 'cannot execute this builder while it is already executing'
    @_executing = true

    # establish situation re: job instances
    if not workload? then throw new Error 'expected workload'
    @previousJob = @job if @job?

    # make a new job
    @job = new Job
      workload: workload
      builder: this
      purgePaths: purgePaths

    # return a promise that the job is done (actioned)
    new Promise (resolve, reject) =>
      @job.actioned().then (outfiles, refs) =>
        @_executing = false
        resolve(@job)
      , reject


  # gets the appropriate output file path for this builder - either something
  # like `concat-2iyo8a.ext` or the file path, revved using `buffer` if provided
  getPrimaryOutfilePath: (buffer=null) ->
    if @files.length > 1
      if @engine.verboseConcat
        filePath = (
          'concat-' +
          @files.map((filePath) ->
            filePath
              .substr(0, filePath.lastIndexOf('.'))
              .split(path.sep).join('__')
          ).join('___') +
          @ext
        )
      else
        filePath = 'concat-' + digest(new Buffer(@files.join('\n'))) + @ext

    else filePath = @files[0]

    if @engine.rev && !@isEntry
      if !buffer? then throw new Error 'trying to rev a builder without providing buffer, this should never happen'
      filePath = digest(buffer) + filePath

    filePath


  getPrimaryOutfileURL: (buffer) ->
    url = @getPrimaryOutfilePath buffer

    # make it use forward slashes if we're on windows or something
    if path.sep isnt '/'
      url = url.split(path.sep).join('/')

    url


  getReferringBuilders: ->
    # return any immediate referrers of this builder, based on its last job. i.e. builders that have children including this one. they will be child jobs, and we can see if this is the builder for those jobs.

    referers = []
    for own builderId, builder of @engine._builders
      continue if builder == this

      job = builder.job || builder.previousJob

      if !job?
        @engine.log 'no job or previousJob found in builder', builderId
      console.assert job._actioned.isFulfilled()

      children = job?._getChildren?.value()

      if children?
        for child in children
          if child.job.builder == this
            referers.push builder

    referers


  isOrphaned: ->
    # if this is an entry, it can't be an orphan
    if @isEntry
      @engine.log "builder #{@id} not an orphan because it is an entry"
      return false

    referers = @getReferringBuilders()

    # if no referers, it's an orphan
    if !referers.length
      @engine.log "builder #{@id} confirmed orphan because no referers"
      return true

    # if any referers are entries, it's not an orphan
    for referer in referers
      if referer.isEntry
        @engine.log "builder #{@id} not an orphan because referer '#{referer.id}' is an entry"
        return false

    # TODO ======
    # # look through referers of referers until one of them is an entry
    # ancestors = referers
    # loop
    #   lengthBefore = ancestors.length
    #   referers = @getReferringBuilders()
    #   ancestors = ancestors.concat ... getReferringBuilders()
    #   # break if no change on this iteration
    #   if ancestors.length == lengthBefore
    #     break

    # if still not found any, this builder is orphaned
    return true
