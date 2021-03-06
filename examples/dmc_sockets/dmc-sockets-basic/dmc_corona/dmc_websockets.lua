--====================================================================--
-- dmc_websockets.lua
--
--
-- by David McCuskey
-- Documentation: http://docs.davidmccuskey.com/display/docs/dmc_websockets.lua
--====================================================================--

--[[

Copyright (C) 2014 David McCuskey. All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in the
Software without restriction, including without limitation the rights to use, copy,
modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
and to permit persons to whom the Software is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included in all copies
or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

--]]



--====================================================================--
-- DMC Corona Library : DMC Websockets
--====================================================================--

--[[

WebSocket support adapted from:
* Lumen (http://github.com/xopxe/Lumen)
* lua-websocket (http://lipp.github.io/lua-websockets/)
* lua-resty-websocket (https://github.com/openresty/lua-resty-websocket)

--]]


-- Semantic Versioning Specification: http://semver.org/

local VERSION = "1.0.0"



--====================================================================--
-- DMC Corona Library Config
--====================================================================--


--====================================================================--
-- Support Functions

local Utils = {} -- make copying from dmc_utils easier

function Utils.extend( fromTable, toTable )

	function _extend( fT, tT )

		for k,v in pairs( fT ) do

			if type( fT[ k ] ) == "table" and
				type( tT[ k ] ) == "table" then

				tT[ k ] = _extend( fT[ k ], tT[ k ] )

			elseif type( fT[ k ] ) == "table" then
				tT[ k ] = _extend( fT[ k ], {} )

			else
				tT[ k ] = v
			end
		end

		return tT
	end

	return _extend( fromTable, toTable )
end


--====================================================================--
-- Configuration

local dmc_lib_data, dmc_lib_info

-- boot dmc_library with boot script or
-- setup basic defaults if it doesn't exist
--
if false == pcall( function() require( "dmc_corona_boot" ) end ) then
	_G.__dmc_corona = {
		dmc_corona={},
	}
end

dmc_lib_data = _G.__dmc_corona
dmc_lib_info = dmc_lib_data.dmc_library



--====================================================================--
-- DMC WebSockets
--====================================================================--


--====================================================================--
-- Configuration

dmc_lib_data.dmc_websockets = dmc_lib_data.dmc_websockets or {}

local DMC_WEBSOCKETS_DEFAULTS = {
	debug_active=false,
}

local dmc_websockets_data = Utils.extend( dmc_lib_data.dmc_websockets, DMC_WEBSOCKETS_DEFAULTS )


--====================================================================--
-- Imports

local mime = require 'mime'
local urllib = require 'socket.url'

local ByteArray = require 'dmc_websockets.bytearray'
local ByteArrayErrorFactory = require 'lua_bytearray.exceptions'
local Objects = require 'lua_objects'
local Patch = require( 'lua_patch' )()
local Sockets = require 'dmc_sockets'
local StatesMix = require 'lua_states'
local Utils = require 'lua_utils'

-- websockets helpers
local ws_error = require 'dmc_websockets.exception'
local ws_frame = require 'dmc_websockets.frame'
local ws_handshake = require 'dmc_websockets.handshake'


--====================================================================--
-- Setup, Constants

-- setup some aliases to make code cleaner
local inheritsFrom = Objects.inheritsFrom
local ObjectBase = Objects.ObjectBase

local tinsert = table.insert
local tconcat = table.concat

local LOCAL_DEBUG = false

local ProtocolError = ws_error.ProtocolError
local BufferError = ByteArrayErrorFactory.BufferError



--====================================================================--
-- WebSocket Class
--====================================================================--


local WebSocket = inheritsFrom( ObjectBase )
WebSocket.NAME = "WebSocket"

StatesMix.mixin( WebSocket )

-- version for the the group of WebSocket files
WebSocket.VERSION = '1.0.0'
WebSocket.USER_AGENT = 'dmc_websockets/'..WebSocket.VERSION

--== Message Type Constants

WebSocket.TEXT = 'text'
WebSocket.BINARY = 'binary'

--== Throttle Constants

WebSocket.OFF = Sockets.OFF
WebSocket.LOW = Sockets.LOW
WebSocket.MEDIUM = Sockets.MEDIUM
WebSocket.HIGH = Sockets.HIGH

--== Connection-Status Constants

WebSocket.NOT_ESTABLISHED = 0
WebSocket.ESTABLISHED = 1
WebSocket.CLOSING_HANDSHAKE = 2
WebSocket.CLOSED = 3

--== Protocol Close Constants

local CLOSE_CODES = {
	INTERNAL = { code=9999, reason="Internal Error" },
}

--== State Constants

WebSocket.STATE_CREATE = "state_create"
WebSocket.STATE_INIT = "state_init"
WebSocket.STATE_NOT_CONNECTED = "state_not_connected"
WebSocket.STATE_HTTP_NEGOTIATION = "state_http_negotiation"
WebSocket.STATE_CONNECTED = "state_connected"
WebSocket.STATE_CLOSING = "state_closing_connection"
WebSocket.STATE_CLOSED = "state_closed"

--== Event Constants

WebSocket.EVENT = 'websocket_event'

WebSocket.ONOPEN = 'onopen'
WebSocket.ONMESSAGE = 'onmessage'
WebSocket.ONERROR = 'onerror'
WebSocket.ONCLOSE = 'onclose'


--====================================================================--
--== Start: Setup DMC Objects

function WebSocket:_init( params )
	-- print( "WebSocket:_init" )
	params = params or {}
	self:superCall( "_init", params )
	--==--

	--== Sanity Check ==--

	if not self.is_intermediate then
		assert( params.uri, "WebSocket: requires parameter 'uri'" )
	end

	--== Create Properties ==--

	self._uri = params.uri
	self._port = params.port
	self._query = params.query
	self._protocols = params.protocols

	self._auto_connect = params.auto_connect == nil and true or params.auto_connect
	self._auto_reconnect = params.auto_reconnect or false

	self._msg_queue = {}
	-- used to build data from frames, table
	self._current_frame = nil

	-- self._max_payload_len = params.max_payload_len
	-- self._send_unmasked = params.send_unmasked or false
	-- self._rd_frame_co = nil -- ref to read-frame coroutine

	self._socket_handler = nil -- ref to
	self._socket_throttle = params.throttle

	self._close_timer = nil

	--== Object References ==--

	self._ba = nil -- our Byte Array, buffer
	self._socket = nil


	-- set first state
	self:setState( WebSocket.STATE_CREATE )

end


function WebSocket:_initComplete()
	-- print( "WebSocket:_initComplete" )
	self:superCall( "_initComplete" )
	--==--
	self:_createNewFrame()

	if self._auto_connect == true then
		self:connect()
	end
end

--== END: Setup DMC Objects
--====================================================================--


--====================================================================--
--== Public Methods

function WebSocket:connect()
	-- print( 'WebSocket:connect' )
	self:gotoState( WebSocket.STATE_INIT )
end


function WebSocket.__setters:throttle( value )
	-- print( 'WebSocket.__setters:throttle', value )
	Sockets.throttle = value
end


function WebSocket.__getters:readyState()
	return self._ready_state
end


function WebSocket:send( data, params )
	-- print( "WebSocket:send", #data )
	params = params or {}
	--==--

	local mtype = params.type or WebSocket.TEXT

	if mtype == WebSocket.BINARY then
		self:_sendBinary( data )
	else
		self:_sendText( data )
	end

end


function WebSocket:close()
	-- print( "WebSocket:close" )
	local evt = Utils.extend( ws_frame.close.OK, {} )
	self:_close( evt )
end


--====================================================================--
--== Private Methods

function WebSocket:_onOpen()
	-- print( "WebSocket:_onOpen" )
	self:dispatchEvent( self.ONOPEN )
end

--[[
	msg={
		data='',
		ftype=''
	}
--]]
function WebSocket:_onMessage( msg )
	-- print( "WebSocket:_onMessage", msg )
	self:dispatchEvent( WebSocket.ONMESSAGE, { message=msg }, {merge=true} )
end

function WebSocket:_onClose()
	-- print( "WebSocket:_onClose" )
	self:dispatchEvent( self.ONCLOSE )
end

function WebSocket:_onError( ecode, emsg )
	-- print( "WebSocket:_onError", ecode, emsg )
	self:dispatchEvent( self.ONERROR, {is_error=true, error=ecode, emsg=emsg }, {merge=true} )
end


function WebSocket:_doHttpConnect()
	-- print( "WebSocket:_doHttpConnect" )

	local request = ws_handshake.createRequest{
		host=self._host,
		port=self._port,
		path=self._path,
		protocols=self._protocols
	}

	if request then
		-- TODO: error handling
		local bytes, err, idx = self._socket:send( request )
	else
		self:_close( { reconnect=false } )
	end

end


-- @param str raw returned header from HTTP request
--
function WebSocket:_processHeaderString( str )
	-- print( "WebSocket:_processHeaderString" )
	local results = {}
	for line in string.gmatch( str, '[^\r\n]*\r\n') do
		tinsert( results, line )
	end
	return results
end

function WebSocket:_handleHttpRespose()
	-- print( "WebSocket:_handleHttpRespose" )

	-- see if we have entire header
	local _, e_pos = self._ba:search( '\r\n\r\n' )
	if e_pos == nil then return end

	local ba = self._ba
	local raw, data

	ba.pos = 1
	h_str = ba:readBuf( e_pos )

	if ws_handshake.checkResponse( self:_processHeaderString( h_str ) ) then
		self:gotoState( WebSocket.STATE_CONNECTED )
	else
		self:_close( { reconnect=false } )
	end

end


--== Methods to handle non-/fragmented frames

function WebSocket:_createNewFrame()
	self._current_frame = {
		data = {},
		type = ''
	}
end
function WebSocket:_insertFrameData( data, ftype )
	local frame = self._current_frame

	--== Check for errors in Continuation

	-- there is no type for this frame and none from previous
	if ftype == nil and #frame.data == 0 then
		return nil
	end
	-- we already have a type/data from previous frame
	if ftype ~= nil and #frame.data > 0 then
		return nil
	end

	if ftype then frame.type = ftype end
	tinsert( frame.data, data )

	return data
end
function WebSocket:_processCurrentFrame()
	local frame = self._current_frame
	frame.data = tconcat( frame.data, '' )

	self:_createNewFrame()
	return frame
end


function WebSocket:_receiveFrame()
	-- print( "WebSocket:_receiveFrame" )

	local ws_types = ws_frame.type
	local ws_close = ws_frame.close

	-- check current state
	local state = self:getState()
	if state ~= WebSocket.STATE_CONNECTED and state ~= WebSocket.STATE_CLOSING then
		self:_onError( -1, "WebSocket is not connected" )
	end

	local function handleWSFrame( frame_info )
		-- print("got frame", frame_info.type, frame_info.fin )
		-- print("got data", frame_info.data ) -- when testing, this could be A LOT of data
		local fcode, ftype, fin, data = frame_info.opcode, frame_info.type, frame_info.fin, frame_info.data
		if LOCAL_DEBUG then
			print( "Received msg type:" % ftype )
		end

		if fcode == ws_types.continuation then
			if not self:_insertFrameData( data ) then
				self:_bailout{
					code=ws_close.PROTO_ERR.code,
					reason=ws_close.PROTO_ERR.reason,
				}
				return
			end
			if fin then
				local msg = self:_processCurrentFrame()
				self:_onMessage( msg )
			end

		elseif fcode == ws_types.text or fcode == ws_types.binary then
			if not self:_insertFrameData( data, ftype ) then
				self:_bailout{
					code=ws_close.PROTO_ERR.code,
					reason=ws_close.PROTO_ERR.reason,
				}
				return
			end
			if fin then
				local msg = self:_processCurrentFrame()
				self:_onMessage( msg )
			end

		elseif fcode == ws_types.close then
			local code, reason = ws_frame.decodeCloseFrameData( data )
			local evt = {
				code=code or ws_close.OK.code,
				reason=reason or ws_close.OK.reason,
				from_server=true
			}
			self:_close( evt )

		elseif fcode == ws_types.ping then
			if self:getState() == WebSocket.STATE_CONNECTED then
				self:_sendPong( data )
			end

		elseif fcode == ws_types.pong then
			-- pass

		end
	end

	--== processing loop

	local err = nil
	while not err do
		local position = self._ba.pos -- save in case of errors
		try{
			function()
				handleWSFrame( ws_frame.receiveFrame( self._ba ) )
			end,
			catch{
				function(e)
					err=e
					self._ba.pos = position
				end
			}
		}
	end

	--== handle error

	if not err.isa then
		print( "Unknown Error", err )
		self:_bailout{
			code=CLOSE_CODES.INTERNAL.code,
			reason=CLOSE_CODES.INTERNAL.reason
		}

	elseif err:isa( BufferError ) then
		-- pass, not enough data to read another frame

	elseif err:isa( ws_error.ProtocolError ) then
		print( "Protocol Error:", err.message )
		self:_bailout{
			code=err.code,
			reason=err.reason,
		}

	else
		print( "Unknown Error", err.code, err.reason, err.message )
		self:_bailout{
			code=CLOSE_CODES.INTERNAL.code,
			reason=CLOSE_CODES.INTERNAL.reason
		}
	end

end

-- @param msg table with message info
-- opcode: one of websocket types
-- data: data to send
--
function WebSocket:_sendFrame( msg )
	-- print( "WebSocket:_sendFrame", msg.opcode, msg.data )

	local opcode = msg.opcode or ws_frame.type.text
	local data = msg.data
	local masked = true -- always when client to server
	local sock = self._socket

	local onFrameCallback = function( event )
		if LOCAL_DEBUG then
			print("Received frame to send: size", #event.frame )
		end
		if not event.frame then
			self:_onError( -1, event.emsg )
		else
			-- send frame
			-- TODO: error handling
			local bytes, err, idx = self._socket:send( event.frame )
		end
	end

	local p =
	{
			data=data,
			opcode=opcode,
			masked=masked,
			onFrame=onFrameCallback,
			-- max_frame_size (optional)
		}
	ws_frame.buildFrames( p )

end


function WebSocket:_bailout( params )
	-- print("Failing connection", params.code, params.reason )
	self:_close( params )
end



function WebSocket:_close( params )
	-- print( "WebSocket:_close" )
	params = params or {}
	local default_close = ws_frame.close.GOING_AWAY
	params.code = params.code or default_close.code
	params.reason = params.reason or default_close.reason
	--==--
	params.reconnect = params.reconnect == nil and true or false

	local state = self:getState()

	if state == WebSocket.STATE_CLOSED then
		-- pass

	elseif state == WebSocket.STATE_CLOSING then
		self:gotoState( WebSocket.STATE_CLOSED )

	elseif state == WebSocket.STATE_NOT_CONNECTED or state == WebSocket.STATE_HTTP_NEGOTIATION then
		self:gotoState( WebSocket.STATE_CLOSED )

	else
		self:gotoState( WebSocket.STATE_CLOSING, params )

	end

end


function WebSocket:_sendBinary( data )
	local msg = { opcode=ws_frame.type.binary, data=data }
	self:_sendMessage( msg )
end
function WebSocket:_sendClose( code, reason )
	-- print( "WebSocket:_sendClose", code, reason )
	local data = ws_frame.encodeCloseFrameData( code, reason )
	local msg = { opcode=ws_frame.type.close, data=data }
	self:_sendMessage( msg )
end
function WebSocket:_sendPing( data )
	local msg = { opcode=ws_frame.type.ping, data=data }
	self:_sendMessage( msg )
end
function WebSocket:_sendPong( data )
	local msg = { opcode=ws_frame.type.pong, data=data }
	self:_sendMessage( msg )
end
function WebSocket:_sendText( data )
	local msg = { opcode=ws_frame.type.text, data=data }
	self:_sendMessage( msg )
end


function WebSocket:_sendMessage( msg )
	-- print( "WebSocket:_sendMessage" )
	params = params or {}
	--==--

	local state = self:getState()

	-- build frames
	-- queue frames
	-- send frames

	if false then
		self:_addMessageToQueue( msg )

	elseif state == WebSocket.STATE_CLOSED then
		-- pass

	else
		self:_sendFrame( msg )

	end

end


function WebSocket:_addMessageToQueue( msg )
	-- print( "WebSocket:_addMessageToQueue" )
	table.insert( self._msg_queue, msg )
end

function WebSocket:_processMessageQueue()
	-- print( "WebSocket:_processMessageQueue" )
	for _, msg in ipairs( self._msg_queue ) do
		print( "Processing Messages", _ )
		self:_sendMessage( msg )
	end
	self._msg_queue = {}
end


--====================================================================--
--== START: STATE MACHINE

function WebSocket:state_create( next_state, params )
	-- print( "WebSocket:state_create >>", next_state )
	params = params or {}
	--==--

	if next_state == WebSocket.STATE_INIT then
		self:do_state_init( params )

	else
		print( "WARNING :: WebSocket:state_create " .. tostring( next_state ) )
	end

end


--== Initialize

function WebSocket:do_state_init( params )
	-- print( "WebSocket:do_state_init" )
	params = params or {}
	--==--
	local socket = self._socket

	self._ready_state = self.NOT_ESTABLISHED
	self:setState( WebSocket.STATE_INIT )

	local uri = self._uri
	local url_parts = urllib.parse( uri )
	local host = url_parts.host
	local port = url_parts.port
	local path = url_parts.path
	local query = url_parts.query

	local port = self._port or port

	if not port then
		port = 80
	end

	if not path or path == "" then
		path = "/"
	end
	if query then
		path = path .. '?' .. query
	end

	self._host = host
	self._path = path
	self._port = port

	if socket then socket:close() end

	socket = Sockets:create( Sockets.TCP )
	Sockets.throttle = self._socket_throttle
	self._socket_handler = self:createCallback( self._socketEvent_handler )

	if LOCAL_DEBUG then
		print( "dmc_websockets:: Connecting to '%s:%s'" % { self._host, self._port } )
	end
	socket:addEventListener( socket.EVENT, self._socket_handler )
	self._socket = socket

	socket:connect( host, port )

end

function WebSocket:state_init( next_state, params )
	-- print( "WebSocket:state_init >>", next_state )
	params = params or {}
	--==--

	if next_state == self.CLOSED then
		self:do_state_closed( params )

	elseif next_state == WebSocket.STATE_NOT_CONNECTED then
		self:do_state_not_connected( params )

	else
		print( "WARNING :: WebSocket:state_init " .. tostring( next_state ) )
	end

end


--== Not Connected

function WebSocket:do_state_not_connected( params )
	-- print( "WebSocket:do_state_not_connected" )
	params = params or {}
	--==--

	self._ready_state = self.NOT_ESTABLISHED

	self:setState( WebSocket.STATE_NOT_CONNECTED )

	-- do after state set
	if LOCAL_DEBUG then
		print("dmc_websockets:: Sending WebSocket connect request to server ")
	end
	self:_doHttpConnect()

end

function WebSocket:state_not_connected( next_state, params )
	-- print( "WebSocket:state_not_connected >>", next_state )
	params = params or {}
	--==--

	if next_state == WebSocket.STATE_HTTP_NEGOTIATION then
		self:do_state_http_negotiation( params )

	elseif next_state == WebSocket.STATE_CLOSED then
		self:do_state_closed( params )

	else
		print( "WARNING :: WebSocket:state_not_connected " .. tostring( next_state ) )
	end

end


--== HTTP Negotiation

function WebSocket:do_state_http_negotiation( params )
	-- print( "WebSocket:do_state_http_negotiation" )
	params = params or {}
	--==--

	self:setState( WebSocket.STATE_HTTP_NEGOTIATION )

	-- do this after setting state
	if LOCAL_DEBUG then
		print("dmc_websockets:: Reading WebSocket connect response from server ")
	end
	self:_handleHttpRespose()

end

function WebSocket:state_http_negotiation( next_state, params )
	-- print( "WebSocket:state_http_negotiation >>", next_state )
	params = params or {}
	--==--

	if next_state == WebSocket.STATE_CONNECTED then
		self:do_state_connected( params )

	elseif next_state == WebSocket.STATE_CLOSED then
		self:do_state_closed( params )

	else
		print( "WARNING :: WebSocket:state_http_negotiation %s" % tostring( next_state ) )
	end

end


--== Connected

function WebSocket:do_state_connected( params )
	-- print( "WebSocket:do_state_connected" )
	params = params or {}
	--==--

	self._ready_state = self.ESTABLISHED
	self:setState( WebSocket.STATE_CONNECTED )

	if LOCAL_DEBUG then
		print( "dmc_websockets:: Connected to server" )
	end

	self:_onOpen()

	-- check if more data after reading header
	self:_receiveFrame()

	-- send any waiting messages
	self:_processMessageQueue()

end
function WebSocket:state_connected( next_state, params )
	-- print( "WebSocket:state_connected >>", next_state )
	params = params or {}
	--==--

	if next_state == WebSocket.STATE_CLOSING then
		self:do_state_closing_connection( params )

	elseif next_state == WebSocket.STATE_CLOSED then
		self:do_state_closed( params )

	else
		print( "WARNING :: WebSocket:state_connected %s" % tostring( next_state ) )
	end

end


--== Closing

function WebSocket:do_state_closing_connection( params )
	-- print( "WebSocket:do_state_closing_connection", params )
	params = params or {}
	params.from_server = params.from_server ~= nil and params.from_server or false
	--==--

	self._ready_state = self.CLOSING_HANDSHAKE
	self:setState( WebSocket.STATE_CLOSING )

	if params.code then
		self:_sendClose( params.code, params.reason )
	end

	if params.from_server then
		self:gotoState( WebSocket.STATE_CLOSED )

	else
		-- set timer to politely wait for server close response
		local f = function()
			print( "ERROR: Close response not received" )
			self._close_timer = nil
			self:gotoState( WebSocket.STATE_CLOSED )
		end
		self._close_timer = timer.performWithDelay( 4000, f )
	end

end
function WebSocket:state_closing_connection( next_state, params )
	-- print( "WebSocket:state_closing_connection >>", next_state )
	params = params or {}
	--==--

	if next_state == WebSocket.STATE_CLOSED then
		self:do_state_closed( params )

	else
		print( "WARNING :: WebSocket:state_closing_connection %s" % tostring( next_state ) )
	end

end


--== Closed

function WebSocket:do_state_closed( params )
	-- print( "WebSocket:do_state_closed" )
	params = params or {}
	--==--

	self._ready_state = self.CLOSED
	self:setState( WebSocket.STATE_CLOSED )

	if self._close_timer then
		-- print( "Close response received" )
		timer.cancel( self._close_timer )
		self._close_timer = nil
	end

	self._socket:close()

	if LOCAL_DEBUG then
		print( "dmc_websockets:: Server connection closed" )
	end

	self:_onClose()

end
function WebSocket:state_closed( next_state, params )
	-- print( "WebSocket:state_closed >>", next_state )
	params = params or {}
	--==--

	if next_state == self.CLOSED then
		self:do_state_closed( params )

	else
		if LOCAL_DEBUG then
			print( "WARNING :: WebSocket:state_closed %s" % tostring( next_state ) )
		end
	end

end

--== END: STATE MACHINE
--====================================================================--


--====================================================================--
--== Event Handlers

function WebSocket:_socketEvent_handler( event )
	-- print( "WebSocket:_socketEvent_handler", event.type, event.status )

	local state = self:getState()
	local sock = self._socket

	if event.type == sock.CONNECT then

		if event.status == sock.CONNECTED then
			self:gotoState( WebSocket.STATE_NOT_CONNECTED )
		else
			self:gotoState( WebSocket.STATE_CLOSED )
		end

	elseif event.type == sock.READ then

		local ba = self._ba
		local data = self._socket:receive('*a')

		if ba == nil then
			ba = ByteArray()
		else
			ba = ByteArray()
			ba:readFromArray( self._ba, self._ba.pos )
		end
		self._ba = ba

		ba:writeBuf( data ) -- copy in new data

		-- if LOCAL_DEBUG then
		-- 	print( 'Data', #data, ba:getAvailable(), ba.pos )
		-- 	Utils.hexDump( data )
		-- end

		if state == WebSocket.STATE_NOT_CONNECTED then
			self:gotoState( WebSocket.STATE_HTTP_NEGOTIATION )

		else
			self:_receiveFrame()
			-- if not self._processing_frame ~= true then
			-- end
			-- timer.performWithDelay( 10, function() self:_receiveFrame() end)
			-- self:_receiveFrame()

		end

	end

end




return WebSocket
