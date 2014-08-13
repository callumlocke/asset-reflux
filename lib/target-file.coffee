# little API for writing a single file to the dest directory

path = require 'path'
_ = require 'lodash'
bufferEqual = require 'buffer-equal'
Promise = require 'bluebird'
fs = require 'graceful-fs'
mkdirp = require 'mkdirp'
# unlink = Promise.promisify fs.unlink

module.exports = class TargetFile
  constructor: (dest, options) ->
    @path = options.path
    @dest = dest
    @buffer = options.buffer
    @id = @path + ' (target: ' + _.uniqueId() + ')' # for logging

  write: ->
    return new Promise (resolve, reject) =>
      fullTargetPath = path.resolve @dest, @path

      mkdirp path.dirname(fullTargetPath), (err) =>
        throw err if err?

        fs.writeFile fullTargetPath, @buffer, (err) ->
          if err? then reject err
          else resolve true
        return

      return

  delete: (done) ->
    fullTargetPath = path.resolve @dest, @path
    fs.unlink fullTargetPath, done
