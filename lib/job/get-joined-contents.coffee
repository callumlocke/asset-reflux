###
  job.getJoinedContents()

  returns a promise that resolves with the infile contents, which might be from a single file or joined together from multiple files.

  the contents will be either a buffer or `false`. the latter means one or more of the sources couldn't be loaded.
###

Promise = require 'bluebird'
_ = require 'lodash'

module.exports = ->
  if !@_getJoinedContents?
    @_getJoinedContents = new Promise (resolve, reject) =>
      @log 'getting joined contents for sources', _.pluck(@builder.sources, 'path')

      promises = @builder.sources.map (source) -> source.getContents()

      Promise.all(promises).then (buffers) =>
        # see if any are false (not found)
        if buffers.indexOf(false) isnt -1
          missingSources = @builder.sources.filter (source, i) =>
            buffers[i] is false
          @missingSources = _.pluck missingSources, 'path' # indicates this job failed
          resolve false # yes resolve with 'not found' for the whole lot, because one source couldn't be found
          return

        if buffers.length == 1
          @log 'only one source; buffer length is ' + buffers[0].length
          resolve buffers[0]
        else
          if @builder.ext is 'js' && @builder.engine.semicolons != false
            withSemicolons = []
            buffers.forEach (buffer) ->
              withSemicolons.push buffer
              withSemicolons.push semicolonBuffer
            withSemicolons.pop()
            buffers = withSemicolons
          resolve Buffer.concat(buffers)

  @_getJoinedContents
