api = {}
function api.init(Computer,color,id)
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
	-- TODO Make more efficient, use love.filesystem.lines
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
		if not Computer.vfs.exists(path) then
			return nil
		end
		local contents = {}
		for line in Computer.vfs.lines(path) do
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
		if not Computer.vfs.exists(path) then
			return nil
		end
		local closed = false
		local File = Computer.vfs.newFile(path, "r")
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
		if append and not Computer.vfs.exists(path) then
			return nil
		end
		local closed = false
		local File = Computer.vfs.newFile(path, append and "a" or "w")
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
		local File = Computer.vfs.newFile(path, append and "a" or "w")
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

	local tmpapi = {}
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
	function tmpapi.tostring(...)
		if select("#",...) == 0 then error("bad argument #1: value expected",2) end
		local something = ...
		if something == nil then return "nil" end
		return _tostring_DB[something] or tostring(something)
	end
	function tmpapi.tonumber(...)
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
	function tmpapi.getfenv(level)
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
			return tmpapi.env
		end
		return env
	end
	function tmpapi.error(str,level)
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
	function tmpapi.loadstring(str, source)
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
		setfenv(f, tmpapi.env)
		return f, err
	end

	tmpapi.term = {}
	function tmpapi.term.clear()
		for y = 1, _conf.terminal_height do
			for x = 1, _conf.terminal_width do
				Computer.textB[y][x] = " "
				Computer.backgroundColourB[y][x] = Computer.state.bg
				Computer.textColourB[y][x] = 1
			end
		end
		Screen.dirty = true
	end
	function tmpapi.term.clearLine()
		if Computer.state.cursorY > _conf.terminal_height or Computer.state.cursorY < 1 then
			return
		end
		for x = 1, _conf.terminal_width do
			Computer.textB[Computer.state.cursorY][x] = " "
			Computer.backgroundColourB[Computer.state.cursorY][x] = Computer.state.bg
			Computer.textColourB[Computer.state.cursorY][x] = 1
		end
		Screen.dirty = true
	end
	function tmpapi.term.getSize()
		return _conf.terminal_width, _conf.terminal_height
	end
	function tmpapi.term.getCursorPos()
		return Computer.state.cursorX, Computer.state.cursorY
	end
	function tmpapi.term.setCursorPos(...)
		local x, y = ...
		if type(x) ~= "number" or type(y) ~= "number" or select("#",...) ~= 2 then error("Expected number, number",2) end
		Computer.state.cursorX = math.floor(x)
		Computer.state.cursorY = math.floor(y)
		Screen.dirty = true
	end
	function tmpapi.term.write(text)
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
				Computer.textB[Computer.state.cursorY][Computer.state.cursorX + i - 1] = char
				Computer.textColourB[Computer.state.cursorY][Computer.state.cursorX + i - 1] = Computer.state.fg
				Computer.backgroundColourB[Computer.state.cursorY][Computer.state.cursorX + i - 1] = Computer.state.bg
			end
		end
		Computer.state.cursorX = Computer.state.cursorX + #text
		Screen.dirty = true
	end
	function tmpapi.term.setTextColor(...)
		local num = ...
		if type(num) ~= "number" or select("#",...) ~= 1 then error("Expected number",2) end
		if num < 1 or num >= 65536 then
			error("Colour out of range",2)
		end
		num = 2^math.floor(math.log(num)/math.log(2))
		if num ~= 1 and num ~= 32768 and not color then
			error("Colour not supported",2)
		end
		Computer.state.fg = num
		Screen.dirty = true
	end
	function tmpapi.term.setBackgroundColor(...)
		local num = ...
		if type(num) ~= "number" or select("#",...) ~= 1 then error("Expected number",2) end
		if num < 1 or num >= 65536 then
			error("Colour out of range",2)
		end
		num = 2^math.floor(math.log(num)/math.log(2))
		if num ~= 1 and num ~= 32768 and not color then
			error("Colour not supported",2)
		end
		Computer.state.bg = num
	end
	function tmpapi.term.isColor()
		return color
	end
	function tmpapi.term.setCursorBlink(bool)
		if type(bool) ~= "boolean" then error("Expected boolean",2) end
		Computer.state.blink = bool
		Screen.dirty = true
	end
	function tmpapi.term.scroll(...)
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
					textBuffer[y - n][x] = Computer.textB[y][x]
					backgroundColourBuffer[y - n][x] = Computer.backgroundColourB[y][x]
					textColourBuffer[y - n][x] = Computer.textColourB[y][x]
				end
			end
		end
		for y = 1, _conf.terminal_height do
			if textBuffer[y] ~= nil then
				for x = 1, _conf.terminal_width do
					Computer.textB[y][x] = textBuffer[y][x]
					Computer.backgroundColourB[y][x] = backgroundColourBuffer[y][x]
					Computer.textColourB[y][x] = textColourBuffer[y][x]
				end
			else
				for x = 1, _conf.terminal_width do
					Computer.textB[y][x] = " "
					Computer.backgroundColourB[y][x] = Computer.state.bg
					Computer.textColourB[y][x] = 1 -- Don't need to bother setting text color
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

	tmpapi.cclite = {}
	if _conf.enableAPI_cclite then
		function tmpapi.cclite.peripheralAttach(sSide, sType)
			if type(sSide) ~= "string" or type(sType) ~= "string" then
				error("Expected string, string",2)
			end
			if not peripheral.base[sType] then
				error("No virtual peripheral of type " .. sType,2)
			end
			if Computer.state.peripherals[sSide] then
				error("Peripheral already attached to " .. sSide,2)
			end
			Computer.state.peripherals[sSide] = peripheral.base[sType](Computer,sSide)
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
		function tmpapi.cclite.peripheralDetach(sSide)
			if type(sSide) ~= "string" then error("Expected string",2) end
			if not Computer.state.peripherals[sSide] then
				error("No peripheral attached to " .. sSide,2)
			end
			if Computer.state.peripherals[sSide].detach ~= nil then
				Computer.state.peripherals[sSide].detach()
			end
			Computer.state.peripherals[sSide] = nil
			table.insert(Computer.eventQueue, {"peripheral_detach",sSide})
		end
		function tmpapi.cclite.getMethods(sSide)
			if type(sSide) ~= "string" then error("Expected string",2) end
			if Computer.state.peripherals[sSide] then return Computer.state.peripherals[sSide].ccliteGetMethods() end
			return
		end
		function tmpapi.cclite.call(sSide, sMethod, ...)
			if type(sSide) ~= "string" then error("Expected string",2) end
			if type(sMethod) ~= "string" then error("Expected string, string",2) end
			if not Computer.state.peripherals[sSide] then error("No peripheral attached",2) end
			return Computer.state.peripherals[sSide].ccliteCall(sMethod, ...)
		end
		function tmpapi.cclite.message(sMessage)
			if type(sMessage) ~= "string" then error("Expected string",2) end
			Screen:message(sMessage)
		end
	end

	local function string_trim(s)
		local from = s:match"^%s*()"
		return from > #s and "" or s:match(".*%S", from)
	end
	
	if _conf.enableAPI_http then
		tmpapi.http = {}
		function tmpapi.http.request(sUrl, sParams)
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
					table.insert(Computer.eventQueue, {"http_success", sUrl, handle})
				else
					table.insert(Computer.eventQueue, {"http_failure", sUrl})
				end
			end

			http.send(sParams)
		end
	end

	tmpapi.os = {}
	function tmpapi.os.clock()
		return tonumber(string.format("%0.2f",math.floor(love.timer.getTime()*20)/20 - Computer.state.startTime))
	end
	function tmpapi.os.time()
		return math.floor((os.clock()*0.02)%24*1000)/1000
	end
	function tmpapi.os.day()
		return math.floor(os.clock()/1200)
	end
	function tmpapi.os.getComputerID()
		return id
	end
	function tmpapi.os.setComputerLabel(label)
		if type(label) ~= "string" and type(label) ~= "nil" then error("Expected string or nil",2) end
		Computer.state.label = label
	end
	function tmpapi.os.getComputerLabel()
		return Computer.state.label
	end
	function tmpapi.os.queueEvent(event, ...)
		if type(event) ~= "string" then error("Expected string",2) end
		table.insert(Computer.eventQueue, {event, ...})
	end
	function tmpapi.os.startTimer(...)
		local nTimeout = ...
		if type(nTimeout) ~= "number" or select("#",...) ~= 1 then error("Expected number",2) end
		nTimeout = math.ceil(nTimeout*20)/20
		if nTimeout < 0.05 then nTimeout = 0.05 end
		Computer.actions.lastTimer = Computer.actions.lastTimer + 1
		Computer.actions.timers[Computer.actions.lastTimer] = math.floor(love.timer.getTime()*20)/20 + nTimeout
		return Computer.actions.lastTimer
	end
	function tmpapi.os.setAlarm(...)
		local nTime = ...
		if type(nTime) ~= "number" or select("#",...) ~= 1 then error("Expected number",2) end
		if nTime < 0 or nTime > 24 then
			error("Number out of range: " .. tostring(nTime))
		end
		local alarm = {
			time = nTime,
			day = tmpapi.os.day() + (nTime < tmpapi.os.time() and 1 or 0)
		}
		Computer.actions.lastAlarm = Computer.actions.lastAlarm + 1
		Computer.actions.alarms[Computer.actions.lastAlarm] = alarm
		return Computer.actions.lastAlarm
	end
	function tmpapi.os.cancelTimer(id)
		if type(id) ~= "number" then error("Expected number",2) end
		Computer.actions.timers[id] = nil
	end
	function tmpapi.os.cancelAlarm(id)
		if type(id) ~= "number" then error("Expected number",2) end
		Computer.actions.alarms[id] = nil
	end
	function tmpapi.os.shutdown()
		Computer:stop(false)
	end
	function tmpapi.os.reboot()
		Computer:stop(true) -- Reboots on next update/tick
	end

	tmpapi.peripheral = {}
	function tmpapi.peripheral.isPresent(sSide)
		if type(sSide) ~= "string" then error("Expected string",2) end
		return Computer.state.peripherals[sSide] ~= nil
	end
	function tmpapi.peripheral.getType(sSide)
		if type(sSide) ~= "string" then error("Expected string",2) end
		if Computer.state.peripherals[sSide] then return peripheral.types[Computer.state.peripherals[sSide].type] end
		return
	end
	function tmpapi.peripheral.getMethods(sSide)
		if type(sSide) ~= "string" then error("Expected string",2) end
		if Computer.state.peripherals[sSide] then return Computer.state.peripherals[sSide].getMethods() end
		return
	end
	function tmpapi.peripheral.call(sSide, sMethod, ...)
		if type(sSide) ~= "string" or type(sMethod) ~= "string" then error("Expected string, string",2) end
		if not Computer.state.peripherals[sSide] then error("No peripheral attached",2) end
		if not Computer.state.peripherals[sSide].cache[sMethod] then
			error("No such method " .. sMethod,2)
		end
		return Computer.state.peripherals[sSide].call(sMethod, ...)
	end

	tmpapi.fs = {}
	function tmpapi.fs.combine(...)
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
		pathA = tmpapi.fs.combine(pathA,"")
		pathB = tmpapi.fs.combine(pathB,"")

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
		local pattern = '^' .. segment:gsub('[*]', '.+'):gsub('?', '.') .. '$'

		if tmpapi.fs.isDir(path) then
			for _, file in ipairs(tmpapi.fs.list(path)) do
				if file:match(pattern) then
					local f = tmpapi.fs.combine(path, file)

					if tmpapi.fs.isDir(f) then
						recurse_spec(results, f, spec:sub(#segment + 2))
					elseif spec == segment then
						table.insert(results, f)
					end
				end
			end
		end
	end

	-- Such a useless function
	function tmpapi.fs.getDir(...)
		local path = ...
		if type(path) ~= "string" or select("#",...) ~= 1 then
			error("Expected string",2)
		end
		return tmpapi.fs.combine(path, "..")
	end
	function tmpapi.fs.find(...)
		local spec = ...
		if type(spec) ~= "string" or select("#",...) ~= 1 then
			error("Expected string",2)
		end
		local results = {}
		recurse_spec(results, '', spec)
		return results
	end
	function tmpapi.fs.open(...)
		local path, mode = ...
		if type(path) ~= "string" or type(mode) ~= "string" or select("#",...) ~= 2 then
			error("Expected string, string",2)
		end
		local testpath = tmpapi.fs.combine("data/", path)
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
	function tmpapi.fs.list(...)
		local path = ...
		if type(path) ~= "string" or select("#",...) ~= 1 then
			error("Expected string",2)
		end
		local testpath = tmpapi.fs.combine("data/", path)
		if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
		path = vfs.normalize(path)
		if not Computer.vfs.exists(path) or not Computer.vfs.isDirectory(path) then
			error("Not a directory",2)
		end
		return Computer.vfs.getDirectoryItems(path)
	end
	function tmpapi.fs.exists(...)
		local path = ...
		if type(path) ~= "string" or select("#",...) ~= 1 then
			error("Expected string",2)
		end
		local testpath = tmpapi.fs.combine("data/", path)
		if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then return false end
		path = vfs.normalize(path)
		return Computer.vfs.exists(path)
	end
	function tmpapi.fs.isDir(...)
		local path = ...
		if type(path) ~= "string" or select("#",...) ~= 1 then
			error("Expected string",2)
		end
		local testpath = tmpapi.fs.combine("data/", path)
		if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then return false end
		path = vfs.normalize(path)
		return Computer.vfs.isDirectory(path)
	end
	function tmpapi.fs.isReadOnly(...)
		local path = ...
		if type(path) ~= "string" or select("#",...) ~= 1 then
			error("Expected string",2)
		end
		path = vfs.normalize(path)
		return path == "/rom" or path:sub(1, 5) == "/rom/"
	end
	function tmpapi.fs.getName(...)
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
	function tmpapi.fs.getDrive(...)
		local path = ...
		if type(path) ~= "string" or select("#",...) ~= 1 then
			error("Expected string",2)
		end
		local testpath = tmpapi.fs.combine("data/", path)
		if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
		path = vfs.normalize(path)
		if not Computer.vfs.exists(path) then
			return
		end
		local mountEntry = Computer.vfs.getMountContainer(path)
		return mountEntry[4]
	end
	function tmpapi.fs.getSize(...)
		local path = ...
		if type(path) ~= "string" or select("#",...) ~= 1 then
			error("Expected string",2)
		end
		local testpath = tmpapi.fs.combine("data/", path)
		if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
		path = vfs.normalize(path)
		if Computer.vfs.exists(path) ~= true then
			error("No such file",2)
		end

		if Computer.vfs.isDirectory(path) then
			return 0
		end
		
		local size = Computer.vfs.getSize(path)
		return math.ceil(size/512)*512
	end

	function tmpapi.fs.getFreeSpace(...)
		local path = ...
		if type(path) ~= "string" or select("#",...) ~= 1 then
			error("Expected string",2)
		end
		local testpath = tmpapi.fs.combine("data/", path)
		if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
		path = vfs.normalize(path)
		if path == "/rom" or path:sub(1, 5) == "/rom/" then
			return 0
		end
		return math.huge
	end

	function tmpapi.fs.makeDir(...)
		local path = ...
		if type(path) ~= "string" or select("#",...) ~= 1 then
			error("Expected string",2)
		end
		local testpath = tmpapi.fs.combine("data/", path)
		if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
		path = vfs.normalize(path)
		if path == "/rom" or path:sub(1, 5) == "/rom/" then
			error("Access Denied",2)
		end
		if Computer.vfs.exists(path) and not Computer.vfs.isDirectory(path) then
			error("File exists",2)
		end
		Computer.vfs.createDirectory(path)
	end

	local function deltree(sFolder)
		local tObjects = Computer.vfs.getDirectoryItems(sFolder)

		if tObjects then
			for _, sObject in pairs(tObjects) do
				local pObject =  sFolder.."/"..sObject

				if Computer.vfs.isDirectory(pObject) then
					deltree(pObject)
				end
				Computer.vfs.remove(pObject)
			end
		end
		return Computer.vfs.remove(sFolder)
	end

	local function copytree(sFolder, sToFolder)
		if not Computer.vfs.isDirectory(sFolder) then
			Computer.vfs.write(sToFolder, Computer.vfs.read(sFolder))
			return
		end
		Computer.vfs.createDirectory(sToFolder)
		local tObjects = Computer.vfs.getDirectoryItems(sFolder)

		if tObjects then
			for _, sObject in pairs(tObjects) do
				local pObject =  sFolder.."/"..sObject
				local pToObject = sToFolder.."/"..sObject

				if Computer.vfs.isDirectory(pObject) then
					Computer.vfs.createDirectory(pToObject)
					copytree(pObject,pToObject)
				else
					Computer.vfs.write(pToObject, Computer.vfs.read(pObject))
				end
			end
		end
	end

	function tmpapi.fs.move(...)
		local fromPath, toPath = ...
		if type(fromPath) ~= "string" or type(toPath) ~= "string" or select("#",...) ~= 2 then
			error("Expected string, string",2)
		end
		local testpath = tmpapi.fs.combine("data/", fromPath)
		if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
		local testpath = tmpapi.fs.combine("data/", toPath)
		if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
		fromPath = vfs.normalize(fromPath)
		toPath = vfs.normalize(toPath)
		if fromPath == "/rom" or fromPath:sub(1, 5) == "/rom/" or 
			toPath == "/rom" or toPath:sub(1, 5) == "/rom/" then
			error("Access Denied",2)
		end
		if Computer.vfs.exists(fromPath) ~= true then
			error("No such file",2)
		end
		if Computer.vfs.exists(toPath) == true then
			error("File exists",2)
		end
		if contains(fromPath, toPath) then
			error("Can't move a directory inside itself",2)
		end
		copytree(fromPath, toPath)
		deltree(fromPath)
	end

	function tmpapi.fs.copy(...)
		local fromPath, toPath = ...
		if type(fromPath) ~= "string" or type(toPath) ~= "string" or select("#",...) ~= 2 then
			error("Expected string, string",2)
		end
		local testpath = tmpapi.fs.combine("data/", fromPath)
		if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
		local testpath = tmpapi.fs.combine("data/", toPath)
		if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
		fromPath = vfs.normalize(fromPath)
		toPath = vfs.normalize(toPath)
		if toPath == "/rom" or toPath:sub(1, 5) == "/rom/" then
			error("Access Denied",2)
		end
		if Computer.vfs.exists(fromPath) ~= true then
			error("No such file",2)
		end
		if Computer.vfs.exists(toPath) == true then
			error("File exists",2)
		end
		if contains(fromPath, toPath) then
			error("Can't copy a directory inside itself",2)
		end
		copytree(fromPath, toPath)
	end

	function tmpapi.fs.delete(...)
		local path = ...
		if type(path) ~= "string" or select("#",...) ~= 1 then
			error("Expected string",2)
		end
		local testpath = tmpapi.fs.combine("data/", path)
		if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
		path = vfs.normalize(path)
		if path == "/rom" or path:sub(1, 5) == "/rom/" or Computer.vfs.isMountPath(path) then
			error("Access Denied",2)
		end
		deltree(path)
	end

	tmpapi.redstone = {}
	function tmpapi.redstone.getSides()
		return {"top","bottom","left","right","front","back"}
	end
	function tmpapi.redstone.getInput(side)
		if type(side) ~= "string" then
			error("Expected string",2)
		elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
			error("Invalid side.",2)
		end
		return false
	end
	function tmpapi.redstone.setOutput(side, value)
		if type(side) ~= "string" or type(value) ~= "boolean" then
			error("Expected string, boolean",2)
		elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
			error("Invalid side.",2)
		end
	end
	function tmpapi.redstone.getOutput(side)
		if type(side) ~= "string" then
			error("Expected string",2)
		elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
			error("Invalid side.",2)
		end
		return false
	end
	function tmpapi.redstone.getAnalogInput(side)
		if type(side) ~= "string" then
			error("Expected string",2)
		elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
			error("Invalid side.",2)
		end
		return 0
	end
	function tmpapi.redstone.setAnalogOutput(side, strength)
		if type(side) ~= "string" or type(strength) ~= "number" then
			error("Expected string, number",2)
		elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
			error("Invalid side.",2)
		end
	end
	function tmpapi.redstone.getAnalogOutput(side)
		if type(side) ~= "string" then
			error("Expected string",2)
		elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
			error("Invalid side.",2)
		end
		return 0
	end
	function tmpapi.redstone.getBundledInput(side)
		if type(side) ~= "string" then
			error("Expected string",2)
		elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
			error("Invalid side.",2)
		end
		return 0
	end
	function tmpapi.redstone.getBundledOutput(sude)
		if type(side) ~= "string" then
			error("Expected string",2)
		elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
			error("Invalid side.",2)
		end
		return 0
	end
	function tmpapi.redstone.setBundledOutput(side, colors)
		if type(side) ~= "string" or type(colors) ~= "number" then
			error("Expected string, number",2)
		elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
			error("Invalid side.",2)
		end
	end
	function tmpapi.redstone.testBundledInput(side, color)
		if type(side) ~= "string" or type(color) ~= "number" then
			error("Expected string, number",2)
		elseif side~="top" and side~="bottom" and side~="left" and side~="right" and side~="front" and side~="back" then
			error("Invalid side.",2)
		end
		return color == 0
	end

	tmpapi.bit = {}
	function tmpapi.bit.norm(val)
		while val < 0 do val = val + 4294967296 end
		return val
	end
	function tmpapi.bit.blshift(n, bits)
		if (type(n) ~= "number" and type(n) ~= "nil") or (type(bits) ~= "number" and type(bits) ~= "nil") then
			error("number expected",2)
		elseif n == nil or bits == nil then
			error("too few arguments",2)
		end
		return tmpapi.bit.norm(bit.lshift(n, bits))
	end
	function tmpapi.bit.brshift(n, bits)
		if (type(n) ~= "number" and type(n) ~= "nil") or (type(bits) ~= "number" and type(bits) ~= "nil") then
			error("number expected",2)
		elseif n == nil or bits == nil then
			error("too few arguments",2)
		end
		return tmpapi.bit.norm(bit.arshift(n, bits))
	end
	function tmpapi.bit.blogic_rshift(n, bits)
		if (type(n) ~= "number" and type(n) ~= "nil") or (type(bits) ~= "number" and type(bits) ~= "nil") then
			error("number expected",2)
		elseif n == nil or bits == nil then
			error("too few arguments",2)
		end
		return tmpapi.bit.norm(bit.rshift(n, bits))
	end
	function tmpapi.bit.bxor(m, n)
		if (type(m) ~= "number" and type(m) ~= "nil") or (type(n) ~= "number" and type(n) ~= "nil") then
			error("number expected",2)
		elseif m == nil or n == nil then
			error("too few arguments",2)
		end
		return tmpapi.bit.norm(bit.bxor(m, n))
	end
	function tmpapi.bit.bor(m, n)
		if (type(m) ~= "number" and type(m) ~= "nil") or (type(n) ~= "number" and type(n) ~= "nil") then
			error("number expected",2)
		elseif m == nil or n == nil then
			error("too few arguments",2)
		end
		return tmpapi.bit.norm(bit.bor(m, n))
	end
	function tmpapi.bit.band(m, n)
		if (type(m) ~= "number" and type(m) ~= "nil") or (type(n) ~= "number" and type(n) ~= "nil") then
			error("number expected",2)
		elseif m == nil or n == nil then
			error("too few arguments",2)
		end
		return tmpapi.bit.norm(bit.band(m, n))
	end
	function tmpapi.bit.bnot(n)
		if type(n) ~= "number" and type(n) ~= "nil" then
			error("number expected",2)
		elseif n == nil then
			error("too few arguments",2)
		end
		return tmpapi.bit.norm(bit.bnot(n))
	end

	tmpapi.env = {
		_VERSION = "Luaj-jse 2.0.3",
		tostring = tmpapi.tostring,
		tonumber = tmpapi.tonumber,
		unpack = unpack,
		getfenv = tmpapi.getfenv,
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
		error = tmpapi.error,
		ipairs = ipairs,
		pairs = pairs,
		pcall = pcall,
		xpcall = xpcall,
		loadstring = tmpapi.loadstring,
		math = tablecopy(math),
		string = tablecopy(string),
		table = tablecopy(table),
		coroutine = tablecopy(coroutine),

		-- CC apis (BIOS completes tmpapi.)
		term = {
			clear = tmpapi.term.clear,
			clearLine = tmpapi.term.clearLine,
			getSize = tmpapi.term.getSize,
			getCursorPos = tmpapi.term.getCursorPos,
			setCursorPos = tmpapi.term.setCursorPos,
			setTextColor = tmpapi.term.setTextColor,
			setTextColour = tmpapi.term.setTextColor,
			setBackgroundColor = tmpapi.term.setBackgroundColor,
			setBackgroundColour = tmpapi.term.setBackgroundColor,
			setCursorBlink = tmpapi.term.setCursorBlink,
			scroll = tmpapi.term.scroll,
			write = tmpapi.term.write,
			isColor = tmpapi.term.isColor,
			isColour = tmpapi.term.isColor,
		},
		fs = {
			getDir = tmpapi.fs.getDir,
			find = tmpapi.fs.find,
			open = tmpapi.fs.open,
			list = tmpapi.fs.list,
			exists = tmpapi.fs.exists,
			isDir = tmpapi.fs.isDir,
			isReadOnly = tmpapi.fs.isReadOnly,
			getName = tmpapi.fs.getName,
			getDrive = tmpapi.fs.getDrive,
			getSize = tmpapi.fs.getSize,
			getFreeSpace = tmpapi.fs.getFreeSpace,
			makeDir = tmpapi.fs.makeDir,
			move = tmpapi.fs.move,
			copy = tmpapi.fs.copy,
			delete = tmpapi.fs.delete,
			combine = tmpapi.fs.combine,
		},
		os = {
			clock = tmpapi.os.clock,
			getComputerID = tmpapi.os.getComputerID,
			computerID = tmpapi.os.getComputerID,
			setComputerLabel = tmpapi.os.setComputerLabel,
			getComputerLabel = tmpapi.os.getComputerLabel,
			computerLabel = tmpapi.os.getComputerLabel,
			queueEvent = tmpapi.os.queueEvent,
			startTimer = tmpapi.os.startTimer,
			setAlarm = tmpapi.os.setAlarm,
			cancelTimer = tmpapi.os.cancelTimer,
			cancelAlarm = tmpapi.os.cancelAlarm,
			time = tmpapi.os.time,
			day = tmpapi.os.day,
			shutdown = tmpapi.os.shutdown,
			reboot = tmpapi.os.reboot,
		},
		peripheral = {
			isPresent = tmpapi.peripheral.isPresent,
			getType = tmpapi.peripheral.getType,
			getMethods = tmpapi.peripheral.getMethods,
			call = tmpapi.peripheral.call,
		},
		redstone = {
			getSides = tmpapi.redstone.getSides,
			getInput = tmpapi.redstone.getInput,
			getOutput = tmpapi.redstone.getOutput,
			getBundledInput = tmpapi.redstone.getBundledInput,
			getBundledOutput = tmpapi.redstone.getBundledOutput,
			getAnalogInput = tmpapi.redstone.getAnalogInput,
			getAnalogOutput = tmpapi.redstone.getAnalogOutput,
			getAnalogueInput = tmpapi.redstone.getAnalogInput,
			getAnalogueOutput = tmpapi.redstone.getAnalogOutput,
			setOutput = tmpapi.redstone.setOutput,
			setBundledOutput = tmpapi.redstone.setBundledOutput,
			setAnalogOutput = tmpapi.redstone.setAnalogOutput,
			setAnalogueOutput = tmpapi.redstone.setAnalogOutput,
			testBundledInput = tmpapi.redstone.testBundledInput,
		},
		bit = {
			blshift = tmpapi.bit.blshift,
			brshift = tmpapi.bit.brshift,
			blogic_rshift = tmpapi.bit.blogic_rshift,
			bxor = tmpapi.bit.bxor,
			bor = tmpapi.bit.bor,
			band = tmpapi.bit.band,
			bnot = tmpapi.bit.bnot,
		},
	}
	if _conf.enableAPI_http then
		tmpapi.env.http = {
			request = tmpapi.http.request,
		}
	end
	if _conf.enableAPI_cclite then
		tmpapi.env.cclite = {
			peripheralAttach = tmpapi.cclite.peripheralAttach,
			peripheralDetach = tmpapi.cclite.peripheralDetach,
			getMethods = tmpapi.cclite.getMethods,
			call = tmpapi.cclite.call,
			log = print,
			message = tmpapi.cclite.message,
			traceback = debug.traceback,
		}
	end
	tmpapi.env.rs = tmpapi.env.redstone
	tmpapi.env.math.mod = nil
	tmpapi.env.string.gfind = nil
	tmpapi.env._G = tmpapi.env
	return tmpapi
end