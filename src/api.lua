local real_error = error
local function error(str,level)
	if level == nil then level = 1 end
	if type(level) ~= "number" then
		real_error("bad argument: int expected, got " .. type(level),2)
	end
	if level <= 0 then
		level = -2
	end
	str = str == nil and "" or tostring(str)
	local info = debug.getinfo(level+1)
	if info ~= nil then
		str = (info.source == "=[C]" and info.name or info.short_src .. ":" .. info.currentline) .. ": " .. str
	end
	real_error(str,-1)
end

-- HELPER FUNCTIONS
local function lines(str)
	str=str:gsub("\r\n","\n"):gsub("\r","\n"):gsub("\n$","").."\n"
	local out={}
	for line in str:gmatch("([^\n]*)\n") do
		table.insert(out,line)
	end
	return out
end

-- HELPER CLASSES/HANDLES
local HTTPHandle
if _conf.enableAPI_http then
	function HTTPHandle(contents, status)
		local closed = false
		local lineIndex = 1
		local handle
		handle = {
			close = function()
				closed = true
			end,
			readLine = function()
				if closed then return end
				local str = contents[lineIndex]
				lineIndex = lineIndex + 1
				return str
			end,
			readAll = function()
				if closed then return end
				if lineIndex == 1 then
					lineIndex = #contents + 1
					return table.concat(contents, '\n')
				else
					local tData = {}
					local data = handle.readLine()
					while data ~= nil do
						table.insert(tData, data)
						data = handle.readLine()
					end
					return table.concat(tData, '\n')
				end
			end,
			getResponseCode = function()
				return status
			end
		}
		return handle
	end
end

-- Needed for term.write, (file).write, and (file).writeLine
-- This serialzier is bad, it is supposed to be bad. Don't use it.
local function serializeImpl(t, tTracking)	
	local sType = type(t)
	if sType == "table" then
		if tTracking[t] ~= nil then
			return nil
		end
		tTracking[t] = true

		local result = "{"
		for k,v in pairs(t) do
			local cache1 = serializeImpl(k, tTracking)
			local cache2 = serializeImpl(v, tTracking)
			if cache1 ~= nil and cache2 ~= nil then
				result = result..cache1.."="..cache2..", "
			end
		end
		if result:sub(-2,-1) == ", " then result = result:sub(1,-3) end
		result = result.."}"
		return result
	elseif sType == "string" then
		return t
	elseif sType == "number" then
		if t == math.huge then
			return "Infinity"
		elseif t == -math.huge then
			return "-Infinity"
		elseif t ~= t then
			return "NaN"
		else
			return tostring(t):gsub("^[^e.]+%f[^0-9.]","%1.0"):gsub("e%+","e"):upper()
		end
	elseif sType == "boolean" then
		return tostring(t)
	else
		return nil
	end
end

local function serialize(t)
	local tTracking = {}
	return serializeImpl(t, tTracking) or ""
end

local function string_trim(s)
	local from = s:match"^%s*()"
	return from > #s and "" or s:match(".*%S", from)
end

local function FileReadHandle(path)
	if not vfs.exists(path) then
		return nil
	end
	local contents = {}
	for line in vfs.lines(path) do
		table.insert(contents, line)
	end
	local closed = false
	local lineIndex = 1
	local handle
	handle = {
		close = function()
			closed = true
		end,
		readLine = function()
			if closed then return end
			local str = contents[lineIndex]
			lineIndex = lineIndex + 1
			return str
		end,
		readAll = function()
			if closed then return end
			if lineIndex == 1 then
				lineIndex = #contents + 1
				return table.concat(contents, '\n')
			else
				local tData = {}
				local data = handle.readLine()
				while data ~= nil do
					table.insert(tData, data)
					data = handle.readLine()
				end
				return table.concat(tData, '\n')
			end
		end
	}
	return handle
end

local function FileBinaryReadHandle(path)
	if not vfs.exists(path) then
		return nil
	end
	local closed = false
	local File = vfs.newFile(path, "r")
	if File == nil then return end
	local handle = {
		close = function()
			closed = true
			File:close()
		end,
		read = function()
			if closed or File:eof() then return end
			return File:read(1):byte()
		end
	}
	return handle
end

local function FileWriteHandle(path, append)
	local closed = false
	if path:find("/",nil,true) then
		vfs.createDirectory(path:match("(.*)/"))
	end
	local File = vfs.newFile(path, append and "a" or "w")
	if File == nil then return end
	local handle = {
		close = function()
			closed = true
			File:close()
		end,
		writeLine = function(data)
			if closed then error("Stream closed",2) end
			File:write(serialize(data) .. (_conf.useCRLF and "\r\n" or "\n"))
		end,
		write = function(data)
			if closed then error("Stream closed",2) end
			File:write(serialize(data))
		end,
		flush = function()
			File:flush()
		end
	}
	return handle
end

local function FileBinaryWriteHandle(path, append)
	local closed = false
	if path:find("/",nil,true) then
		vfs.createDirectory(path:match("(.*)/"))
	end
	local File = vfs.newFile(path, append and "a" or "w")
	if File == nil then return end
	local handle = {
		close = function()
			closed = true
			File:close()
		end,
		write = function(data)
			if closed then return end
			if type(data) ~= "number" then return end
			while data < 0 do
				data = data + 256
			end
			File:write(string.char(data % 256))
		end,
		flush = function()
			File:flush()
		end
	}
	return handle
end

local ffi=require("ffi")
api = {}
local _tostring_DB = {}
local function addToDB(entry)
	for k,v in pairs(entry) do
		if tostring(v):find("function: builtin#") ~= nil then
			_tostring_DB[v] = k
		end
	end
end
addToDB(_G)
addToDB(math)
addToDB(string)
addToDB(table)
addToDB(coroutine)
function api.tostring(...)
	if select("#",...) == 0 then error("bad argument #1: value expected",2) end
	local thing = ...
	local fix
	if thing == nil then
		return "nil"
	elseif type(thing) == "number" then
		if thing == 1/0 or thing == -1/0 or thing ~= thing or (math.floor(thing) == thing and thing < 2^63 and thing >= -2^63) then
			fix = string.format("%.0f",thing)
		else
			fix = string.format("%.8G",thing):gsub("E%+","E")
		end
		return fix
	elseif type(thing) == "table" then
		fix = tostring(thing):gsub("table: 0x","table: ")
		return fix
	elseif _tostring_DB[thing] ~= nil then
		return _tostring_DB[thing]
	elseif type(thing) == "function" then
		fix = tostring(thing):gsub("function: 0x","function: ")
		return fix
	else
		return tostring(thing)
	end
end
function api.tonumber(...)
	local str, base = ...
	if select("#",...) < 1 then
		error("bad argument #1: value expected",2)
	end
	if base == nil then base = 10 end
	if (type(base) ~= "number" and type(base) ~= "string") or (type(base) == "string" and tonumber(base) == nil) then
		if type(base) == "string" then
			error("bad argument: number expected, got string",2)
		end
		error("bad argument: int expected, got " .. type(base),2)
	end
	base = math.floor(tonumber(base))
	if base < 2 or base >= 37 then
		error("bad argument #2: base out of range",2)
	end
	if base ~= 10 then
		if type(str) ~= "number" and type(str) ~= "string" then
			error("bad argument: string expected, got " .. type(str),2)
		else
			str = string_trim(tostring(str))
		end
	end
	-- Fix some strings.
	if type(str) == "string" and base >= 11 then
		str = str:gsub("%[","4"):gsub("\\","5"):gsub("]","6"):gsub("%^","7"):gsub("_","8"):gsub("`","9")
	end
	if base ~= 10 and str:sub(1,1) == "-" then
		local tmpnum = tonumber(str:sub(2),base)
		return (tmpnum ~= nil and str:sub(2,2) ~= "-") and -tmpnum or nil
	else
		return tonumber(str,base)
	end
end
function api.getfenv(level)
	if level == nil then level = 1 end
	if type(level) ~= "function" and type(level) ~= "number" then
		error("bad argument: " .. (type(level) == "string" and "number" or "int") .. " expected, got " .. type(level),2)
	end
	local stat,env
	if type(level) == "function" then
		env = getfenv(level)
	else
		if level < 0 then
			error("bad argument #1: level must be non-negative",2)
		end
		stat,env = pcall(getfenv,level + 2)
		if not stat then
			error("bad argument #1: invalid level",2)
		end
	end
	if env.love == love then
		return api.env
	end
	return env
end
function api.loadstring(str, source)
	if source == nil then source = "string" end
	if type(str) ~= "string" and type(str) ~= "number" then error("bad argument: string expected, got " .. type(str),2) end
	if type(source) ~= "string" and type(source) ~= "number" then error("bad argument: String expected, got " .. type(str),2) end
	local source2 = tostring(source)
	local sSS = source2:sub(1,1)
	if sSS == "@" or sSS == "=" then
		source2 = source2:sub(2)
	end
	local f, err = loadstring(str, "@" .. source2)
	if f == nil then
		-- Get the normal error message
		local _, err = loadstring(str, source)
		local info = debug.getinfo(2)
		if info ~= nil then
			err = (info.source == "=[C]" and info.name or info.short_src .. ":" .. info.currentline) .. ": " .. err
		end
		return f, err
	end
	jit.off(f) -- Required for "Too long without yielding"
	setfenv(f, api.env)
	return f, err
end
function api.inext(tbl, key)
	if type(tbl) ~= "table" then
		error("bad argument: table expected, got " .. type(tbl),2)
	elseif type(key) ~= "number" then
		error("bad argument: int expected, got " .. type(key),2)
	end
	key = math.floor(key)+1
	if key == key and tbl[key] ~= nil then
		return key, tbl[key]
	end
end

api.term = {}
local function validateColor(color,def)
	if color >= 48 and color <= 57 then
		return color - 48
	elseif color >= 97 and color <= 102 then
		return color - 87
	end
	return def
end
function api.term.blit(text,fg,bg)
	if type(text) ~= "string" or type(fg) ~= "string" or type(bg) ~= "string" then
		error("Expected string, string, string",2)
	end
	if #text ~= #fg or #text ~= #bg then
		error("Arguments must be the same length",2)
	end
	if Computer.state.cursorY > _conf.terminal_height or Computer.state.cursorY < 1 or Computer.state.cursorX > _conf.terminal_width then
		Computer.state.cursorX = Computer.state.cursorX + #text
		return
	end
	for i = 1, #text do
		local char = text:sub(i, i)
		if Computer.state.cursorX + i - 1 >= 1 then
			if Computer.state.cursorX + i - 1 > _conf.terminal_width then
				break
			end
			Screen.textB[Computer.state.cursorY][Computer.state.cursorX + i - 1] = char
			Screen.textColourB[Computer.state.cursorY][Computer.state.cursorX + i - 1] = 2^validateColor(fg:byte(i,i),0)
			Screen.backgroundColourB[Computer.state.cursorY][Computer.state.cursorX + i - 1] = 2^validateColor(bg:byte(i,i),15)
		end
	end
	Computer.state.cursorX = Computer.state.cursorX + #text
	Screen.dirty = true
end
function api.term.clear()
	for y = 1, _conf.terminal_height do
		for x = 1, _conf.terminal_width do
			Screen.textB[y][x] = " "
			Screen.backgroundColourB[y][x] = Computer.state.bg
			Screen.textColourB[y][x] = 1
		end
	end
	Screen.dirty = true
end
function api.term.clearLine()
	if Computer.state.cursorY > _conf.terminal_height or Computer.state.cursorY < 1 then
		return
	end
	for x = 1, _conf.terminal_width do
		Screen.textB[Computer.state.cursorY][x] = " "
		Screen.backgroundColourB[Computer.state.cursorY][x] = Computer.state.bg
		Screen.textColourB[Computer.state.cursorY][x] = 1
	end
	Screen.dirty = true
end
function api.term.getSize()
	return _conf.terminal_width, _conf.terminal_height
end
function api.term.getCursorPos()
	return Computer.state.cursorX, Computer.state.cursorY
end
function api.term.setCursorPos(...)
	local x, y = ...
	if type(x) ~= "number" or type(y) ~= "number" or select("#",...) ~= 2 then error("Expected number, number",2) end
	Computer.state.cursorX = math.floor(x)
	Computer.state.cursorY = math.floor(y)
	Screen.dirty = true
end
function api.term.write(text)
	text = serialize(text)
	if Computer.state.cursorY > _conf.terminal_height or Computer.state.cursorY < 1 or Computer.state.cursorX > _conf.terminal_width then
		Computer.state.cursorX = Computer.state.cursorX + #text
		return
	end

	for i = 1, #text do
		local char = text:sub(i, i)
		if Computer.state.cursorX + i - 1 >= 1 then
			if Computer.state.cursorX + i - 1 > _conf.terminal_width then
				break
			end
			Screen.textB[Computer.state.cursorY][Computer.state.cursorX + i - 1] = char
			Screen.textColourB[Computer.state.cursorY][Computer.state.cursorX + i - 1] = Computer.state.fg
			Screen.backgroundColourB[Computer.state.cursorY][Computer.state.cursorX + i - 1] = Computer.state.bg
		end
	end
	Computer.state.cursorX = Computer.state.cursorX + #text
	Screen.dirty = true
end
function api.term.getTextColor()
	return Computer.state.fg
end
function api.term.setTextColor(...)
	local num = ...
	if type(num) ~= "number" or select("#",...) ~= 1 then error("Expected number",2) end
	if num < 1 or num >= 65536 or num ~= num then
		error("Colour out of range",2)
	end
	num = 2^math.floor(math.log(num)/math.log(2))
	Computer.state.fg = num
	Screen.dirty = true
end
function api.term.getBackgroundColor()
	return Computer.state.bg
end
function api.term.setBackgroundColor(...)
	local num = ...
	if type(num) ~= "number" or select("#",...) ~= 1 then error("Expected number",2) end
	if num < 1 or num >= 65536 or num ~= num then
		error("Colour out of range",2)
	end
	num = 2^math.floor(math.log(num)/math.log(2))
	Computer.state.bg = num
end
function api.term.isColor()
	return true
end
function api.term.setCursorBlink(...)
	local bool = ...
	if type(bool) ~= "boolean" or select("#",...) ~= 1 then error("Expected boolean",2) end
	Computer.state.blink = bool
	Screen.dirty = true
end
function api.term.scroll(...)
	local n = ...
	if type(n) ~= "number" or select("#",...) ~= 1 then error("Expected number",2) end
	local textBuffer = {}
	local backgroundColourBuffer = {}
	local textColourBuffer = {}
	for y = 1, _conf.terminal_height do
		if y - n > 0 and y - n <= _conf.terminal_height then
			textBuffer[y - n] = {}
			backgroundColourBuffer[y - n] = {}
			textColourBuffer[y - n] = {}
			for x = 1, _conf.terminal_width do
				textBuffer[y - n][x] = Screen.textB[y][x]
				backgroundColourBuffer[y - n][x] = Screen.backgroundColourB[y][x]
				textColourBuffer[y - n][x] = Screen.textColourB[y][x]
			end
		end
	end
	for y = 1, _conf.terminal_height do
		if textBuffer[y] ~= nil then
			for x = 1, _conf.terminal_width do
				Screen.textB[y][x] = textBuffer[y][x]
				Screen.backgroundColourB[y][x] = backgroundColourBuffer[y][x]
				Screen.textColourB[y][x] = textColourBuffer[y][x]
			end
		else
			for x = 1, _conf.terminal_width do
				Screen.textB[y][x] = " "
				Screen.backgroundColourB[y][x] = Computer.state.bg
				Screen.textColourB[y][x] = 1 -- Don't need to bother setting text color
			end
		end
	end
	Screen.dirty = true
end

function tablecopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in pairs(orig) do
			copy[orig_key] = orig_value
		end
	else
		copy = orig
	end
	return copy
end

api.cclite = {}
if _conf.enableAPI_cclite then
	function api.cclite.peripheralAttach(sSide, sType)
		if type(sSide) ~= "string" or type(sType) ~= "string" then
			error("Expected string, string",2)
		end
		if not peripheral.base[sType] then
			error("No virtual peripheral of type " .. sType,2)
		end
		if Computer.state.peripherals[sSide] then
			error("Peripheral already attached to " .. sSide,2)
		end
		Computer.state.peripherals[sSide] = peripheral.base[sType](sSide)
		if Computer.state.peripherals[sSide] ~= nil then
			local methods = Computer.state.peripherals[sSide].getMethods()
			Computer.state.peripherals[sSide].cache = {}
			for i = 1,#methods do
				Computer.state.peripherals[sSide].cache[methods[i]] = true
			end
			local ccliteMethods = Computer.state.peripherals[sSide].ccliteGetMethods()
			Computer.state.peripherals[sSide].ccliteCache = {}
			for i = 1,#ccliteMethods do
				Computer.state.peripherals[sSide].ccliteCache[ccliteMethods[i]] = true
			end
			table.insert(Computer.eventQueue, {"peripheral",sSide})
		else
			error("No peripheral added",2)
		end
	end
	function api.cclite.peripheralDetach(sSide)
		if type(sSide) ~= "string" then error("Expected string",2) end
		if not Computer.state.peripherals[sSide] then
			error("No peripheral attached to " .. sSide,2)
		end
		Computer.state.peripherals[sSide] = nil
		table.insert(Computer.eventQueue, {"peripheral_detach",sSide})
	end
	function api.cclite.getMethods(sSide)
		if type(sSide) ~= "string" then error("Expected string",2) end
		if Computer.state.peripherals[sSide] then return Computer.state.peripherals[sSide].ccliteGetMethods() end
		return
	end
	function api.cclite.call(sSide, sMethod, ...)
		if type(sSide) ~= "string" then error("Expected string",2) end
		if type(sMethod) ~= "string" then error("Expected string, string",2) end
		if not Computer.state.peripherals[sSide] then error("No peripheral attached",2) end
		return Computer.state.peripherals[sSide].ccliteCall(sMethod, ...)
	end
	function api.cclite.message(sMessage)
		if type(sMessage) ~= "string" then error("Expected string",2) end
		Screen:message(sMessage)
	end
end

if _conf.enableAPI_http then
	local https_alert=false
	api.http = {}
	function api.http.checkURL(sUrl)
		if type(sUrl) ~= "string" then
			error("Expected string",2)
		end
		local goodUrl = string_trim(sUrl)
		if goodUrl:sub(1,4) == "ftp:" or goodUrl:sub(1,5) == "file:" or goodUrl:sub(1,7) == "mailto:" then
			return false, "URL not http"
		end
		if goodUrl:sub(1,5) ~= "http:" and goodUrl:sub(1,6) ~= "https:" then
			return false, "URL malformed"
		end
		return true
	end
	function api.http.request(sUrl, sParams, tHeaders)
		if type(sUrl) ~= "string" then
			error("Expected string",2)
		end
		local goodUrl = string_trim(sUrl)
		if goodUrl:sub(1,4) == "ftp:" or goodUrl:sub(1,5) == "file:" or goodUrl:sub(1,7) == "mailto:" then
			return false, "URL not http"
		end
		if goodUrl:sub(1,5) ~= "http:" and goodUrl:sub(1,6) ~= "https:" then
			return false, "URL malformed"
		end
		if goodUrl:sub(1,6) == "https:" and not _conf.useLuaSec then
			if not https_alert then
				https_alert=true
				Screen:message("Warning: No HTTPS support enabled, falling back to HTTP")
			end
			print("Warning: Attempted to load page \"" .. goodUrl .. "\" without HTTPS support enabled")
		end
		if type(sParams) ~= "string" then
			sParams = nil
		end
		local http = HttpRequest.new()
		local method = sParams and "POST" or "GET"

		http.open(method, goodUrl, true)

		if method == "POST" then
			http.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
			http.setRequestHeader("Content-Length", sParams:len())
		end

		if type(tHeaders) == "table" then
			for k, v in pairs(tHeaders) do
				if type(k) == "string" and type(v) == "string" then
					local lk=string.lower(k)
					if lk ~= "host" and lk ~= "connection" then
						http.setRequestHeader(k, v)
					end
				end
			end
		end

		http.onReadyStateChange = function()
			if http.status == 200 then
				local handle = HTTPHandle(lines(http.responseText), http.status)
				table.insert(Computer.eventQueue, {"http_success", sUrl, handle})
			else
				table.insert(Computer.eventQueue, {"http_failure", sUrl, "Could not connect"})
			end
		end

		http.send(sParams)
		return true
	end
end

api.os = {}
function api.os.clock()
	return tonumber(string.format("%0.2f",math.floor(love.timer.getTime()*20)/20 - Computer.state.startTime))
end
function api.os.time()
	return math.floor(((love.timer.getTime()-Computer.state.startTime)*0.02)%24*1000)/1000
end
function api.os.day()
	return math.floor((love.timer.getTime()-Computer.state.startTime)/1200)
end
function api.os.setComputerLabel(label)
	if type(label) == "function" then label = nil end
	if type(label) ~= "string" and type(label) ~= "nil" then error("Expected string or nil",2) end
	Computer.state.label = label:sub(1,32)
end
function api.os.getComputerLabel()
	return Computer.state.label
end
function api.os.queueEvent(event, ...)
	if type(event) ~= "string" then error("Expected string",2) end
	table.insert(Computer.eventQueue, {event, ...})
end
function api.os.startTimer(nTimeout)
	if type(nTimeout) ~= "number" then error("Expected number",2) end
	nTimeout = math.ceil(nTimeout*20)/20
	if nTimeout < 0.05 then nTimeout = 0.05 end
	Computer.actions.timers[Computer.actions.lastTimer] = math.floor(love.timer.getTime()*20)/20 + nTimeout
	Computer.actions.lastTimer = Computer.actions.lastTimer + 1
	return Computer.actions.lastTimer-1
end
function api.os.setAlarm(nTime)
	if type(nTime) ~= "number" then error("Expected number",2) end
	if nTime < 0 or nTime > 24 then
		error("Number out of range",2)
	end
	local alarm = {
		time = nTime,
		day = api.os.day() + (nTime < api.os.time() and 1 or 0)
	}
	Computer.actions.alarms[Computer.actions.lastAlarm] = alarm
	Computer.actions.lastAlarm = Computer.actions.lastAlarm + 1
	return Computer.actions.lastAlarm-1
end
function api.os.cancelTimer(id)
	if type(id) ~= "number" then error("Expected number",2) end
	if id == id then
		Computer.actions.timers[id] = nil
	end
end
function api.os.cancelAlarm(id)
	if type(id) ~= "number" then error("Expected number",2) end
	if id == id then
		Computer.actions.alarms[id] = nil
	end
end
function api.os.shutdown()
	Computer:stop(false)
end
function api.os.reboot()
	Computer:stop(true) -- Reboots on next update/tick
end

api.peripheral = {}
function api.peripheral.isPresent(sSide)
	if type(sSide) ~= "string" then error("Expected string",2) end
	return Computer.state.peripherals[sSide] ~= nil
end
function api.peripheral.getType(sSide)
	if type(sSide) ~= "string" then error("Expected string",2) end
	if Computer.state.peripherals[sSide] then return peripheral.types[Computer.state.peripherals[sSide].type] end
	return
end
function api.peripheral.getMethods(sSide)
	if type(sSide) ~= "string" then error("Expected string",2) end
	if Computer.state.peripherals[sSide] then return Computer.state.peripherals[sSide].getMethods() end
	return
end
function api.peripheral.call(sSide, sMethod, ...)
	if type(sSide) ~= "string" or type(sMethod) ~= "string" then
		if sSide == nil or type(sMethod) ~= "string" then
			error("Expected string, string",2)
		else
			error("Expected string",2)
		end
	end
	if not Computer.state.peripherals[sSide] then error("No peripheral attached",2) end
	if not Computer.state.peripherals[sSide].cache[sMethod] then
		error("No such method " .. sMethod,2)
	end
	return Computer.state.peripherals[sSide].call(sMethod, ...)
end

api.fs = {}

local function cleanPath(path,wildcard)
	local path = path:gsub("\\", "/"):gsub("[\":<>%?|" .. (wildcard and "" or "%*") .. "]","")

	local tPath = {}
	for part in path:gmatch("[^/]+") do
		if part ~= "" and part ~= "." then
			if part == ".." and #tPath > 0 and tPath[#tPath] ~= ".." then
				table.remove(tPath)
			else
				table.insert(tPath, part:sub(1,255))
			end
		end
	end
	return table.concat(tPath, "/")
end

function api.fs.combine(...)
	local basePath, localPath = ...
	if type(basePath) ~= "string" or type(localPath) ~= "string" or select("#",...) ~= 2 then
		error("Expected string, string",2)
	end

	return cleanPath(("/" .. basePath .. "/" .. localPath):gsub("\\", "/"), true)
end

local function contains(pathA, pathB)
	pathA = cleanPath(pathA)
	pathB = cleanPath(pathB)

	if pathB == ".." then
		return false
	elseif pathB:sub(1,3) == "../" then
		return false
	elseif pathB == pathA then
		return true
	elseif #pathA == 0 then
		return true
	else
		return pathB:sub(1,#pathA+1) == pathA .. "/"
	end
end

local function recurse_spec(results, path, spec)
	local segment = spec:match('([^/]*)'):gsub('/', '')
	local pattern = '^' .. segment:gsub("[%.%[%]%(%)%%%+%-%?%^%$]","%%%1"):gsub("%z","%%z"):gsub("%*","[^/]-") .. '$'

	if api.fs.isDir(path) then
		for _, file in ipairs(api.fs.list(path)) do
			if file:match(pattern) then
				local f = api.fs.combine(path, file)

				if spec == segment then
					table.insert(results, f)
				end
				if api.fs.isDir(f) then
					recurse_spec(results, f, spec:sub(#segment + 2))
				end
			end
		end
	end
end

function api.fs.getDir(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	path = cleanPath(path, true)
	if #path == 0 then
		return ".."
	else
		return path:match("(.*)/") or ""
	end
end
function api.fs.find(...)
	local spec = ...
	if type(spec) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	spec = cleanPath(spec, true)
	local results = {}
	recurse_spec(results, '', spec)
	return results
end
local fsmodes = {r=FileReadHandle, rb=FileBinaryReadHandle, w=FileWriteHandle, a=FileWriteHandle, wb=FileBinaryWriteHandle, ab=FileBinaryWriteHandle}
function api.fs.open(...)
	local path, mode = ...
	if type(path) ~= "string" or type(mode) ~= "string" or select("#",...) ~= 2 then
		error("Expected string, string",2)
	end

	path = cleanPath(path)
	if path == ".." or path:sub(1,3) == "../" then error("Invalid Path",2) end

	local fsfunc = fsmodes[mode]
	if fsfunc == nil then error("Unsupported mode",2) end

	if vfs.isDirectory(path) then return end

	return fsfunc(path, mode == "a" or mode == "ab")
end
function api.fs.list(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end

	path = cleanPath(path)
	if path == ".." or path:sub(1,3) == "../" then error("Invalid Path",2) end

	if not vfs.exists(path) or not vfs.isDirectory(path) then
		error("Not a directory",2)
	end
	return vfs.getDirectoryItems(path)
end
function api.fs.exists(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end

	path = cleanPath(path)
	if path == ".." or path:sub(1,3) == "../" then return false end

	return vfs.exists(path)
end
function api.fs.isDir(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end

	path = cleanPath(path)
	if path == ".." or path:sub(1,3) == "../" then return false end

	return vfs.isDirectory(path)
end
function api.fs.isReadOnly(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	path = cleanPath(path)
	return path == "rom" or path:sub(1, 4) == "rom/"
end
function api.fs.getName(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	path = cleanPath(path, true)
	if path == "" then
		return "root"
	else
		return path:match(".*/(.+)") or path
	end
end
function api.fs.getDrive(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end

	path = cleanPath(path)
	if path == ".." or path:sub(1,3) == "../" then error("Invalid Path",2) end

	if not vfs.exists(path) then
		return
	end
	local mountEntry = vfs.getMountContainer(path)
	return mountEntry[4]
end
function api.fs.getSize(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end

	path = cleanPath(path)
	if path == ".." or path:sub(1,3) == "../" then error("Invalid Path",2) end

	if vfs.exists(path) ~= true then
		error("No such file",2)
	end

	if vfs.isDirectory(path) then
		return 0
	end

	return vfs.getSize(path)
end

function api.fs.getFreeSpace(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end

	path = cleanPath(path)
	if path == ".." or path:sub(1,3) == "../" then error("Invalid Path",2) end

	if path == "rom" or path:sub(1, 4) == "rom/" then
		return 0
	end
	return math.huge
end

function api.fs.makeDir(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end

	path = cleanPath(path)
	if path == ".." or path:sub(1,3) == "../" then error("Invalid Path",2) end

	if path == "rom" or path:sub(1, 4) == "rom/" then
		error("Access Denied",2)
	end
	if vfs.exists(path) and not vfs.isDirectory(path) then
		error("File exists",2)
	end
	vfs.createDirectory(path)
end

local function deltree(sFolder)
	local tObjects = vfs.getDirectoryItems(sFolder)

	if tObjects then
		for _, sObject in pairs(tObjects) do
			local pObject = sFolder.."/"..sObject

			if vfs.isDirectory(pObject) then
				deltree(pObject)
			end
			vfs.remove(pObject)
		end
	end
	return vfs.remove(sFolder)
end
api._deltree = deltree

local function copytree(sFolder, sToFolder)
	if not vfs.isDirectory(sFolder) then
		vfs.write(sToFolder, vfs.read(sFolder))
		return
	end
	vfs.createDirectory(sToFolder)
	local tObjects = vfs.getDirectoryItems(sFolder)

	if tObjects then
		for _, sObject in pairs(tObjects) do
			local pObject = sFolder.."/"..sObject
			local pToObject = sToFolder.."/"..sObject

			if vfs.isDirectory(pObject) then
				vfs.createDirectory(pToObject)
				copytree(pObject,pToObject)
			else
				vfs.write(pToObject, vfs.read(pObject))
			end
		end
	end
end
api._copytree = copytree

function api.fs.move(...)
	local fromPath, toPath = ...
	if type(fromPath) ~= "string" or type(toPath) ~= "string" or select("#",...) ~= 2 then
		error("Expected string, string",2)
	end

	fromPath = cleanPath(fromPath)
	if fromPath == ".." or fromPath:sub(1,3) == "../" then error("Invalid Path",2) end
	toPath = cleanPath(toPath)
	if toPath == ".." or toPath:sub(1,3) == "../" then error("Invalid Path",2) end

	if fromPath == "rom" or fromPath:sub(1, 4) == "rom/" or
		toPath == "rom" or toPath:sub(1, 4) == "rom/" then
		error("Access denied",2)
	end
	if not vfs.exists(fromPath) then
		error("No such file",2)
	elseif vfs.exists(toPath) then
		error("File exists",2)
	elseif contains(fromPath, toPath) then
		error("Can't move a directory inside itself",2)
	end
	copytree(fromPath, toPath)
	deltree(fromPath)
end

function api.fs.copy(...)
	local fromPath, toPath = ...
	if type(fromPath) ~= "string" or type(toPath) ~= "string" or select("#",...) ~= 2 then
		error("Expected string, string",2)
	end

	fromPath = cleanPath(fromPath)
	if fromPath == ".." or fromPath:sub(1,3) == "../" then error("Invalid Path",2) end
	toPath = cleanPath(toPath)
	if toPath == ".." or toPath:sub(1,3) == "../" then error("Invalid Path",2) end

	if toPath == "rom" or toPath:sub(1, 4) == "rom/" then
		error("Access denied",2)
	elseif not vfs.exists(fromPath) then
		error("No such file",2)
	elseif vfs.exists(toPath) then
		error("File exists",2)
	elseif contains(fromPath, toPath) then
		error("Can't copy a directory inside itself",2)
	end
	copytree(fromPath, toPath)
end

function api.fs.delete(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end

	path = cleanPath(path)
	if path == ".." or path:sub(1,3) == "../" then error("Invalid Path",2) end

	if path == "rom" or path:sub(1, 4) == "rom/" or vfs.isMountPath(path) then
		error("Access Denied",2)
	end
	deltree(path)
end

api.redstone = {}
local outputs = {top=0, bottom=0, left=0, right=0, front=0, back=0}
local bundled = {top=0, bottom=0, left=0, right=0, front=0, back=0}
function api.redstone.getSides()
	return {"top","bottom","left","right","front","back"}
end
function api.redstone.getInput(side)
	if type(side) ~= "string" then
		error("Expected string",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return false
end
function api.redstone.setOutput(side, value)
	if type(side) ~= "string" or type(value) ~= "boolean" then
		error("Expected string, boolean",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	outputs[side] = value and 15 or 0
end
function api.redstone.getOutput(side)
	if type(side) ~= "string" then
		error("Expected string",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return outputs[side] > 0
end
function api.redstone.getAnalogInput(side)
	if type(side) ~= "string" then
		error("Expected string",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return 0
end
function api.redstone.setAnalogOutput(side, strength)
	if type(side) ~= "string" or type(strength) ~= "number" then
		error("Expected string, number",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	elseif strength <= -1 or strength >= 16 then
		error("Expected number in range 0-15",2)
	end
	outputs[side] = math.floor(strength)
end
function api.redstone.getAnalogOutput(side)
	if type(side) ~= "string" then
		error("Expected string",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return outputs[side]
end
function api.redstone.getAnalogueInput(side)
	if type(side) ~= "string" then
		error("Expected string",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return 0
end
function api.redstone.setAnalogueOutput(side, strength)
	if type(side) ~= "string" or type(strength) ~= "number" then
		error("Expected string, number",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	elseif strength <= -1 or strength >= 16 then
		error("Expected number in range 0-15",2)
	end
	outputs[side] = math.floor(strength)
end
function api.redstone.getAnalogueOutput(side)
	if type(side) ~= "string" then
		error("Expected string",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return outputs[side]
end
function api.redstone.getBundledInput(side)
	if type(side) ~= "string" then
		error("Expected string",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return 0
end
function api.redstone.getBundledOutput(side)
	if type(side) ~= "string" then
		error("Expected string",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return bundled[side]
end
function api.redstone.setBundledOutput(side, colors)
	if type(side) ~= "string" or type(colors) ~= "number" then
		error("Expected string, number",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	bundled[side] = math.max(math.min(math.floor(colors),2^31),0)
end
function api.redstone.testBundledInput(side, color)
	if type(side) ~= "string" or type(color) ~= "number" then
		error("Expected string, number",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return color == 0 or color ~= color
end

api.bit = {}
local function cleanValue(val)
	if val ~= val or val == -math.huge then
		return 0
	elseif val == math.huge then
		return -1
	end
	return val
end
function api.bit.norm(val)
	while val < 0 do val = val + 4294967296 end
	return val
end
function api.bit.blshift(n, bits)
	if type(n) ~= "number" or type(bits) ~= "number" then
		error("Expected number, number",2)
	end
	n,bits=cleanValue(n),cleanValue(bits)
	return api.bit.norm(bit.lshift(n, bits))
end
function api.bit.brshift(n, bits)
	if type(n) ~= "number" or type(bits) ~= "number" then
		error("Expected number, number",2)
	end
	n,bits=cleanValue(n),cleanValue(bits)
	return api.bit.norm(bit.arshift(n, bits))
end
function api.bit.blogic_rshift(n, bits)
	if type(n) ~= "number" or type(bits) ~= "number" then
		error("Expected number, number",2)
	end
	n,bits=cleanValue(n),cleanValue(bits)
	return api.bit.norm(bit.rshift(n, bits))
end
function api.bit.bxor(m, n)
	if type(m) ~= "number" or type(n) ~= "number" then
		error("Expected number, number",2)
	end
	m,n=cleanValue(m),cleanValue(n)
	return api.bit.norm(bit.bxor(m, n))
end
function api.bit.bor(m, n)
	if type(m) ~= "number" or type(n) ~= "number" then
		error("Expected number, number",2)
	end
	m,n=cleanValue(m),cleanValue(n)
	return api.bit.norm(bit.bor(m, n))
end
function api.bit.band(m, n)
	if type(m) ~= "number" or type(n) ~= "number" then
		error("Expected number, number",2)
	end
	m,n=cleanValue(m),cleanValue(n)
	return api.bit.norm(bit.band(m, n))
end
function api.bit.bnot(n)
	if type(n) ~= "number" then
		error("Expected number",2)
	end
	n=cleanValue(n)
	return api.bit.norm(bit.bnot(n))
end

local randseed=ffi.new("uint64_t")
function rnext(bits)
	randseed=(randseed*0x5DEECE66D+0xB)%2^48
	return randseed/(2^(48-bits))
end
function rnextInt(n)
	if bit.band(n,-n)==bit.tobit(n) then
		return tonumber((n*rnext(31))/2^31)
	end
	local val
	repeat
		local bits=tonumber(rnext(31))
		val=bits%n
	until bits-val+(n-1)>=0
	return val
end
api.math=tablecopy(math)
function api.math.randomseed(num)
	if type(num)~="number" then
		error("bad argument #1: number expected, got "..type(num),2)
	end
	num=((num==math.huge or num==1/0) and -1) or (num~=num and 0) or math.floor(num)
	randseed=(ffi.cast("uint64_t",bit.bxor(math.floor(num/2^32)%2^16,5))*2^32)+tonumber(bit.tohex(bit.bxor(num%2^32,0xDEECE66D)),16)
end
function api.math.random(a,b)
	if b==nil then
		if a==nil then
			local n=tonumber((rnext(26)*(2^27))+rnext(27))/2^53
			if n==1 or n==0 then
				return n
			end
			local c=1
			while n<0.1 do
				n=n*10
				c=c*0.1
			end
			return n*c
		else
			if type(a)~="number" then
				error("bad argument #1: number expected, got "..type(a),2)
			elseif a<1 or a==math.huge or a~=a or a==1/0 then
				error("bad argument #1: interval is empty",2)
			end
			return 1+rnextInt(math.floor(a))
		end
	else
		if type(a)~="number" then
			error("bad argument #1: number expected, got "..type(a),2)
		elseif type(b)~="number" then
			error("bad argument #2: number expected, got "..type(b),2)
		elseif a==math.huge or a~=a or a==1/0 then
			error("bad argument #1: interval is empty",2)
		elseif b==math.huge or b~=b or b==1/0 or b<a then
			error("bad argument #2: interval is empty",2)
		end
		return a+rnextInt(b+1-a)
	end
end

_tostring_DB[coroutine.create] = nil
_tostring_DB[string.gmatch] = "gmatch" -- what ...
_tostring_DB[api.tostring] = "tostring"
_tostring_DB[api.tonumber] = "tonumber"
_tostring_DB[api.loadstring] = "loadstring"
_tostring_DB[api.inext] = "__inext"
_tostring_DB[api.math.random] = "random"
_tostring_DB[api.math.randomseed] = "randomseed"
_tostring_DB[api.getfenv] = "getfenv"
_tostring_DB[error] = "error"

function api.init() -- Called after this file is loaded! Important. Else api.x is not defined
	api.math.randomseed(math.random(0,0xFFFFFFFFFFFF))
	api.env = {
		_CC_VERSION="1.75",
		_LUAJ_VERSION="2.0.3",
		_MC_VERSION="1.7.10",
		_VERSION="Lua 5.1",
		__inext = api.inext,
		tostring = api.tostring,
		tonumber = api.tonumber,
		unpack = unpack,
		getfenv = api.getfenv,
		setfenv = setfenv,
		rawequal = rawequal,
		rawset = rawset,
		rawget = rawget,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		next = next,
		type = type,
		select = select,
		assert = assert,
		error = error,
		ipairs = ipairs,
		pairs = pairs,
		pcall = pcall,
		xpcall = xpcall,
		loadstring = api.loadstring,
		math = api.math,
		string = tablecopy(string),
		table = tablecopy(table),
		coroutine = tablecopy(coroutine),

		-- CC apis (BIOS completes api.)
		term = {
			blit = api.term.blit,
			clear = api.term.clear,
			clearLine = api.term.clearLine,
			getSize = api.term.getSize,
			getCursorPos = api.term.getCursorPos,
			setCursorPos = api.term.setCursorPos,
			getTextColor = api.term.getTextColor,
			getTextColour = api.term.getTextColor,
			setTextColor = api.term.setTextColor,
			setTextColour = api.term.setTextColor,
			getBackgroundColor = api.term.getBackgroundColor,
			getBackgroundColour = api.term.getBackgroundColor,
			setBackgroundColor = api.term.setBackgroundColor,
			setBackgroundColour = api.term.setBackgroundColor,
			setCursorBlink = api.term.setCursorBlink,
			scroll = api.term.scroll,
			write = api.term.write,
			isColor = api.term.isColor,
			isColour = api.term.isColor,
		},
		fs = {
			getDir = api.fs.getDir,
			find = api.fs.find,
			open = api.fs.open,
			list = api.fs.list,
			exists = api.fs.exists,
			isDir = api.fs.isDir,
			isReadOnly = api.fs.isReadOnly,
			getName = api.fs.getName,
			getDrive = api.fs.getDrive,
			getSize = api.fs.getSize,
			getFreeSpace = api.fs.getFreeSpace,
			makeDir = api.fs.makeDir,
			move = api.fs.move,
			copy = api.fs.copy,
			delete = api.fs.delete,
			combine = api.fs.combine,
		},
		os = {
			clock = api.os.clock,
			getComputerID = function() return 0 end,
			computerID = function() return 0 end,
			setComputerLabel = api.os.setComputerLabel,
			getComputerLabel = api.os.getComputerLabel,
			computerLabel = api.os.getComputerLabel,
			queueEvent = api.os.queueEvent,
			startTimer = api.os.startTimer,
			setAlarm = api.os.setAlarm,
			cancelTimer = api.os.cancelTimer,
			cancelAlarm = api.os.cancelAlarm,
			time = api.os.time,
			day = api.os.day,
			shutdown = api.os.shutdown,
			reboot = api.os.reboot,
		},
		peripheral = {
			isPresent = api.peripheral.isPresent,
			getType = api.peripheral.getType,
			getMethods = api.peripheral.getMethods,
			call = api.peripheral.call,
		},
		redstone = {
			getSides = api.redstone.getSides,
			getInput = api.redstone.getInput,
			getOutput = api.redstone.getOutput,
			getBundledInput = api.redstone.getBundledInput,
			getBundledOutput = api.redstone.getBundledOutput,
			getAnalogInput = api.redstone.getAnalogInput,
			getAnalogOutput = api.redstone.getAnalogOutput,
			getAnalogueInput = api.redstone.getAnalogueInput,
			getAnalogueOutput = api.redstone.getAnalogueOutput,
			setOutput = api.redstone.setOutput,
			setBundledOutput = api.redstone.setBundledOutput,
			setAnalogOutput = api.redstone.setAnalogOutput,
			setAnalogueOutput = api.redstone.setAnalogueOutput,
			testBundledInput = api.redstone.testBundledInput,
		},
		bit = {
			blshift = api.bit.blshift,
			brshift = api.bit.brshift,
			blogic_rshift = api.bit.blogic_rshift,
			bxor = api.bit.bxor,
			bor = api.bit.bor,
			band = api.bit.band,
			bnot = api.bit.bnot,
		},
	}
	if _conf.enableAPI_http then
		api.env.http = {
			checkURL = api.http.checkURL,
			request = api.http.request,
		}
	end
	if _conf.enableAPI_cclite then
		api.env.cclite = {
			peripheralAttach = api.cclite.peripheralAttach,
			peripheralDetach = api.cclite.peripheralDetach,
			getMethods = api.cclite.getMethods,
			call = api.cclite.call,
			log = print,
			message = api.cclite.message,
			traceback = debug.traceback,
		}
	end
	api.env.rs = api.env.redstone
	api.env.math.mod = nil
	api.env.string.gfind = nil
	api.env._G = api.env
end
api.init()
