###
  workload.run()

  initialises and runs the workload. can only be done once per workload.
###

chalk = require 'chalk'
async = require 'async'
Promise = require 'bluebird'

module.exports = (callback) ->
  # ensure the workload can only run once
  if @_started then throw new Error 'Workload already running/ran.'
  @_started = true

  @allFinalised = new Promise (resolve, reject) =>
    for sourcePath in @changedPaths
      if @engine.debug
        if @engine._sources[sourcePath]?._getContents?
          @log chalk.magenta('deleting'), sourcePath
        else
          @log chalk.magenta('not cached'), sourcePath

      @engine._sources[sourcePath]?._getContents = null # TODO: don't purge in AR

    # run a build job for each source in parallel, and collect the results
    async.concat @buildPaths, (sourcePath, done) =>
      # find/create all builders that might need to be run due to this source being added/changed/deleted, and execute them all
      relevantBuilders = []

      @log "async.concat step for #{sourcePath}"

      # first the builder for this one
      relevantBuilders[0] = @engine.getOrCreateBuilder([sourcePath], true) # true means it's a primary builder, so it will never rev its primary target

      # CHECK: do we need to look for any parent jobs and rerun those if they refer
      # to something that has since been concat'd or revved or should be inlined?
      # or is that taken care of already?

      async.map relevantBuilders, (builder, done) =>
        if not @id? then throw 'should not happen'
        builder
          .execute(@changedPaths, @id)
          .then((job) =>
            @log "#{@engine.id}-#{@id} 'relevant builder' executed: #{builder.id}"
            done null, job
            return
          )
        return


      , done
      return

    , (err, jobs) =>
      # this workload is finished.
      @_workloadRunning = false

      if err?
        reject err
        return

      # call back with all the primary jobs' results
      callback null, jobs.map((job) => job.getResults()).map((results) =>
        results.filter (result) => result? && result.workloadId == @id
      )

    return

  this
