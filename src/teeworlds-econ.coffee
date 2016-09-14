{ Socket } = require 'net'
{ EventEmitter } = require 'events'
{ split, splitText, parseWeapon, formatClient, escape, debug } = require './utils'

# Teeworlds external console wrapper class
class TeeworldsEcon extends EventEmitter

  # Constructor
  #
  # @param {String} host
  # @param {Integer} port
  # @param {String} pasword
  constructor: (args...) ->
    super

    if typeof args[0] == 'object'
      { host, port, password } = args[0]
    else
      [ host, port, password ] = args
    throw new Error('Undefined host') unless host
    throw new Error('Undefined port') unless port
    throw new Error('Undefined password') unless password
    @server = { host, port, password }

    @connection = null
    @connected = false

    @retryDelay = null
    @retryCount = null
    @retryTimer = null

    @clientsInfo = {}

    @resetHandlers()
    @addHandler @handleEnterMessage
    @addHandler @handleLeaveMessage
    @addHandler @handlePickupMessage
    @addHandler @handleChatMessage
    @addHandler @handleKillMessage
    @addHandler @handleFlagGrabMessage
    @addHandler @handleFlagReturnMessage
    @addHandler @handleCaptureMessage

  # Execute any command on server
  #
  # @param {String} command
  # @event error
  exec: (command) ->
    unless @isConnected()
      err = new Error 'Not connected'
      debug.connection '%s:%s econ error: %s', @server.host, @server.port, err.message
      @emit 'error', err
      return

    @write command

  # Say something to chat
  #
  # @param {String} message
  # @param {Integer} limit max line length
  say: (message, limit = 256) ->
    # maximum line length = 256
    limit = 256 if limit > 256
    # split long message to chunks
    chunks = message
      .split '\n'
      .map escape
      .map (line) ->
        splitText line, limit
      .reduce (a, b) ->
        a.concat b

    # execute say command
    @exec "say \"#{chunk}\"" for chunk in chunks

  # Set server message of the day
  #
  # @param {String} message
  motd: (message) ->
    @exec "sv_motd \"#{escape message}\""

  # Write to econ socket
  #
  # @param {String} message
  write: (message) ->
    return unless @connection and @connection.writable
    debug.connection 'writing to %s:%s econ: %s', @server.host, @server.port, message
    @connection.write message + '\n'

  # Add messages handler
  #
  # @param {Function} handler
  addHandler: (handler) ->
    @handlers.push handler

  # Remove messages handler
  #
  # @param {Function} handler
  removeHandler: (handler) ->
    index = @handlers.find (item) -> handler == item
    @handlers.splice index, 1 unless index == -1

  # Remove all messages handlers
  resetHandlers: () ->
    @handlers = []

  # Method for parsing incoming econ messages
  #
  # @private
  # @param {String} message
  # @event online
  # @event reconnected
  # @event error
  # @event end
  handleMessage: (message) =>
    debug.connection 'reading from %s:%s econ: %s', @server.host, @server.port, message

    # client connection
    do (message) =>
      if matches = /^\[server\]: player has entered the game. ClientID=([0-9]+) addr=(.+?):([0-9]+)$/.exec message
        cid = parseInt(matches[1])
        info = {
          ip: matches[2]
          port: matches[3]
        }
        debug.connection 'new client (%s) with ip:port %s:%s on %s:%s ', cid, info.ip, info.port, @server.host, @server.port
        @assignClientInfo cid, info

    # authentication request
    if message == 'Enter password:'
      debug.connection '%s:%s password request', @server.host, @server.port
      @write @server.password
      return

    # connected
    if message == 'Authentication successful. External console access granted.'
      unless @connected
        @connected = true
        debug.connection '%s:%s connected', @server.host, @server.port
        @emit 'online'
      else
        debug.connection '%s:%s reconnected', @server.host, @server.port
        @emit 'reconnected'
      return

    # wrong password
    if /^Wrong password [0-9\/]+.$/.exec message
      err = new Error "#{message} Disconnecting"
      debug.connection '%s:%s econ error: %s', @server.host, @server.port, err.message
      @emit 'error', err
      @disconnect()
      @emit 'end'
      return

    # authentication timeout
    if message == 'authentication timeout'
      err = new Error 'Authentication timeout. Disconnecting'
      debug.connection '%s:%s econ error: %s', @server.host, @server.port, err.message
      @emit 'error', err
      @disconnect()
      @emit 'end'
      return

    # execute all event handlers sequentaly
    for handler in @handlers
      result = handler.call @, @, message
      break if result == false

  # Enter messages handler
  #
  # @param {TeeworldsEcon} econ
  # @param {String} message
  # @event enter { player, team, client }
  handleEnterMessage: (econ, message) ->
    if matches = /^\[game\]: team_join player='([0-9]+):(.+?)' team=([0-9]+)$/.exec message
      debug.events '%s:%s econ %s event', econ.server.host, econ.server.port, 'enter'
      econ.emit 'enter', {
        player: matches[2]
        team: parseInt(matches[3])
        client: formatClient(econ.getClientInfo(parseInt(matches[1])))
      }

  # Leave messages handler
  #
  # @param {TeeworldsEcon} econ
  # @param {String} message
  # @event leave { player }
  handleLeaveMessage: (econ, message) ->
    if matches = /^\[game\]: leave player='([0-9]+):(.+?)'$/.exec message
      debug.events '%s:%s econ %s event', econ.server.host, econ.server.port, 'leave'
      econ.emit 'leave', {
        player: matches[2]
        client: formatClient(econ.getClientInfo(parseInt(matches[1])))
      }

  # Pickup messages handler
  #
  # @param {TeeworldsEcon} econ
  # @param {String} message
  # @event enter { player, weapon }
  handlePickupMessage: (econ, message) ->
    if matches = /^\[game\]: pickup player='[0-9-]+:([^']+)' item=(2|3)+\/([0-9\/]+)$/.exec message
      debug.events '%s:%s econ %s event', econ.server.host, econ.server.port, 'pickup'
      econ.emit 'pickup', {
        player: matches[1]
        weapon: parseWeapon(parseInt(matches[3]))
      }

  # Chat messages handler
  #
  # @param {TeeworldsEcon} econ
  # @param {String} message
  # @event chat { type, player, message }
  handleChatMessage: (econ, message) ->
    # player chat message
    if matches = /^\[(teamchat|chat)\]: [0-9]+:[0-9-]+:([^:]+): (.*)$/.exec message
      debug.events '%s:%s econ %s event', econ.server.host, econ.server.port, 'chat'
      econ.emit 'chat', {
        type: matches[1]
        player: matches[2]
        message: matches[3]
      }

    # server chat message
    if matches = /^\[chat\]: \*\*\* (.*)$/.exec message
      debug.events '%s:%s econ %s event', econ.server.host, econ.server.port, 'chat'
      econ.emit 'chat', {
        type: 'server'
        player: null
        message: matches[1]
      }

  # Kill messages handler
  #
  # @param {TeeworldsEcon} econ
  # @param {String} message
  # @event kill { killer, victim, weapon }
  handleKillMessage: (econ, message) ->
    if matches = /^\[game\]: kill killer='[0-9-]+:([^']+)' victim='[0-9-]+:([^']+)' weapon=([-0-9]+) special=[0-9]+$/.exec message
      return if matches[3] == '-3'
      debug.events '%s:%s econ %s event', econ.server.host, econ.server.port, 'kill'
      econ.emit 'kill', {
        killer: matches[1]
        victim: matches[2]
        weapon: parseWeapon(parseInt(matches[3]))
      }

  # Flag grab messages handler
  #
  # @param {TeeworldsEcon} econ
  # @param {String} message
  # @event enter { player }
  handleFlagGrabMessage: (econ, message) ->
    if matches = /^\[game\]: flag_grab player='[0-9-]+:([^']+)'$/.exec message
      debug.events '%s:%s econ %s event', econ.server.host, econ.server.port, 'flaggrab'
      econ.emit 'flaggrab', {
        player: matches[1]
      }

  # Flag return messages handler
  #
  # @param {TeeworldsEcon} econ
  # @param {String} message
  handleFlagReturnMessage: (econ, message) ->
    if /^\[game\]: flag_return$/.exec message
      debug.events '%s:%s econ %s event', econ.server.host, econ.server.port, 'flagreturn'
      econ.emit 'flagreturn', {}

  # Flag capture messages handler
  #
  # @param {TeeworldsEcon} econ
  # @param {String} message
  # @event enter { flag, player, time }
  handleCaptureMessage: (econ, message) ->
    if matches = /^\[chat\]: \*\*\* The ([^ ]+) flag was captured by '([^']+)' \(([0-9.]+) seconds\)$/.exec message
      debug.events '%s:%s econ %s event', econ.server.host, econ.server.port, 'capture'
      econ.emit 'capture', {
        flag: matches[1]
        player: matches[2]
        time: parseFloat(matches[3]) * 1000
      }

  # Assign info for client with specified ID
  #
  # @private
  # @param {Integer} cid
  # @param {Object} info
  # @return {Object} client info
  assignClientInfo: (cid, info) ->
    @clientsInfo[cid] = {} unless @clientsInfo[cid]
    Object.assign @clientsInfo[cid], info
    return @clientsInfo[cid]

  # Return awailable info for client with specified ID
  #
  # @private
  # @param {Integer} cid
  # @return {Object}
  getClientInfo: (cid) ->
    return @clientsInfo[cid] ? {}

  # Connect to server econ
  #
  # @example Set connection params
  #   econ.connect({ retryDelay: 30000, retryCount: -1 })
  #
  # @param {Object} connectionParams
  # @event error
  connect: (connectionParams = {}) ->
    return if @connection

    @retryDelay = if connectionParams.retryDelay then connectionParams.retryDelay else 30000
    @retryCount = if connectionParams.retryCount then connectionParams.retryCount else -1

    @connection = new Socket()

    @connection
      .pipe split(/\r?\n\u0000*/)
      .on 'data', @handleMessage

    @connection.on 'error', (err) =>
      debug.connection '%s:%s connection error: %s', @server.host, @server.port, err.message
      @emit 'error', err
    @connection.on 'close', @reconnect
    @connection.on 'end', @reconnect

    @connection.setKeepAlive true

    debug.connection 'connecting to %s:%s', @server.host, @server.port

    @connection.connect @server.port, @server.host

  # Reconnect on connection lost
  #
  # @private
  # @event end
  # @event reconnect
  reconnect: () =>
    return if @retryTimer

    debug.connection 'reconnecting to %s:%s', @server.host, @server.port

    if @retryCount == 0
      @disconnect()
      @emit 'end'
      return
    @retryCount-- if @retryCount > 0

    @emit 'reconnect'
    @retryTimer = setTimeout () =>
      @retryTimer = null
      @disconnect()
      @connect({ @retryDelay, @retryCount })
    , @retryDelay

  # Disconnect from server
  disconnect: () =>
    return if !@connection

    debug.connection 'disconnecting from %s:%s', @server.host, @server.port

    @connection.removeAllListeners 'data'
    @connection.removeAllListeners 'end'
    @connection.removeAllListeners 'error'
    @connection.destroy()
    @connection.unref()
    @connection = null

  # Check connection status
  #
  # @return {Boolean} is connected/disconnected
  isConnected: () ->
    return @connection and @connection.writable and @connected

module.exports = TeeworldsEcon
