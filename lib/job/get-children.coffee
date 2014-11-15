###
  job.getChildren()

  returns a promise that resolves with an array of 'child' objects.

  a child is an object containing a job, a 'reference details' object, and an array of the *resolved* urls derived from that reference details objects. (urls plural because concatenation)
###

Promise = require 'bluebird'
findAssets = require 'find-assets'
_ = require 'lodash'
helpers = require '../helpers'

module.exports = ->
    if !@_getChildren?
      @_getChildren = new Promise (resolve) =>
        console.assert @builder.engine.crawl is true

        @getJoinedContents().then (joinedContents) =>
          console.assert Buffer.isBuffer(joinedContents)

          allReferenceDetails = switch @builder.ext
            when '.html' then findAssets.html(joinedContents.toString(), @builder.concat)
            when '.css'  then [] #findAssets.css(joinedContents.toString())
            else null

          children = null
          if allReferenceDetails?
            children = allReferenceDetails.map((details) =>
              resolvedURLPaths = _.pluck(details, 'url').map (url) =>
                helpers.getBaseRelativeURL(url, @builder.getPrimaryTargetPath())

              job = @engine.getOrCreateBuilder(
                resolvedURLPaths, true
              ).getJob(@workloadId, @builder.engine.rev)

              { resolvedURLPaths, job, details }
            )

          resolve(children)

    @_getChildren
