###
  job.finalised()

  'finalised' means one of the following has been established:
    .targets or .missingSources or .beforeFinaliseError
  ...and also any child jobs are finalised too
###

Promise = require 'bluebird'
File = require 'x-file'
_ = require 'lodash'

module.exports = ->
  if !@_finalised?
    @_finalised = new Promise (resolve, reject) =>

      @getJoinedContents().then((joinedContents) =>
        if joinedContents && !Buffer.isBuffer(joinedContents)
          @log 'strange error', joinedContents
          return reject new Error('joinedContents should be buffer or false')

        Promise.all([

          # establish @targets or @missingSources
          new Promise (resolve) =>

            (new Promise (resolve) =>

              # establish the final buffer (after rewriting refs)
              if @engine.crawl && joinedContents != false
                @log 'establishing prefinal buffer..?'

                @getChildren().then (children) =>
                  if children?

                    newString = do =>
                      oldString = joinedContents.toString()

                      if not children? then return oldString

                      newString = ''
                      lastIndex = 0
                      children.forEach (child) =>
                        refStart = child.details[0].start
                        refEnd = child.details[child.details.length - 1].end

                        newPath = child.job.builder.getPrimaryTargetPath() # will this get revved if nec?

                        # TODO this properly
                        newElement = switch child.job.builder.ext
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
                primaryTarget = new File(
                  @builder.getPrimaryTargetPath(preFinalBuffer), # may be revved
                  preFinalBuffer
                )

                # run the user's process hook
                @builder.engine.processHook.call null, primaryTarget, @changedSourcePaths, (err, targets) =>
                  @log 'process hook had error?', err?

                  if err?
                    @beforeFinaliseError = err
                    resolve()
                  else
                    # @targets = targets.map (target) =>
                    #   return target if target instanceof File
                    #   return new File target.path, (target.contents || target.string || null)
                    @targets = targets
                    resolve()
            )
          ,

          # wait for all child jobs to be finalised
          new Promise (resolve) =>
            if @engine.crawl && joinedContents isnt false
              @getChildren().then((children) =>
                if children?
                  @log 'waiting for crawled children to be finalised'
                  Promise.all(children.map((child) =>
                    child.job.finalised()
                  )).then((results) =>
                    @log 'children finalised', results.length
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
          previousJob = @builder.previousJob

          @log 'previousJob exists:', previousJob
          @log 'previousJob targets:', previousJob?.targets

          if previousJob? && previousJob.targets?
            if @targets?
              targetPaths = _.pluck @targets, 'path'
              @deletions = previousJob.targets.filter (target) =>
                targetPaths.indexOf(target.path) is -1
            else @deletions = previousJob.targets # all of them!
          @log 'finalised deletions', @deletions

          @log 'resolving finalised now', results
          resolve()
        )
      )

  @_finalised