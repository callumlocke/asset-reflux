###
  workload._outputFile(outfile, fromBuilder)

  sorts out:
    workload.filesOutput (so this workload has a record of having output this file)
    engine._outfileBuilders (so the engine knows which builder(s) cause the output of this file)

  ...then it actually emits the file.
###

bufferEqual = require 'buffer-equal'
_ = require 'lodash'
Builder = require '../builder'

module.exports = (outfile, fromBuilder) ->
  if !(fromBuilder instanceof Builder) && fromBuilder != false
    throw new TypeError 'expected builder (or explicit false)'
  if !outfile?.isXFile
    console.error outfile
    throw new TypeError 'expected xfile'

  @log "workload._outputFile called with fromBuilder: #{fromBuilder.id}", outfile.inspect()

  # if it's a deletion, deregister the fromBuilder as a 'reason' for this outfile
  if outfile.contents is false
    # deletion: remove this builder from the builders array for this outfile
    if fromBuilder && @engine._outfileBuilders[outfile.path]?
      @log "deregistering builder #{fromBuilder.id} as reason for outfile", outfile.inspect()
      @engine._outfileBuilders[outfile.path] = _.without(
        @engine._outfileBuilders[outfile.path],
        fromBuilder
      )
    else
      @log "NOT deregistering builder #{fromBuilder?.id} as reason (did not exist anyway)", outfile.inspect()

  # ...or if a buffer, register it as a reason
  else if Buffer.isBuffer outfile.contents
    # add this builder to the builders array for this outfile
    if not @engine._outfileBuilders[outfile.path]?
      @engine._outfileBuilders[outfile.path] = []

    if fromBuilder && @engine._outfileBuilders[outfile.path].indexOf fromBuilder is -1
      @log "registering builder #{fromBuilder.id} as reason for outfile", outfile.inspect()
      @engine._outfileBuilders[outfile.path].push fromBuilder
    else
      @log "NOT registering builder #{fromBuilder?.id} as reason for outfile (already exists)", outfile.inspect()


  else throw new TypeError 'Expected contents to be buffer or false'

  # don't output this again if already output
  for alreadyFile in @filesOutput
    if alreadyFile.path == outfile.path
      if alreadyFile.contents != outfile.contents && !bufferEqual(alreadyFile.contents, outfile.contents)
        console.error alreadyFile
        console.error outfile
        throw new Error 'outfile was output twice in one workload with different contents'

      @log 'outfile was output again in same workload', outfile.inspect()
      return

  # record that it got output
  @filesOutput.push outfile

  # ...and emit it
  @emit 'output', outfile

  return
