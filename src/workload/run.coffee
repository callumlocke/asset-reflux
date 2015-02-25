###
  workload.run()

  initialises and runs the workload. can only be done once per workload.
###

chalk = require 'chalk'
async = require 'async'
Promise = require 'bluebird'
lightArray = require 'light-array'
XFile = require 'x-file'

module.exports = (callback) ->
  # ensure the workload can only run once
  if @_started then throw new Error 'Workload already running/ran.'
  @_started = true

  if @engine._workloadRunning then throw new Error 'Cannot run two workloads at once'
  @engine._workloadRunning = true

  @allFinalised = new Promise (resolve, reject) =>
    # run a build job for each source in parallel, and collect the results
    async.concat @entryPaths, (entryPath, done) =>
      # find/create all builders that might need to be run due to this source being added/changed/deleted, and execute them all
      relevantBuilders = []

      @log "async.concat step for #{entryPath}"

      # first the builder for this one
      relevantBuilders[0] = @engine.getOrCreateBuilder([entryPath], true) # true means it's an entry builder, so it will never rev its primary outfile

      # CHECK: do we need to look for any parent jobs and rerun those if they refer
      # to something that has since been concat'd or revved or should be inlined?
      # or is that taken care of already?

      async.map relevantBuilders, (builder, done) =>
        if not @id? then throw 'should not happen'
        builder
          .execute(@purgePaths, this)
          .then((job) =>
            @log "#{@engine.id}-#{@id} 'relevant builder' executed: #{builder.id}"
            done null, job
            return
          )
        return
      , done
      return

    , (err, jobs) =>
      # this workload is (nearly) finished.
      if err?
        reject err
        return

      # add deletions!
      do =>
        # identify builders that have become orphaned due to this workload of jobs
        orphanedBuilders = []
        for own builderId, builder of @engine._builders
          if builder.isOrphaned()
            orphanedBuilders.push builder

        # console.log 'ORPHANED BUILDERS'
        # console.log orphanedBuilders

        # remove those orphaned builders from the outfileBuilders record
        for own outfile, buildersList of @engine._outfileBuilders
          # remove `builder` from `buildersList`, if present
          for builder, i in buildersList
            if orphanedBuilders.indexOf(builder) != -1
              lightArray.removeItemByIndex buildersList, i

          # if this outfile is now orphaned, emit a deletion!
          if buildersList.length == 0
            @log 'deleting orphaned outfile:', outfile
            @_outputFile new XFile(path: outfile, contents: false), false
            delete @engine._outfileBuilders[outfile]

      # call back
      @_started = false
      @engine._workloadRunning = false
      callback null, @filesOutput

    return

  this
