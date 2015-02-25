###
  job.getJoinedContents()

  returns a promise that resolves with the infile contents, which might be from a single file or joined together from multiple files.

  the contents will be either a buffer or `false`. the latter means one or more of the sources couldn't be loaded.
###

Promise = require 'bluebird'
_ = require 'lodash'

semicolonBuffer = new Buffer ';' # for concatenating js files safely

module.exports = ->
  if !@_getJoinedContents?
    @_getJoinedContents = new Promise (resolve, reject) =>
      @log 'getting joined contents for sources', _.pluck(@builder.sources, 'path')

      promises = @builder.files.map (filePath) =>
        new Promise (resolve, reject) =>
          @engine.readFile filePath, (err, contents) =>
            # if it's a standard node 'file does not exist' error, correct this to 'false'
            if err?.code is 'ENOENT'
              err = null
              contents = false

            if err? then reject err
            else resolve contents

      Promise.all(promises).then (buffers) =>
        # see if any are false (not found)
        if buffers.indexOf(false) isnt -1
          @missingSources = @builder.files.filter (filePath, i) =>
            buffers[i] is false
          # (missingSources indicates this job failed)

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

      , reject
  @_getJoinedContents
