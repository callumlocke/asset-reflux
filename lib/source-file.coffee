# a sourceFile is a reusable interface for reading a specific file from disk, with caching.

fs = require 'graceful-fs'
Promise = require 'bluebird'
path = require 'path'

module.exports = class SourceFile

  constructor: (options) ->
    @path = options.path
    @manager = options.manager

    @getContents()

  getContents: ->
    if not @_getContents?
      @_getContents = new Promise (resolve, reject) =>
        file = do =>
          fileParts = @path.split(path.sep)

          for own starter, resolveTo of @manager.loadPaths
            starterSplit = starter.split(path.sep)

            failed = false
            for part, i in starterSplit
              if fileParts[i] == part then continue
              failed = true
              break

            if !failed
              return path.resolve(process.cwd(), resolveTo, @path)

          return path.resolve(@manager.src, @path)

        fs.readFile file, (err, contents) =>
          if err?
            if err.code isnt 'ENOENT'
              reject err
            else resolve false # not an error - file not existing is just info.
          else resolve contents
          return

    @_getContents
