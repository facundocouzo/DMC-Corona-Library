--====================================================================--
-- lua_patch.lua
--
--
-- by David McCuskey
-- Documentation: http://docs.davidmccuskey.com/display/docs/lua_patch.lua
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
-- DMC Lua Library : Lua Patch
--====================================================================--

-- Semantic Versioning Specification: http://semver.org/

local VERSION = "0.2.0"


--====================================================================--
-- Setup, Constants

local lua_patch_data = {
	string_format_active = false,
	table_pop_active = false
}

local PATCH_TABLE_POP = 'table-pop'
local PATCH_STRING_FORMAT = 'string-format'
local doTablePopPatch, doStringFormatPatch


--====================================================================--
--== Support Function

local function addPatch( input )

	if type(input)=='table' then
		-- pass
	elseif type(input)=='string' then
		input = { input }
	elseif type(input)=='nil' then
		input = { PATCH_TABLE_POP, PATCH_STRING_FORMAT }
	else
		error("Lua Patch:: unknown patch type '" .. type(input) .. "'" )
	end

	for i, patch_name in ipairs( input ) do
		if patch_name == PATCH_TABLE_POP then
			doTablePopPatch()

		elseif patch_name == PATCH_STRING_FORMAT then
			doStringFormatPatch()

		else
			error("Lua Patch:: unknown patch name '" .. tostring( patch ) .. "'" )
		end
	end
end



--====================================================================--
-- Patch Work
--====================================================================--


--====================================================================--
--== Python-style string formatting

-- stringFormatting()
-- implement Python-style string replacement
-- http://lua-users.org/wiki/StringInterpolation
--
local function stringFormatting( a, b )
	if not b then
		return a
	elseif type(b) == "table" then
		return string.format(a, unpack(b))
	else
		return string.format(a, b)
	end
end

doStringFormatPatch = function()
	if not lua_patch_data.string_format_active then
		print( "Lua Patch::activating patch '" .. PATCH_STRING_FORMAT .. "'" )
		getmetatable("").__mod = stringFormatting
		lua_patch_data.string_format_active = true
	end
end


--====================================================================--
--== Python-style table pop() method

-- tablePop()
--
local function tablePop( t, v )
	local res = t[v]
	t[v] = nil
	return res
end

doTablePopPatch = function()
	if not lua_patch_data.table_pop_active then
		print( "Lua Patch::activating patch '" .. PATCH_TABLE_POP .. "'" )
		table.pop = tablePop
		lua_patch_data.table_pop_active = true
	end
end



--====================================================================--
-- Patch Facade
--====================================================================--

return addPatch
