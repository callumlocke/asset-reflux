###
job.actioned()

THIS SHOULD BE DEPRECATED.
  it should be possible to just action all the outfiles/deletions at the end of the 'finalised' stage, as it can be synchronous.
###

Promise = require 'bluebird'
async = require 'async'

module.exports = ->
  if !@_actioned?
    @_actioned = new Promise (resolve) =>
      @finalised().then( =>
        @log 'job finalised'

        # emit output events for everything
        if @outfiles?
          for outfile in @outfiles
            @workload._outputFile outfile, @builder
        if @deletions?
          for deletion in @deletions
            console.assert deletion.contents is false
            @workload._outputFile deletion, @builder

        async.parallel([
          # ensure all children are actioned
          (done) =>
            @getJoinedContents().then((joinedContents) =>
              if @engine.crawl and joinedContents isnt false
                @log 'waiting for children to be actioned'

                @getChildren().then((children) =>
                  if children?
                    Promise.all(children.map((child) =>
                      child.job.actioned()
                    )).then(=>
                      @log 'children actioned'
                      if @_actioned.isFulfilled()
                        throw new Error 'why is this fullfilled already?'
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
