###
  assetReflux()
  returns a configured Engine instance
###

Engine = require './engine'

# export stuff
module.exports = (options) -> new Engine options;
module.exports.Engine = Engine

# also export various utility deps, in case a wrapper lib wants them
module.exports.async    = require 'async'
module.exports.Promise  = require 'bluebird'
module.exports.chalk    = require 'chalk'
module.exports._        = require 'lodash'
module.exports.Args     = require 'args-js'
module.exports.File     = require 'x-file'
