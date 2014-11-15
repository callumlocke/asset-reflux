# a job belongs to one builder, and orchestrates a single act of executing that builder.
# it lingers afterwards and can be reused by other builders that might need to know its contents.
# when a next job runs, the first one becomes previousJob, and then eventually it gets dereferenced completely.

_ = require 'lodash'
chalk = require 'chalk'

semicolonBuffer = new Buffer ';' # for concat'ing scripts

module.exports = class Job

  constructor: (options) ->
    @builder = options.builder
    @workloadId = options.workloadId

    @id = @builder.id + '_job' + _.uniqueId()

    @engine = @builder.engine
    @destination = @engine.destination

    @changedSourcePaths = options.changedSourcePaths

    if @engine.debug
      @log = =>
        @engine.log.apply @engine, [
          chalk.yellow(@id),
          [].slice.call(arguments).map((arg) -> chalk.gray(arg)).join(' ')
        ]
    else @log = (->)

    # start immediately - a job can't exist without being either started or done, there is no 'waiting' state
    @actioned()

  # methods
  getJoinedContents: require './get-joined-contents'
  getChildren: require './get-children'
  finalised: require './finalised'
  actioned: require './actioned'
  getResults: require './get-results'
