###
  job.finalised()

  'finalised' means one of the following has been established:
    .targets or .missingSources or .beforeFinaliseError
  ...and also any child jobs are finalised too

  THE ABOVE COMMENT IS OUT OF DATE.
###

Promise = require 'bluebird'
XFile = require 'x-file'
_ = require 'lodash'
urlPath = require 'path-browserify'

module.exports = ->
  if !@_finalised?
    @_finalised = new Promise (resolve, reject) =>

      @getJoinedContents().then((joinedContents) =>
        if joinedContents && !Buffer.isBuffer(joinedContents)
          @log 'strange error', joinedContents
          return reject new Error('joinedContents should be buffer or false')

        Promise.all([

          # establish @outfiles or @missingSources
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

                        newPath = child.job.builder.getPrimaryOutfileURL() # will this get revved if nec?

                        # make the newPath relative to this builder/job's dirname
                        newPath = urlPath.relative(
                          urlPath.dirname(@builder.getPrimaryOutfileURL())
                          newPath
                        )

                        # TODO: preserve other attributes that might be on it, by just using
                        # whatever is in child.details[child.details.length-1].string, and overwriting
                        # the relevant attribute.
                        newElement = switch child.details[0].type
                          when 'script' then '<script src="' + newPath + '"></script>'
                          when 'stylesheet' then '<link rel="stylesheet" href="' + newPath + '">'
                          when 'import' then '<link rel="import" href="' + newPath + '">'
                          when 'img' then '<img src="' + newPath + '">'

                        if !newElement? then throw new Error "don't know what to do with #{child.details[0].type}"

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

                # we definitely need to make a outfiles array, unless the `process` hook fails
                primaryOutfile = new XFile(
                  @builder.getPrimaryOutfilePath(preFinalBuffer), # may be revved
                  preFinalBuffer
                )

                # run the user's process hook
                @builder.engine.processHook.call null, primaryOutfile, @purgePaths, (err, outfiles) =>
                  @log 'process hook had error?', err?

                  if err?
                    @beforeFinaliseError = err
                    resolve()
                  else
                    if Array.isArray outfiles
                      @outfiles = outfiles
                    else if outfiles?
                      @outfiles = [outfiles]
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
                  )).then(=>
                    @log 'children finalised'
                    resolve()
                    return
                  )
                else resolve()
              )
            else
              @log 'not waiting for children to finalise'
              resolve()

        ]).then(() =>
          # add basic deletions (for any files that were output by this builder's
          # previous job, but weren't output by this one)

          previousJob = @builder.previousJob

          @log 'previousJob exists:', previousJob?
          @log 'previousJob outfiles:', previousJob?.outfiles

          if previousJob? && previousJob.outfiles?
            if @outfiles?
              outfilePaths = _.pluck @outfiles, 'path'
              @deletions = previousJob.outfiles.filter (outfile) =>
                outfilePaths.indexOf(outfile.path) is -1
            else @deletions = previousJob.outfiles # all of them!
          @log 'finalised deletions', @deletions

          # turn them into actual deletions (i.e. false contents)
          if @deletions?
            for deletion, i in @deletions
              @deletions[i] = new XFile
                path: deletion.path
                contents: false

          @log 'resolving finalised now'
          resolve()
        )
      )

  @_finalised
