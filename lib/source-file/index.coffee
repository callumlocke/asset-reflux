# TODO: remove this class. let builders use the read hook directly. do this
# kind of disk read caching before AR.

Promise = require 'bluebird'
path = require 'path'

module.exports = class SourceFile

  constructor: (options) ->
    @path = options.path
    @engine = options.engine

    @getContents()

  getContents: ->
    if not @_getContents?
      @_getContents = new Promise (resolve, reject) =>
        @engine.readHook @path, (err, contents) ->
          if err? then return reject(err)
          resolve(contents)

    @_getContents
