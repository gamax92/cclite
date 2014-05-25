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
	if append and not vfs.exists(path) then
		return nil
	end
	local closed = false
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
	local something = ...
	if something == nil then return "nil" end
	return _tostring_DB[something] or tostring(something)
end
function api.tonumber(...)
	local str, base = ...
	if select("#",...) < 1 then
		error("bad argument #1: value expected",2)
	end
	base = base or 10
	if (type(base) ~= "number" and type(base) ~= "string") or (type(base) == "string" and tonumber(base) == nil) then
		if type(base) == "string" then
			error("bad argument: number expected, got " .. type(base),2)
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
			str = tostring(str)
		end
	end
	-- Fix some strings.
	if type(str) == "string" and base >= 11 then
		str = str:gsub("%[","4"):gsub("\\","5"):gsub("]","6"):gsub("%^","7"):gsub("_","8"):gsub(string.char(96),"9")
	end
	if base ~= 10 and str:sub(1,1) == "-" then
		local tmpnum = tonumber(str:sub(2),base)
		return (tmpnum ~= nil and str:sub(2,2) ~= "-") and -tmpnum or nil
	else
		return tonumber(str,base)
	end
end
function api.getfenv(level)
	level = level or 1
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
function api.error(str,level)
	level = level or 1
	if type(level) ~= "number" then
		error("bad argument #2: number expected, got " .. type(level),2)
	end
	if level == 0 then
		level = -1 -- Prevent defect caused by this error fix.
	end
	local info = debug.getinfo(level+1)
	if info ~= nil and info.source == "=[C]" and level >= 1 then
		str = info.name .. ": " .. tostring(str)
	end
	error(str,level+1)
end
function api.loadstring(str, source)
	source = source or "string"
	if type(str) ~= "string" and type(str) ~= "number" then error("bad argument: string expected, got " .. type(str),2) end
	if type(source) ~= "string" and type(source) ~= "number" then error("bad argument: string expected, got " .. type(str),2) end
	local source2 = tostring(source)
	local sSS = source2:sub(1,1)
	if sSS == "@" or sSS == "=" then
		source2 = source2:sub(2)
	end
	local f, err = loadstring(str, "@" .. source2)
	if f == nil then
		-- Get the normal error message
		local _, err = loadstring(str, source)
		return f, err
	end
	jit.off(f) -- Required for "Too long without yielding"
	setfenv(f, api.env)
	return f, err
end

api.term = {}
function api.term.clear()
	for y = 1, _conf.terminal_height do
		for x = 1, _conf.terminal_width do
			Screen.textB[y][x] = " "
			Screen.backgroundColourB[y][x] = Emulator.state.bg
			Screen.textColourB[y][x] = 1
		end
	end
	Screen.dirty = true
end
function api.term.clearLine()
	if Emulator.state.cursorY > _conf.terminal_height or Emulator.state.cursorY < 1 then
		return
	end
	for x = 1, _conf.terminal_width do
		Screen.textB[Emulator.state.cursorY][x] = " "
		Screen.backgroundColourB[Emulator.state.cursorY][x] = Emulator.state.bg
		Screen.textColourB[Emulator.state.cursorY][x] = 1
	end
	Screen.dirty = true
end
function api.term.getSize()
	return _conf.terminal_width, _conf.terminal_height
end
function api.term.getCursorPos()
	return Emulator.state.cursorX, Emulator.state.cursorY
end
function api.term.setCursorPos(...)
	local x, y = ...
	if type(x) ~= "number" or type(y) ~= "number" or select("#",...) ~= 2 then error("Expected number, number",2) end
	Emulator.state.cursorX = math.floor(x)
	Emulator.state.cursorY = math.floor(y)
	Screen.dirty = true
end
function api.term.write(text)
	text = serialize(text)
	if Emulator.state.cursorY > _conf.terminal_height or Emulator.state.cursorY < 1 or Emulator.state.cursorX > _conf.terminal_width then
		Emulator.state.cursorX = Emulator.state.cursorX + #text
		return
	end

	for i = 1, #text do
		local char = text:sub(i, i)
		if Emulator.state.cursorX + i - 1 >= 1 then
			if Emulator.state.cursorX + i - 1 > _conf.terminal_width then
				break
			end
			Screen.textB[Emulator.state.cursorY][Emulator.state.cursorX + i - 1] = char
			Screen.textColourB[Emulator.state.cursorY][Emulator.state.cursorX + i - 1] = Emulator.state.fg
			Screen.backgroundColourB[Emulator.state.cursorY][Emulator.state.cursorX + i - 1] = Emulator.state.bg
		end
	end
	Emulator.state.cursorX = Emulator.state.cursorX + #text
	Screen.dirty = true
end
function api.term.setTextColor(...)
	local num = ...
	if type(num) ~= "number" or select("#",...) ~= 1 then error("Expected number",2) end
	if num < 1 or num >= 65536 then
		error("Colour out of range",2)
	end
	num = 2^math.floor(math.log(num)/math.log(2))
	Emulator.state.fg = num
	Screen.dirty = true
end
function api.term.setBackgroundColor(...)
	local num = ...
	if type(num) ~= "number" or select("#",...) ~= 1 then error("Expected number",2) end
	if num < 1 or num >= 65536 then
		error("Colour out of range",2)
	end
	num = 2^math.floor(math.log(num)/math.log(2))
	Emulator.state.bg = num
end
function api.term.isColor()
	return true
end
function api.term.setCursorBlink(...)
	local bool = ...
	if type(bool) ~= "boolean" or select("#",...) ~= 1 then error("Expected boolean",2) end
	Emulator.state.blink = bool
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
				Screen.backgroundColourB[y][x] = Emulator.state.bg
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
		if Emulator.state.peripherals[sSide] then
			error("Peripheral already attached to " .. sSide,2)
		end
		Emulator.state.peripherals[sSide] = peripheral.base[sType](sSide)
		if Emulator.state.peripherals[sSide] ~= nil then
			local methods = Emulator.state.peripherals[sSide].getMethods()
			Emulator.state.peripherals[sSide].cache = {}
			for i = 1,#methods do
				Emulator.state.peripherals[sSide].cache[methods[i]] = true
			end
			local ccliteMethods = Emulator.state.peripherals[sSide].ccliteGetMethods()
			Emulator.state.peripherals[sSide].ccliteCache = {}
			for i = 1,#ccliteMethods do
				Emulator.state.peripherals[sSide].ccliteCache[ccliteMethods[i]] = true
			end
			table.insert(Emulator.eventQueue, {"peripheral",sSide})
		else
			error("No peripheral added",2)
		end
	end
	function api.cclite.peripheralDetach(sSide)
		if type(sSide) ~= "string" then error("Expected string",2) end
		if not Emulator.state.peripherals[sSide] then
			error("No peripheral attached to " .. sSide,2)
		end
		Emulator.state.peripherals[sSide] = nil
		table.insert(Emulator.eventQueue, {"peripheral_detach",sSide})
	end
	function api.cclite.getMethods(sSide)
		if type(sSide) ~= "string" then error("Expected string",2) end
		if Emulator.state.peripherals[sSide] then return Emulator.state.peripherals[sSide].ccliteGetMethods() end
		return
	end
	function api.cclite.call(sSide, sMethod, ...)
		if type(sSide) ~= "string" then error("Expected string",2) end
		if type(sMethod) ~= "string" then error("Expected string, string",2) end
		if not Emulator.state.peripherals[sSide] then error("No peripheral attached",2) end
		return Emulator.state.peripherals[sSide].ccliteCall(sMethod, ...)
	end
	function api.cclite.message(sMessage)
		if type(sMessage) ~= "string" then error("Expected string",2) end
		Screen:message(sMessage)
	end
end

local function string_trim(s)
	local from = s:match"^%s*()"
	return from > #s and "" or s:match(".*%S", from)
end

if _conf.enableAPI_http then
	api.http = {}
	function api.http.request(sUrl, sParams)
		if type(sUrl) ~= "string" then
			error("String expected" .. (sUrl == nil and ", got nil" or ""),2)
		end
		local goodUrl = string_trim(sUrl)
		if goodUrl:sub(1,4) == "ftp:" or goodUrl:sub(1,5) == "file:" or goodUrl:sub(1,7) == "mailto:" then
			error("Not an HTTP URL",2)
		end
		if goodUrl:sub(1,5) ~= "http:" and goodUrl:sub(1,6) ~= "https:" then
			error("Invalid URL",2)
		end
		local http = HttpRequest.new()
		local method = sParams and "POST" or "GET"

		http.open(method, goodUrl, true)

		if method == "POST" then
			http.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
			http.setRequestHeader("Content-Length", sParams:len())
		end

		http.onReadyStateChange = function()
			if http.status == 200 then
				local handle = HTTPHandle(lines(http.responseText), http.status)
				table.insert(Emulator.eventQueue, {"http_success", sUrl, handle})
			else
				table.insert(Emulator.eventQueue, {"http_failure", sUrl})
			end
		end

		http.send(sParams)
	end
end

api.os = {}
function api.os.clock()
	return tonumber(string.format("%0.2f",math.floor(love.timer.getTime()*20)/20 - Emulator.state.startTime))
end
function api.os.time()
	return math.floor((os.clock()*0.02)%24*1000)/1000
end
function api.os.day()
	return math.floor(os.clock()/1200)
end
function api.os.setComputerLabel(label)
	if type(label) ~= "string" and type(label) ~= "nil" then error("Expected string or nil",2) end
	Emulator.state.label = label
end
function api.os.getComputerLabel()
	return Emulator.state.label
end
function api.os.queueEvent(event, ...)
	if type(event) ~= "string" then error("Expected string",2) end
	table.insert(Emulator.eventQueue, {event, ...})
end
function api.os.startTimer(...)
	local nTimeout = ...
	if type(nTimeout) ~= "number" or select("#",...) ~= 1 then error("Expected number",2) end
	nTimeout = math.ceil(nTimeout*20)/20
	if nTimeout < 0.05 then nTimeout = 0.05 end
	Emulator.actions.lastTimer = Emulator.actions.lastTimer + 1
	Emulator.actions.timers[Emulator.actions.lastTimer] = math.floor(love.timer.getTime()*20)/20 + nTimeout
	return Emulator.actions.lastTimer
end
function api.os.setAlarm(...)
	local nTime = ...
	if type(nTime) ~= "number" or select("#",...) ~= 1 then error("Expected number",2) end
	if nTime < 0 or nTime > 24 then
		error("Number out of range: " .. tostring(nTime))
	end
	local alarm = {
		time = nTime,
		day = api.os.day() + (nTime < api.os.time() and 1 or 0)
	}
	Emulator.actions.lastAlarm = Emulator.actions.lastAlarm + 1
	Emulator.actions.alarms[Emulator.actions.lastAlarm] = alarm
	return Emulator.actions.lastAlarm
end
function api.os.cancelTimer(id)
	if type(id) ~= "number" then error("Expected number",2) end
	Emulator.actions.timers[id] = nil
end
function api.os.cancelAlarm(id)
	if type(id) ~= "number" then error("Expected number",2) end
	Emulator.actions.alarms[id] = nil
end
function api.os.shutdown()
	Emulator:stop(false)
end
function api.os.reboot()
	Emulator:stop(true) -- Reboots on next update/tick
end

api.peripheral = {}
function api.peripheral.isPresent(sSide)
	if type(sSide) ~= "string" then error("Expected string",2) end
	return Emulator.state.peripherals[sSide] ~= nil
end
function api.peripheral.getType(sSide)
	if type(sSide) ~= "string" then error("Expected string",2) end
	if Emulator.state.peripherals[sSide] then return peripheral.types[Emulator.state.peripherals[sSide].type] end
	return
end
function api.peripheral.getMethods(sSide)
	if type(sSide) ~= "string" then error("Expected string",2) end
	if Emulator.state.peripherals[sSide] then return Emulator.state.peripherals[sSide].getMethods() end
	return
end
function api.peripheral.call(sSide, sMethod, ...)
	if type(sSide) ~= "string" or type(sMethod) ~= "string" then error("Expected string, string",2) end
	if not Emulator.state.peripherals[sSide] then error("No peripheral attached",2) end
	if not Emulator.state.peripherals[sSide].cache[sMethod] then
		error("No such method " .. sMethod,2)
	end
	return Emulator.state.peripherals[sSide].call(sMethod, ...)
end

api.fs = {}
function api.fs.combine(...)
	local basePath, localPath = ...
	if type(basePath) ~= "string" or type(localPath) ~= "string" or select("#",...) ~= 2 then
		error("Expected string, string",2)
	end
	local path = ("/" .. basePath .. "/" .. localPath):gsub("\\", "/")
	
	local cleanName = ""
	for i = 1,#path do
		local c = path:sub(i,i):byte()
		if c >= 32 and c ~= 34 and c ~= 42 and c ~= 58 and c ~= 60 and c ~= 62 and c ~= 63 and c ~= 124 then
			cleanName = cleanName .. string.char(c)
		end
	end
	
	local tPath = {}
	for part in cleanName:gmatch("[^/]+") do
   		if part ~= "" and part ~= "." then
   			if part == ".." and #tPath > 0 and tPath[1] ~= ".." then
   				table.remove(tPath)
   			else
   				table.insert(tPath, part:sub(1,255))
   			end
   		end
	end
	return table.concat(tPath, "/")
end

local function contains(pathA, pathB)
	pathA = api.fs.combine(pathA,"")
	pathB = api.fs.combine(pathB,"")

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
	if spec:sub(1,1) == "/" then spec = spec:sub(2) end
	if spec:sub(-1,-1) == "/" then spec = spec:sub(1,-2) end
	local segment = spec:match('([^/]*)'):gsub('/', '')
	local pattern = '^' .. segment:gsub('[*]', '.+'):gsub('?', '.') .. '$'

	if api.fs.isDir(path) then
		for _, file in ipairs(api.fs.list(path)) do
			if file:match(pattern) then
				local f = api.fs.combine(path, file)

				if api.fs.isDir(f) then
					recurse_spec(results, f, spec:sub(#segment + 2))
				elseif spec == segment then
					table.insert(results, f)
				end
			end
		end
	end
end

-- Such a useless function
function api.fs.getDir(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	return api.fs.combine(path, "..")
end
function api.fs.find(...)
	local spec = ...
	if type(spec) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	local results = {}
	recurse_spec(results, '', spec)
	return results
end
function api.fs.open(...)
	local path, mode = ...
	if type(path) ~= "string" or type(mode) ~= "string" or select("#",...) ~= 2 then
		error("Expected string, string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = vfs.normalize(path)
	if mode == "r" then
		return FileReadHandle(path)
	elseif mode == "rb" then
		return FileBinaryReadHandle(path)
	elseif mode == "w" or mode == "a" then
		return FileWriteHandle(path,mode == "a")
	elseif mode == "wb" or mode == "ab" then
		return FileBinaryWriteHandle(path,mode == "ab")
	else
		error("Unsupported mode",2)
	end
end
function api.fs.list(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = vfs.normalize(path)
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
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then return false end
	path = vfs.normalize(path)
	return vfs.exists(path)
end
function api.fs.isDir(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then return false end
	path = vfs.normalize(path)
	return vfs.isDirectory(path)
end
function api.fs.isReadOnly(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	path = vfs.normalize(path)
	return path == "/rom" or path:sub(1, 5) == "/rom/"
end
function api.fs.getName(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	path = vfs.normalize(path)
	if path == "/" then
		return "root"
	end
	local fpath, name, ext = path:match("(.-)([^\\/]-%.?([^%.\\/]*))$")
	return name
end
function api.fs.getDrive(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = vfs.normalize(path)
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
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = vfs.normalize(path)
	if vfs.exists(path) ~= true then
		error("No such file",2)
	end

	if vfs.isDirectory(path) then
		return 0
	end
	
	local size = vfs.getSize(path)
	return math.ceil(size/512)*512
end

function api.fs.getFreeSpace(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = vfs.normalize(path)
	if path == "/rom" or path:sub(1, 5) == "/rom/" then
		return 0
	end
	return math.huge
end

function api.fs.makeDir(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = vfs.normalize(path)
	if path == "/rom" or path:sub(1, 5) == "/rom/" then
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
	   		local pObject =  sFolder.."/"..sObject

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
	   		local pObject =  sFolder.."/"..sObject
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
	local testpath = api.fs.combine("data/", fromPath)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	local testpath = api.fs.combine("data/", toPath)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	fromPath = vfs.normalize(fromPath)
	toPath = vfs.normalize(toPath)
	if fromPath == "/rom" or fromPath:sub(1, 5) == "/rom/" or 
		toPath == "/rom" or toPath:sub(1, 5) == "/rom/" then
		error("Access Denied",2)
	end
	if vfs.exists(fromPath) ~= true then
		error("No such file",2)
	end
	if vfs.exists(toPath) == true then
		error("File exists",2)
	end
	if contains(fromPath, toPath) then
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
	local testpath = api.fs.combine("data/", fromPath)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	local testpath = api.fs.combine("data/", toPath)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	fromPath = vfs.normalize(fromPath)
	toPath = vfs.normalize(toPath)
	if toPath == "/rom" or toPath:sub(1, 5) == "/rom/" then
		error("Access Denied",2)
	end
	if vfs.exists(fromPath) ~= true then
		error("No such file",2)
	end
	if vfs.exists(toPath) == true then
		error("File exists",2)
	end
	if contains(fromPath, toPath) then
		error("Can't copy a directory inside itself",2)
	end
	copytree(fromPath, toPath)
end

function api.fs.delete(...)
	local path = ...
	if type(path) ~= "string" or select("#",...) ~= 1 then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = vfs.normalize(path)
	if path == "/rom" or path:sub(1, 5) == "/rom/" or vfs.isMountPath(path) then
		error("Access Denied",2)
	end
	deltree(path)
end

api.redstone = {}
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
end
function api.redstone.getOutput(side)
	if type(side) ~= "string" then
		error("Expected string",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return false
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
	end
end
function api.redstone.getAnalogOutput(side)
	if type(side) ~= "string" then
		error("Expected string",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return 0
end
function api.redstone.getBundledInput(side)
	if type(side) ~= "string" then
		error("Expected string",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return 0
end
function api.redstone.getBundledOutput(sude)
	if type(side) ~= "string" then
		error("Expected string",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return 0
end
function api.redstone.setBundledOutput(side, colors)
	if type(side) ~= "string" or type(colors) ~= "number" then
		error("Expected string, number",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
end
function api.redstone.testBundledInput(side, color)
	if type(side) ~= "string" or type(color) ~= "number" then
		error("Expected string, number",2)
	elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
		error("Invalid side.",2)
	end
	return color == 0
end

api.bit = {}
function api.bit.norm(val)
	while val < 0 do val = val + 4294967296 end
	return val
end
function api.bit.blshift(n, bits)
	if (type(n) ~= "number" and type(n) ~= "nil") or (type(bits) ~= "number" and type(bits) ~= "nil") then
		error("number expected",2)
	elseif n == nil or bits == nil then
		error("too few arguments",2)
	end
	return api.bit.norm(bit.lshift(n, bits))
end
function api.bit.brshift(n, bits)
	if (type(n) ~= "number" and type(n) ~= "nil") or (type(bits) ~= "number" and type(bits) ~= "nil") then
		error("number expected",2)
	elseif n == nil or bits == nil then
		error("too few arguments",2)
	end
	return api.bit.norm(bit.arshift(n, bits))
end
function api.bit.blogic_rshift(n, bits)
	if (type(n) ~= "number" and type(n) ~= "nil") or (type(bits) ~= "number" and type(bits) ~= "nil") then
		error("number expected",2)
	elseif n == nil or bits == nil then
		error("too few arguments",2)
	end
	return api.bit.norm(bit.rshift(n, bits))
end
function api.bit.bxor(m, n)
	if (type(m) ~= "number" and type(m) ~= "nil") or (type(n) ~= "number" and type(n) ~= "nil") then
		error("number expected",2)
	elseif m == nil or n == nil then
		error("too few arguments",2)
	end
	return api.bit.norm(bit.bxor(m, n))
end
function api.bit.bor(m, n)
	if (type(m) ~= "number" and type(m) ~= "nil") or (type(n) ~= "number" and type(n) ~= "nil") then
		error("number expected",2)
	elseif m == nil or n == nil then
		error("too few arguments",2)
	end
	return api.bit.norm(bit.bor(m, n))
end
function api.bit.band(m, n)
	if (type(m) ~= "number" and type(m) ~= "nil") or (type(n) ~= "number" and type(n) ~= "nil") then
		error("number expected",2)
	elseif m == nil or n == nil then
		error("too few arguments",2)
	end
	return api.bit.norm(bit.band(m, n))
end
function api.bit.bnot(n)
	if type(n) ~= "number" and type(n) ~= "nil" then
		error("number expected",2)
	elseif n == nil then
		error("too few arguments",2)
	end
	return api.bit.norm(bit.bnot(n))
end

function api.init() -- Called after this file is loaded! Important. Else api.x is not defined
	api.env = {
		_VERSION = "Luaj-jse 2.0.3",
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
		error = api.error,
		ipairs = ipairs,
		pairs = pairs,
		pcall = pcall,
		xpcall = xpcall,
		loadstring = api.loadstring,
		math = tablecopy(math),
		string = tablecopy(string),
		table = tablecopy(table),
		coroutine = tablecopy(coroutine),

		-- CC apis (BIOS completes api.)
		term = {
			clear = api.term.clear,
			clearLine = api.term.clearLine,
			getSize = api.term.getSize,
			getCursorPos = api.term.getCursorPos,
			setCursorPos = api.term.setCursorPos,
			setTextColor = api.term.setTextColor,
			setTextColour = api.term.setTextColor,
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
			getAnalogueInput = api.redstone.getAnalogInput,
			getAnalogueOutput = api.redstone.getAnalogOutput,
			setOutput = api.redstone.setOutput,
			setBundledOutput = api.redstone.setBundledOutput,
			setAnalogOutput = api.redstone.setAnalogOutput,
			setAnalogueOutput = api.redstone.setAnalogOutput,
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
