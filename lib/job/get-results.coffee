###
  job.getResults()

  MIGHT BE DEPRECATED
###


module.exports = ->
  @log 'getResults called'

  console.assert @_actioned.isFulfilled()

  # get a copy of the results array to return
  results = []
  if @results
    results[i] = result for result, i in @results

  # include results from any children
  joinedContents = @_getJoinedContents.value()
  if @engine.crawl && joinedContents isnt false

    children = @_getChildren.value()

    if children?
      for child in children
        getResults = child.job.getResults()

        if getResults?
          results.push(result) for result in getResults

  results
