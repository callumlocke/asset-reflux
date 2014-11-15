# this is the virtual destination for files to be saved to after they've been built/processed.
# SEMI DEPRECATED.

path = require 'path'
async = require 'async'
mkdirp = require 'mkdirp'
bufferEqual = require 'buffer-equal'
File = require 'x-file'

getFolders = (filePath) ->
  folder = filePath # this one won't be used
  folders = []
  while folder.indexOf(path.sep) != -1
    folder = path.dirname folder
    folders.unshift folder
  folders


module.exports = class Destination
  constructor: (@engine) ->
    @files = {} # hash of filenames and file objects
    @folders = [] # simple list of all current folder names (for what?)

  # takes file path and a buffer (or false for deletion).
  # writes it using the engine's hook.

  write: (file, workloadId, done) ->
    details = if file.contents then file.contents.length + ' bytes' else 'FALSE'
    @engine.log "destination.write(#{file.path} (#{details}), #{workloadId}, done)"

    filePath = file.path
    contents = file.contents

    oldFile = @files[filePath] || null

    result =
      filePath: filePath
      # oldSize: (if oldContents? then oldContents.length else null)
      newContents: file.contents
      oldContents: oldFile?.contents
      workloadId: workloadId

    if file.contents == false
      # this is a deletion.
      delete @files[filePath]
    
    @engine.writeHook file, null, (err) ->
      if err? then return done err
      done null, result
      return

    return
