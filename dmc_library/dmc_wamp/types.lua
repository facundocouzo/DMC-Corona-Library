--====================================================================--
-- dmc_wamp.types
--
--
-- by David McCuskey
-- Documentation: http://docs.davidmccuskey.com/display/docs/dmc_wamp.lua
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

--[[
Wamp support adapted from:
* AutobahnPython (https://github.com/tavendo/AutobahnPython/)
--]]


-- Semantic Versioning Specification: http://semver.org/

local VERSION = "0.1.0"


--====================================================================--
-- Imports

local Objects = require( dmc_lib_func.find('dmc_objects') )
-- local States = require( dmc_lib_func.find('dmc_states') )
local Utils = require( dmc_lib_func.find('dmc_utils') )
local WebSocket = require( dmc_lib_func.find('dmc_websockets') )

local MessageFactory = require( dmc_lib_func.find('dmc_wamp.messages') )
local Role = require( dmc_lib_func.find('dmc_wamp.roles') )

local wamp_utils = require( dmc_lib_func.find('dmc_wamp.utils') )


--====================================================================--
-- Setup, Constants

-- setup some aliases to make code cleaner
local inheritsFrom = Objects.inheritsFrom
local ObjectBase = Objects.ObjectBase

-- local control of development functionality
local LOCAL_DEBUG = false



--====================================================================--
-- Close Details Class
--====================================================================--

local CloseDetailsObj = inheritsFrom( ObjectBase )

function CloseDetailsObj:_init( params )
	-- print( "CloseDetailsObj_init" )
	self:superCall( "_init", params )
	--==--
	self.reason = params.reason
	self.message = params.message
end



--====================================================================--
-- Call Details Class
--====================================================================--

local CallDetails = inheritsFrom( ObjectBase )

function CallDetails:_init( params )
	self:superCall( "_init", params )
	--==--
	self.progress = params.progress
	self.caller = params.caller
	self.authid = params.authid
	self.authrole = params.authrole
	self.authrole = params.authrole
end






--====================================================================--
-- Close Details Constructor
--====================================================================--


local function CloseDetails( params )
	return CloseDetailsObj:new( params )
end


return {
	CloseDetails=CloseDetails
}
