###
job.actioned() - TO BE DEPRECATED

returns a promise that everything is
- finalised
- written to the engine's (virtual) destination
- job.targets have been augmented with details of how much data got written for each
- job.deletions has been created and all of them actioned...
- plus all child (and grandchild...) jobs have been actioned too.
###

Promise = require 'bluebird'
async = require 'async'
File = require 'x-file'

module.exports = ->
  if !@_actioned?
    @_actioned = new Promise (resolve) =>
      @finalised().then( =>
        @log 'job finalised'

        # array to contain the destination's write results
        @results = [] if @targets? || @deletions?

        async.parallel([

          # write this job's targets
          (done) =>
            @log 'writing this job\'s targets ' + (@targets?.length || '(none)')

            if @targets?
              async.each @targets, (target, done) =>
                @log 'writing target ' + target.path + ' - length ' + target.contents.length
                @destination.write target, @workloadId, (err, result) =>
                  if err? then return done err
                  @results.push result
                  done()

              , (err) =>
                @log (if err? then 'failed to write targets' else "wrote #{@targets.length} targets")
                done(err)

            else done()
            return
          ,

          # carry out @deletions
          (done) =>
            return done() unless @deletions?

            async.each @deletions, (oldTarget, done) =>
              @log 'deleting old target ' + oldTarget.path

              deletion = new File oldTarget.path, false

              @destination.write deletion, @workloadId, (err, result) =>
                if err? then return done err
                @results.push result
                done()

            , done
            return
          ,

          # ensure all children are also actioned
          (done) =>
            @getJoinedContents().then((joinedContents) =>
              if @engine.crawl and joinedContents isnt false
                @log 'waiting for crawled children to be actioned'

                @getChildren().then((children) =>
                  if children?
                    Promise.all(children.map((child) =>
                      child.job.actioned()
                    )).then( (results) =>
                      @log 'children actioned', results.length
                      if @_actioned.isFulfilled()
                        throw new Error '!?!?!? why is this fullfilled already?'
                      done()
                    )
                  else
                    @log 'no children to action'
                    done()
                )
              else
                @log 'not crawled'
                done()
              return
            )

            return

        ], (err) =>
          if err? then throw err
          @log 'resolving as actioned now'
          resolve()
        )
        return
      )
      return

  @_actioned
