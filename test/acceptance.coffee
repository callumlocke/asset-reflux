test = require 'tape'
assetReflux = require '..'
_ = require 'lodash'
path = require 'path'
File = require 'x-file'
assert = require 'assert' # for things we don't want to log every time
readRecursive = require 'fs-readdir-recursive'
mkdirp = require 'mkdirp'
rimraf = require 'rimraf'
fs = require 'fs'
sinon = require 'sinon'
async = require 'async'
chalk = require 'chalk'

sourceFiles = null
sourcePaths = null
resetSourceFiles = ->
  sourceFiles =
    'index.html':
      '''
      <p>hi</p>
      <link rel="stylesheet" href="styles/s1.css">
      '''
    'styles/s1.css':
      '''
      body {
        background: blue;
      }
      '''
    'styles/s2.css':
      '''
      p { color: red }
      '''
  sourcePaths = Object.keys sourceFiles
  return


getEmittedFiles = (spy) ->
  _.sortBy(
    _.pluck(_.pluck(spy.getCalls(), 'args'), '0'),
    'path'
  )
readFile = (sourcePath, done) ->
  if sourceFiles[sourcePath]?
    contents = new Buffer(sourceFiles[sourcePath])
  else contents = false
  done null, contents
processHook = (file, triggers, done) ->
  assert file instanceof File
  if triggers?
    assert _.isArray(triggers)
    assert _.isString(trigger) for trigger in triggers

  switch file.ext
    when '.html'
      file.text += '\n<!-- processed! -->'
    when '.js', '.css'
      file.text += '\n/* processed! */'
    else oops()

  done null, file



console.log 'Initial source files: ', sourcePaths

test 'asset-reflux', (t) ->
  async.series [
    #=======================================================
    (done) ->
      console.log chalk.magenta '==================\n TEST 1: BASIC'

      resetSourceFiles()
      outputSpy = sinon.spy()

      engine = assetReflux
        # debug: true
        concat: false
        rev: false
        readFile: readFile
        processHook: processHook

      workload1 = engine.createWorkload sourcePaths, []
      workload1.on 'output', outputSpy
      workload1.run (err) ->
        t.error err, 'workload 1 completed without error'
        t.equal outputSpy.callCount, 3, '3 output events fired'

        # now do another workload...
        sourceFiles['index.html'] += '\n<link rel="stylesheet" href="styles/nonexist.css">'
        delete sourceFiles['styles/s2.css']

        outputSpy.reset()

        changedFiles = [
          'styles/s2.css'
          'index.html'
        ]

        workload2 = engine.createWorkload changedFiles, changedFiles
        workload2.on 'output', outputSpy
        workload2.run (err) ->
          t.error err, 'workload 2 completed without error'
          t.equal outputSpy.callCount, 2, 'output event fired twice'

          emittedFiles = getEmittedFiles outputSpy

          # verify the edited index.html file
          t.equal emittedFiles[0].path, 'index.html', 'extra path correct'
          t.equal emittedFiles[0].text, (
            '''
            <p>hi</p>
            <link rel="stylesheet" href="styles/s1.css">
            <link rel="stylesheet" href="styles/nonexist.css">
            <!-- processed! -->
            '''
          )

          # verify the deleted second file
          t.equal emittedFiles[1].path, 'styles/s2.css', 'deleted path is correct'
          t.equal emittedFiles[1].contents, false, 'deleted contents is `false`'
          t.equal emittedFiles[1].text, false, 'deleted contents is `false`'

          # TODO: verify that there was a 'missing' event for styles/nonexist.css

          done()

    (done) ->
      console.log chalk.magenta '==================\n TEST 2: BUNDLING'

      resetSourceFiles()

      engine = assetReflux
        # debug: true
        concat: true
        verboseConcat: true # for easier debugging tests
        # rev: true
        crawl: true
        readFile: readFile
        processHook: processHook

      outputSpy = sinon.spy()

      workload1 = engine.createWorkload ['index.html'], []
      workload1.on 'output', outputSpy
      workload1.run (err) ->
        t.error err, 'workload 1 completed without error'
        t.equal outputSpy.callCount, 2, '2 output events fired'

        emittedFiles = getEmittedFiles outputSpy

        t.equal emittedFiles[0].path, 'index.html', 'html path correct'
        t.equal emittedFiles[0].text, (
          '''
          <p>hi</p>
          <link rel="stylesheet" href="styles/s1.css">
          <!-- processed! -->
          '''
        )

        t.equal emittedFiles[1].path, 'styles/s1.css', 'css path correct'
        t.equal emittedFiles[1].text, (
          '''
          body {
            background: blue;
          }
          /* processed! */
          '''
        )

        # add a 2nd and 3rd stylesheet reference to the html file
        sourceFiles['styles/s3.css'] = 'strong {display: none}'
        sourceFiles['index.html'] += (
          '\n<link rel="stylesheet" href="styles/s2.css">' +
          '\n<link rel=stylesheet href=styles/s3.css>'
        )

        # do another workload to see how the engine handles the changes
        outputSpy.reset()
        workload2 = engine.createWorkload ['index.html'], ['index.html']
        workload2.on 'output', outputSpy
        workload2.run (err) ->
          t.error err, 'workload 2 completed without error'
          t.equal outputSpy.callCount, 3, '3 output events f'

          emittedFiles = getEmittedFiles outputSpy
          # console.log emittedFiles

          # verify the new, concatenated CSS file
          t.equal emittedFiles[0].path, 'concat-styles__s1___styles__s2___styles__s3.css', 'concat path correct'
          t.equal emittedFiles[0].text, (
            '''
            body {
              background: blue;
            }p { color: red }strong {display: none}
            /* processed! */
            '''
          )

          # verify the edited index.html file
          t.equal emittedFiles[1].path, 'index.html', 'extra path correct'
          t.equal emittedFiles[1].text, (
            '''
            <p>hi</p>
            <link rel="stylesheet" href="concat-styles__s1___styles__s2___styles__s3.css">
            <!-- processed! -->
            '''
          ), 'html got rewritten correctly'


          # verify the orphaned 's1.css' got deleted
          t.equal emittedFiles[2].path, 'styles/s1.css', 'output event for orphaned outfile'
          t.equal emittedFiles[2].text, false, 'orphaned outfile got deleted'


          # remove the middle stylesheet link
          sourceFiles['index.html'] = sourceFiles['index.html'].split('\n').filter((line) ->
            line isnt '<link rel="stylesheet" href="styles/s2.css">'
          ).join('\n')

          # run a third workload to see what happens
          outputSpy.reset()
          workload3 = engine.createWorkload ['index.html'], ['index.html']
          workload3.on 'output', outputSpy
          workload3.run (err) ->
            t.error err, 'workload 3 completed without error'
            t.equal outputSpy.callCount, 3, '3 output events'

            emittedFiles = getEmittedFiles outputSpy
            # console.log emittedFiles

            # verify the old one got deleted
            t.equal emittedFiles[0].path, 'concat-styles__s1___styles__s2___styles__s3.css', 'orphaned concat path correct'
            t.equal emittedFiles[0].contents, false, 'orphaned concat path deleted'

            # verify the new concat path got created
            t.equal emittedFiles[1].path, 'concat-styles__s1___styles__s3.css', 'new concat path correct'
            t.equal emittedFiles[1].text, (
              '''
              body {
                background: blue;
              }strong {display: none}
              /* processed! */
              '''
            ), 'new concat file got created'

            # verify the index.html looks right
            t.equal emittedFiles[2].path, 'index.html', 'html file path correct'
            t.equal emittedFiles[2].text, (
              '''
              <p>hi</p>
              <link rel="stylesheet" href="concat-styles__s1___styles__s3.css">
              <!-- processed! -->
              '''
            ), 'html file rewritten correctly'

            done()

  ], (err) ->
    t.error err, 'no uncaught errors'  
    t.end()
