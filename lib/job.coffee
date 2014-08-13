# a job belongs to one builder, and orchestrates a single act of executing that builder. it lingers afterwards and can be reused by other builders that might need to know its contents.

_ = require 'lodash'
Promise = require 'bluebird'
findAssets = require 'find-assets'
Target = require './target-file'
helpers = require './helpers'
async = require 'async'
chalk = require 'chalk'

semicolonBuffer = new Buffer ';' # for joining scripts

module.exports = class Job

  constructor: (options) ->
    @builder = options.builder

    # for debugging
    @id = @builder.id + '_' + _.uniqueId()
    @log = =>
      return unless @manager.debug

      console.log chalk.yellow(JSON.stringify(@id)), [].slice.call(arguments).map((arg) -> chalk.gray(JSON.stringify(arg))).join(' ')

    @manager = @builder.manager
    @previousJob = @builder.previousJob

    @changedSourcePaths = options.changedSourcePaths

    # start immediately - a job can't exist without being either started or done, there is no 'waiting' state
    @actioned()


  # gets a promise that @joinedContents has been set to either a buffer or `false`
  getJoinedContents: ->
    if !@_getJoinedContents?
      @_getJoinedContents = new Promise (resolve, reject) =>
        @log 'getting joined contents for sources', _.pluck(@builder.sources, 'path')

        promises = @builder.sources.map (source) -> source.getContents()

        Promise.all(promises).then (buffers) =>
          # see if any are false (not found)
          if buffers.indexOf(false) isnt -1
            missingSources = @builder.sources.filter (source, i) =>
              buffers[i] is false
            @missingSources = _.pluck(missingSources, 'path') # indicates this job failed
            resolve(false) # yes resolve with this error
            return

          if buffers.length == 1
            @log 'only one source; buffer length is ' + buffers[0].length
            resolve(buffers[0])
          else
            if @builder.ext is 'js' && @builder.manager.semicolons != false
              withSemicolons = []
              buffers.forEach (buffer) ->
                withSemicolons.push buffer
                withSemicolons.push semicolonBuffer
              withSemicolons.pop()
              buffers = withSemicolons
            resolve(Buffer.concat(buffers))

    @_getJoinedContents


  # gets an array of objects detailing jobs and reference details
  getChildren: ->
    if !@_getChildren?
      @_getChildren = new Promise (resolve) =>
        console.assert @builder.manager.crawl is true

        @getJoinedContents().then (joinedContents) =>
          console.assert Buffer.isBuffer(joinedContents)

          allReferenceDetails = switch @builder.ext
            when '.html' then findAssets.html(joinedContents.toString(), !!@builder.concat)
            when '.css'  then [] #findAssets.css(joinedContents.toString())
            else null

          children = null
          if allReferenceDetails?
            children = allReferenceDetails.map((details) =>
              resolvedURLPaths = _.pluck(details, 'url').map (url) =>
                helpers.getBaseRelativeURL(url, @builder.getPrimaryTargetPath())

              job = @manager.getOrCreateBuilder(resolvedURLPaths, {
                rev: @builder.manager.rev
              }).getJob()

              { resolvedURLPaths, job, details }
            )

          resolve(children)

    @_getChildren


  # state-managing promises...

  # `.finalised()` gets a promise that the job is in a finalised state,
  # meaning one of the following has been established:
  # @targets OR @missingSources OR @beforeFinaliseError
  # ...and also any child jobs are finalised too (if applicable).
  # but a finalised job has not necessarily written anything to the target directory yet.
  finalised: ->
    if !@_finalised?
      @_finalised = new Promise (resolve) =>
        @getJoinedContents().then((joinedContents) =>
          Promise.all([

            # establish @targets or @missingSources
            new Promise (resolve) =>
              (new Promise (resolve) =>

                # establish the final buffer (after rewriting refs)
                if @manager.crawl && joinedContents isnt false
                  @getChildren().then (children) =>
                    if children?
                      newString = do =>
                        oldString = joinedContents.toString()
                        if not refs? then return oldString

                        newString = ''
                        lastIndex = 0
                        refs.forEach (ref) =>
                          refStart = ref.details[0].start
                          refEnd = ref.details[ref.details.length - 1].end

                          newPath = ref.builder.getPrimaryTargetPath() # will this get revved if nec?

                          # TODO: do this properly.
                          newElement = switch ref.builder.ext
                            when '.js' then '<script src="' + newPath + '"></script>'
                            when '.css' then '<link rel="stylesheet" href="' + newPath + '">'
                            else '<todo src="' + newPath + '"></todo>'

                          newString += (
                            oldString.substring(lastIndex, refStart) +
                            newElement
                          )
                          lastIndex = refEnd
                        newString += oldString.substring(lastIndex)
                        newString

                      resolve(new Buffer(newString))

                    else resolve(joinedContents)
                else resolve(joinedContents) # no crawling; just pass the same
                                             # buffer straight through
              ).then((preFinalBuffer) =>

                if preFinalBuffer is false
                  console.assert @missingSources.length
                  resolve()
                else
                  @log 'preFinalBuffer length', preFinalBuffer.length

                  # we definitely need to make a targets array, unless the `process` hook fails
                  primaryTarget = new Target @builder.manager.dest,
                    path: @builder.getPrimaryTargetPath(preFinalBuffer) # may be revved
                    buffer: preFinalBuffer

                  # run the user's process hook
                  @builder.manager.process.call null, primaryTarget, @changedSourcePaths, (err, targets) =>
                    @log 'process hook had error?', err?

                    if err?
                      @beforeFinaliseError = err
                      resolve()
                    else
                      @targets = targets.map (target) =>
                        return target if target instanceof Target
                        return new Target @manager.dest, target
                      resolve()
              )
            ,

            # ensure all child jobs are finalised
            new Promise (resolve) =>
              if @manager.crawl && joinedContents isnt false
                @getChildren().then((children) =>
                  if children?
                    @log 'waiting for crawled children to be finalised'
                    Promise.all(children.map((child) =>
                      child.job.finalised()
                    )).then((results) =>
                      @log 'CHILDREN FINALISED', results.length
                      resolve()
                      return
                    )
                  else resolve()
                )
              else
                @log 'not waiting for children to finalise'
                resolve()

          ]).then((results) =>
            # now all targets are known, we can see which ones from
            # the previousJob's targets are no longer there, and make
            # @deletions for them.

            if @previousJob? && @previousJob.targets?
              if @targets?
                targetPaths = _.pluck @targets, 'path'
                @deletions = @previousJob.targets.filter (target) =>
                  targetPaths.indexOf(target.path) is -1
              else @deletions = @previousJob.targets # all of them!

            @log 'FINALISED DELETIONS', @deletions
            @log 'RESOLVING FINALISED NOW', results

            resolve()
          )
        )

    @_finalised


  # `.actioned()` gets a promise that everything is finalised, plus
  # the @targets have been augmented with details of how much data got
  # written, plus @deletions has been created and all of them
  # actioned... plus all the above is true for all child jobs (and all
  # descendents).
  actioned: ->
    if !@_actioned?
      @_actioned = new Promise (resolve) =>
        @finalised().then( =>
          @log 'job finalised'

          async.parallel([

            # write this job's targets
            (done) =>
              @log 'writing this job\'s targets - ' + (@targets?.length)

              if @targets?
                Promise.all(@targets.map((target) =>
                  @log 'writing target ' + target.path + ' - length ' + target.buffer.length
                  target.write()
                )).then(=>
                  @log 'written targets.'
                  done()
                )

              else done()
              return
            ,

            # carry out @deletions
            (done) =>
              return done() unless @deletions?

              async.each @deletions, (oldTarget, done) =>
                oldTarget.delete(done)
              , done
              return
            ,

            # ensure all children have also been actioned
            (done) =>
              @getJoinedContents().then((joinedContents) =>
                if @manager.crawl and joinedContents isnt false
                  @log 'waiting for crawled children to be actioned'
                  # @log 'joinedContents', (if joinedContents then joinedContents.length else joinedContents)

                  @getChildren().then((children) =>
                    if children?
                      Promise.all(children.map((child) =>
                        child.job.actioned()
                      )).then( (results) =>
                        @log 'CHILDREN ACTIONED', results.length
                        if @_actioned.isFulfilled()
                          throw new Error '!?!?!? why is this fullfilled already?'
                        done()
                      )
                    else
                      @log 'NO CHILDREN TO ACTION'
                      done()
                  )
                else
                  @log 'NOT CRAWLED'
                  done()
                return
              )

              return

          ], (err) =>
            if err? then throw err
            @log 'RESOLVING ACTIONED NOW'
            resolve()
          )
          return
        )
        return

    @_actioned



  # other stuff...

  getResults: ->
    @log 'getResults called'

    if not @_actioned.isFulfilled()
      @log '❗️  job is not yet actioned'
      throw new Error 'getResults called before job was completed'

    written = null
    deleted = null
    missingSources = null # warnings that no source could be found for
                          # some crawled reference

    written = @targets?.map (target) =>
      {
        file: target.path
        # file: target.id
        newSize: target.buffer.length
        oldSize: null # todo (nb: false means didn't exist; 0 means
                      # zero size)
      }

    deleted = @deletions?.map (deletion) =>
      {
        file: deletion.path
        oldSize: null # todo
      }

    missingSources = @missingSources?.map (ms) =>
      { file: ms }

    # add all the children
    joinedContents = @_getJoinedContents.value()
    if @manager.crawl && joinedContents isnt false

      children = @_getChildren.value()

      if children?
        for child in children
          childResults = child.job.getResults()
          if childResults.written?
            if !written? then written = childResults.written
            else written = written.concat childResults.written

          if childResults.deleted?
            if !deleted then deleted = childResults.deleted
            else deleted = deleted.concat childResults.deleted

          if childResults.missingSources?
            if !missingSources
              missingSources = childResults.missingSources
            else missingSources = missingSources.concat(
              childResults.missingSources
            )

          # { resolvedURLPaths, job, details }

    {written, deleted, missingSources}


  # template: ->
  #   if !@_template?
  #     @_template = new Promise (resolve, reject) =>
  #   @_template
