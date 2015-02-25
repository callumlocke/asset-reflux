###
  job.getChildren()

  returns a promise that resolves with an array of 'child' objects.

  a child is an object containing a job, a 'reference details' object, and an array of the *resolved* urls derived from that reference details objects. (urls plural because concatenation)
###

Promise = require 'bluebird'
findAssets = require 'find-assets'
_ = require 'lodash'
urlPath = require 'path-browserify'

getBaseRelativeURL = (refererRelativeURL, referer) ->
  if refererRelativeURL.charAt(0) == '/'
    refererRelativeURL.substring(1)
  else
    urlPath.resolve('/' + urlPath.dirname(referer), refererRelativeURL).substring(1)


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
                getBaseRelativeURL url, @builder.getPrimaryOutfileURL()

              job = @engine.getOrCreateBuilder(
                resolvedURLPaths, false
              ).getJob(@workload, @builder.engine.rev)

              { resolvedURLPaths, job, details }
            )

          @log 'getJoinedChildren', children

          resolve(children)

    @_getChildren
