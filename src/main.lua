local messageCache = {}

local defaultConf = '_conf = {\n	-- Enable the "http" API on Computers\n	enableAPI_http = true,\n	\n	-- Enable the "cclite" API on Computers\n	enableAPI_cclite = true,\n	\n	-- The height of Computer screens, in characters\n	terminal_height = 19,\n	\n	-- The width of Computer screens, in characters\n	terminal_width = 51,\n	\n	-- The GUI scale of Computer screens\n	terminal_guiScale = 2,\n	\n	-- Enable display of emulator FPS\n	cclite_showFPS = false,\n	\n	-- The FPS to lock CCLite to\n	lockfps = 20,\n	\n	-- Enable https connections through luasec\n	useLuaSec = false,\n	\n	-- Enable usage of Carrage Return for fs.writeLine\n	useCRLF = false,\n	\n	-- Check for updates\n	cclite_updateChecker = true,\n	\n	-- Enable onscreen controls\n	mobileMode = false,\n	\n	--Mappings for controlpad\n	ctrlPad={\n		["top"] = "w",\n		["bottom"] = "s",\n		["left"] = "a",\n		["right"] = "d",\n		["center"] = "return"\n	}\n}\n'

-- Load configuration
local defaultConfFunc = loadstring(defaultConf,"@config")
defaultConfFunc() -- Load defaults.

function complain(test,err,stat)
	if test ~= true then
		table.insert(messageCache,err)
		stat.bad = true
	end
end

function validateConfig(cfgData,setup)
	local cfgCache = {}
	for k,v in pairs(_conf) do
		cfgCache[k] = v
	end
	local cfgFunc, err = loadstring(cfgData,"@config")
	if cfgFunc == nil then
		table.insert(messageCache,err)
	else
		stat, err = pcall(cfgFunc)
		if stat == false then
			table.insert(messageCache,err)
			_conf = cfgCache
		else
			-- Verify configuration
			local stat = {bad = false}
			complain(type(_conf.enableAPI_http) == "boolean", "Invalid value for _conf.enableAPI_http", stat)
			complain(type(_conf.enableAPI_cclite) == "boolean", "Invalid value for _conf.enableAPI_cclite", stat)
			complain(type(_conf.terminal_height) == "number", "Invalid value for _conf.terminal_height", stat)
			complain(type(_conf.terminal_width) == "number", "Invalid value for _conf.terminal_width", stat)
			complain(type(_conf.terminal_guiScale) == "number", "Invalid value for _conf.terminal_guiScale", stat)
			complain(type(_conf.cclite_showFPS) == "boolean", "Invalid value for _conf.cclite_showFPS", stat)
			complain(type(_conf.lockfps) == "number", "Invalid value for _conf.lockfps", stat)
			complain(type(_conf.useLuaSec) == "boolean", "Invalid value for _conf.useLuaSec", stat)
			complain(type(_conf.useCRLF) == "boolean", "Invalid value for _conf.useCRLF", stat)
			complain(type(_conf.cclite_updateChecker) == "boolean", "Invalid value for _conf.cclite_updateChecker", stat)
			complain(type(_conf.mobileMode) == "boolean", "Invalid value for _conf.mobileMode", stat)
			complain(type(_conf.ctrlPad) == "table", "Invalid value for _conf.ctrlPad", stat)
			if stat.bad == true then
				_conf = cfgCache
			elseif type(setup) == "function" then
				setup(cfgCache)
			end
		end
	end
end

if love.filesystem.exists("/CCLite.cfg") then
	local cfgData = love.filesystem.read("/CCLite.cfg")
	validateConfig(cfgData)
else
	love.filesystem.write("/CCLite.cfg", defaultConf)
end

love.window.setTitle("ComputerCraft Emulator")
love.window.setIcon(love.image.newImageData("res/icon.png"))
love.window.setMode((_conf.terminal_width * 6 * _conf.terminal_guiScale) + (_conf.terminal_guiScale * 2), (_conf.terminal_height * 9 * _conf.terminal_guiScale) + (_conf.terminal_guiScale * 2), {vsync = false})

if _conf.enableAPI_http then require("http.HttpRequest") end
bit = require("bit")
require("render")
require("api")
require("vfs")

if _conf.compat_loadstringMask ~= nil then
	Screen:message("_conf.compat_loadstringMask is obsolete")
end

if _conf.compat_faultyClip ~= nil then
	Screen:message("_conf.compat_faultyClip is obsolete")
end

-- Test if HTTPS is working
if _conf.useLuaSec then
	local stat, err = pcall(function()
		local trash = require("ssl.https")
	end)
	if stat ~= true then
		_conf.useLuaSec = false
		Screen:message("Could not load HTTPS support")
		if err:find("module 'ssl.core' not found") then
			print("CCLite cannot find ssl.dll or ssl.so\n\n" .. err)
		elseif err:find("The specified procedure could not be found") then
			print("CCLite cannot find ssl.lua\n\n" .. err)
		elseif err:find("module 'ssl.https' not found") then
			print("CCLite cannot find ssl/https.lua\n\n" .. err)
		else
			print(err)
		end
	end
end

-- Check for updates
local _updateCheck
if love.filesystem.exists("builddate.txt") and _conf.cclite_updateChecker then
	_updateCheck = {}
	_updateCheck.thread = love.thread.newThread("updateCheck.lua")
	_updateCheck.channel = love.thread.newChannel()
	_updateCheck.thread:start(_updateCheck.channel)
	_updateCheck.working = true
end

-- Load virtual peripherals
peripheral = {}
peripheral.base = {}
peripheral.types = {}
local tFiles = love.filesystem.getDirectoryItems("peripheral")
for k,v in pairs(tFiles) do
	local stat, err = pcall(require,"peripheral." .. v:sub(1,-5))
	if stat == false then
		Screen:message("Could not load peripheral." .. v:sub(1,-5))
		print(err)
	end
end

-- Conversion table for Love2D keys to LWJGL key codes
keys = {
	["q"] = 16, ["w"] = 17, ["e"] = 18, ["r"] = 19,
	["t"] = 20, ["y"] = 21, ["u"] = 22, ["i"] = 23,
	["o"] = 24, ["p"] = 25, ["a"] = 30, ["s"] = 31,
	["d"] = 32, ["f"] = 33, ["g"] = 34, ["h"] = 35,
	["j"] = 36, ["k"] = 37, ["l"] = 38, ["z"] = 44,
	["x"] = 45, ["c"] = 46, ["v"] = 47, ["b"] = 48,
	["n"] = 49, ["m"] = 50,
	["1"] = 2, ["2"] = 3, ["3"] = 4, ["4"] = 5, ["5"] = 6,
	["6"] = 7, ["7"] = 8, ["8"] = 9, ["9"] = 10, ["0"] = 11,
	[" "] = 57,

	["'"] = 40, [","] = 51, ["-"] = 12, ["."] = 52, ["/"] = 53,
	[":"] = 146, [";"] = 39, ["="] = 13, ["@"] = 145, ["["] = 26,
	["\\"] = 43, ["]"] = 27, ["^"] = 144, ["_"] = 147, ["`"] = 41,

	["up"] = 200,
	["down"] = 208,
	["right"] = 205,
	["left"] = 203,
	["home"] = 199,
	["end"] = 207,
	["pageup"] = 201,
	["pagedown"] = 209,
	["insert"] = 210,
	["backspace"] = 14,
	["tab"] = 15,
	["return"] = 28,
	["delete"] = 211,
	["capslock"] = 58,
	["numlock"] = 69,
	["scrolllock"] = 70,
	
	["f1"] = 59,
	["f2"] = 60,
	["f3"] = 61,
	["f4"] = 62,
	["f5"] = 63,
	["f6"] = 64,
	["f7"] = 65,
	["f8"] = 66,
	["f9"] = 67,
	["f10"] = 68,
	["f12"] = 88,
	["f13"] = 100,
	["f14"] = 101,
	["f15"] = 102,
	["f16"] = 103,
	["f17"] = 104,
	["f18"] = 105,

	["rshift"] = 54,
	["lshift"] = 42,
	["rctrl"] = 157,
	["lctrl"] = 29,
	["ralt"] = 184,
	["lalt"] = 56,
}

-- Patch love.keyboard.isDown to make ctrl checking easier
local olkiD = love.keyboard.isDown
function love.keyboard.isDown(...)
	local keys = {...}
	if #keys == 1 and keys[1] == "ctrl" then
		return olkiD("lctrl") or olkiD("rctrl")
	else
		return olkiD(unpack(keys))
	end
end

local function math_bind(val,lower,upper)
	return math.min(math.max(val,lower),upper)
end

Emulator = {
	running = false,
	reboot = false, -- Tells update loop to start Emulator automatically
	blockInput = false,
	actions = { -- Keyboard commands i.e. ctrl + s and timers/alarms
		lastTimer = 0,
		lastAlarm = 0,
		timers = {},
		alarms = {},
	},
	eventQueue = {},
	lastUpdateClock = os.clock(),
	state = {
		cursorX = 1,
		cursorY = 1,
		bg = 32768,
		fg = 1,
		blink = false,
		label = nil,
		startTime = math.floor(love.timer.getTime()*20)/20,
		peripherals = {}
	},
	minecraft = {
		time = 0,
		day = 0,
	},
	mouse = {
		isPressed = false,
	},
	lastFPS = love.timer.getTime(),
	FPS = love.timer.getFPS(),
}

function Emulator:start()
	self.reboot = false
	for y = 1, _conf.terminal_height do
		local screen_textB = Screen.textB[y]
		local screen_backgroundColourB = Screen.backgroundColourB[y]
		for x = 1, _conf.terminal_width do
			screen_textB[x] = " "
			screen_backgroundColourB[x] = 32768
		end
	end
	Screen.dirty = true
	api.init()
	Emulator.state.cursorX = 1
	Emulator.state.cursorY = 1
	Emulator.state.bg = 32768
	Emulator.state.fg = 1
	Emulator.state.blink = false
	Emulator.state.startTime = math.floor(love.timer.getTime()*20)/20

	local fn, err = loadstring(love.filesystem.read("/lua/bios.lua"),"@bios")

	if not fn then
		print(err)
		return
	end

	setfenv(fn, api.env)

	self.proc = coroutine.create(fn)
	self.running = true
	self:resume({})
end

function Emulator:stop(reboot)
	self.proc = nil
	self.running = false
	self.reboot = reboot
	Screen.dirty = true

	-- Reset events/key shortcuts
	self.actions.terminate = nil
	self.actions.shutdown = nil
	self.actions.reboot = nil
	self.actions.lastTimer = 0
	self.actions.lastAlarm = 0
	self.actions.timers = {}
	self.actions.alarms = {}
	self.eventQueue = {}
end

function Emulator:resume(...)
	if not self.running then return end
	debug.sethook(self.proc,function() error("Too long without yielding",2) end,"",9e7)
	local ok, err = coroutine.resume(self.proc, ...)
	debug.sethook(self.proc)
	if not self.proc then return end -- Emulator:stop could be called within the coroutine resulting in proc being nil
	if coroutine.status(self.proc) == "dead" then -- Which could cause an error here
		Emulator:stop()
	end
	if not ok then
		print(err) -- Bios was unable to handle error
	end
	self.blockInput = false
	return ok, err
end

function love.load()
	if love.system.getOS() == "Android" then
		love.keyboard.setTextInput(true)
	end
	if _conf.lockfps > 0 then 
		min_dt = 1/_conf.lockfps
		next_time = love.timer.getTime()
	end

	local fontPack = {131,161,163,166,170,171,172,174,186,187,188,189,191,196,197,198,199,201,209,214,215,216,220,224,225,226,228,229,230,231,232,233,234,235,236,237,238,239,241,242,243,244,246,248,249,250,251,252,255}
	ChatAllowedCharacters = {}
	for i = 32,126 do
		ChatAllowedCharacters[i] = true
	end
	for i = 1,#fontPack do
		ChatAllowedCharacters[fontPack[i]] = true
	end
	ChatAllowedCharacters[96] = nil

	if not love.filesystem.exists("data/") then
		love.filesystem.createDirectory("data/")
	end

	if not love.filesystem.exists("data/0/") then
		love.filesystem.createDirectory("data/0/") -- Make the user data folder
	end
	
	local cache0
	if love.filesystem.exists("data/0/") and not love.filesystem.isDirectory("data/0/") then
		print("Backing up /0")
		cache0 = love.filesystem.read("/data/0")
		love.filesystem.remove("/data/0")
		love.filesystem.createDirectory("data/0/")
	end
	
	vfs.mount("/data","/")
	-- Migrate to new folder.
	local list = vfs.getDirectoryItems("/")
	for k,v in pairs(list) do
		if tonumber(v) == nil or tonumber(v) < 0 or tonumber(v) ~= math.floor(tonumber(v)) or v ~= tostring(tonumber(v)) then
			print("Migrating /" .. v)
			api._copytree("/" .. v, "/0/" .. v)
			api._deltree("/" .. v)
		end
	end
	vfs.unmount("/")
	
	if cache0 ~= nil then
		print("Restoring /0")
		love.filesystem.write("/data/0/0",cache0)
	end
	
	vfs.mount("/data/0","/")
	vfs.mount("/lua/rom","/rom")
	
	love.keyboard.setKeyRepeat(true)

	Emulator:start()
end

function love.mousereleased(x, y, _button)
	if x > 0 and x < Screen.sWidth and y > 0 and y < Screen.sHeight then -- Within screen bounds.
		Emulator.mouse.isPressed = false
	end
end

function love.mousepressed(x, y, button)
	if x > 0 and x < Screen.sWidth and y > 0 and y < Screen.sHeight then -- Within screen bounds.
		if controlPad then
			if ((x - controlPad.x)^2 + (y - controlPad.y)^2 < controlPad.r^2) then
				-- Click on control pad
				if y <= controlPad.y - (controlPad.r / 3) then
					table.insert(Emulator.eventQueue, {"key",keys[_conf.ctrlPad.top]})
					if #_conf.ctrlPad.top == 1 and ChatAllowedCharacters[_conf.ctrlPad.top:byte()] then
						table.insert(Emulator.eventQueue, {"char", _conf.ctrlPad.top})
					end
				end
				if y >= controlPad.y + (controlPad.r / 3) then
					table.insert(Emulator.eventQueue, {"key",keys[_conf.ctrlPad.bottom]})
					if #_conf.ctrlPad.bottom == 1 and ChatAllowedCharacters[_conf.ctrlPad.bottom:byte()] then
						table.insert(Emulator.eventQueue, {"char", _conf.ctrlPad.bottom})
					end
				end
				if x <= controlPad.x - (controlPad.r / 3) then
					table.insert(Emulator.eventQueue, {"key",keys[_conf.ctrlPad.left]})
					if #_conf.ctrlPad.left == 1 and ChatAllowedCharacters[_conf.ctrlPad.left:byte()] then
						table.insert(Emulator.eventQueue, {"char", _conf.ctrlPad.left})
					end
				end
				if x >= controlPad.x + (controlPad.r / 3) then
					table.insert(Emulator.eventQueue, {"key",keys[_conf.ctrlPad.right]})
					if #_conf.ctrlPad.right == 1 and ChatAllowedCharacters[_conf.ctrlPad.right:byte()] then
						table.insert(Emulator.eventQueue, {"char", _conf.ctrlPad.right})
					end
				end
				if ((x - controlPad.x)^2 + (y - controlPad.y)^2 < (controlPad.r / 2)^2) then
					table.insert(Emulator.eventQueue, {"key",keys[_conf.ctrlPad.center]})
					if #_conf.ctrlPad.center == 1 and ChatAllowedCharacters[_conf.ctrlPad.center:byte()] then
						table.insert(Emulator.eventQueue, {"char", _conf.ctrlPad.center})
					end
				end
			end
		else
			local termMouseX = math_bind(math.floor((x - _conf.terminal_guiScale) / Screen.pixelWidth) + 1,1,_conf.terminal_width)
			local termMouseY = math_bind(math.floor((y - _conf.terminal_guiScale) / Screen.pixelHeight) + 1,1,_conf.terminal_height)

			if button == "l" or button == "m" or button == "r" then
				Emulator.mouse.isPressed = true
				Emulator.mouse.lastTermX = termMouseX
				Emulator.mouse.lastTermY = termMouseY
				if button == "l" then button = 1
				elseif button == "m" then button = 3
				elseif button == "r" then button = 2
				end
				table.insert(Emulator.eventQueue, {"mouse_click", button, termMouseX, termMouseY})
			elseif button == "wu" then -- Scroll up
				table.insert(Emulator.eventQueue, {"mouse_scroll", -1, termMouseX, termMouseX})
			elseif button == "wd" then -- Scroll down
				table.insert(Emulator.eventQueue, {"mouse_scroll", 1, termMouseX, termMouseY})
			end
		end
	end
end

function love.textinput(unicode)
	if not Emulator.blockInput then
		-- Hack to get around android bug
		if love.system.getOS() == "Android" and keys[unicode] ~= nil then
			table.insert(Emulator.eventQueue, {"key", keys[unicode]})
		end
		if ChatAllowedCharacters[unicode:byte()] then
			table.insert(Emulator.eventQueue, {"char", unicode})
		end
	end
end

function love.keypressed(key, isrepeat)
	if love.keyboard.isDown("ctrl") and not isrepeat then
		if Emulator.actions.terminate == nil    and key == "t" then
			Emulator.actions.terminate = love.timer.getTime()
		elseif Emulator.actions.shutdown == nil and key == "s" then
			Emulator.actions.shutdown =  love.timer.getTime()
		elseif Emulator.actions.reboot == nil   and key == "r" then
			Emulator.actions.reboot =    love.timer.getTime()
		end
	else -- Ignore key shortcuts before "press any key" action. TODO: This might be slightly buggy!
		if not Emulator.running and not isrepeat then
			Emulator:start()
			Emulator.blockInput = true
			return
		end
	end

	if love.keyboard.isDown("ctrl") and key == "v" then
		local cliptext = love.system.getClipboardText()
		cliptext = cliptext:gsub("\r\n","\n"):sub(1,128)
		local nloc = cliptext:find("\n") or -1
		if nloc > 0 then
			cliptext = cliptext:sub(1, nloc - 1)
		end
		table.insert(Emulator.eventQueue, {"paste", cliptext})
	elseif isrepeat and love.keyboard.isDown("ctrl") and (key == "t" or key == "s" or key == "r") then
	elseif keys[key] then
		table.insert(Emulator.eventQueue, {"key", keys[key]})
		-- Hack to get around android bug
		if love.system.getOS() == "Android" and #key == 1 and ChatAllowedCharacters[key:byte()] then
			table.insert(Emulator.eventQueue, {"char", key})
		end
	end
end

function love.visible(see)
	if see then
		Screen.dirty = true
	end
end

--[[
	Not implementing:
	modem_message
	monitor_touch
	monitor_resize
]]

local function updateShortcut(name, key1, key2, cb)
	if Emulator.actions[name] ~= nil then
		if love.keyboard.isDown(key1) and love.keyboard.isDown(key2) then
			if love.timer.getTime() - Emulator.actions[name] > 1 then
				Emulator.actions[name] = nil
				if cb then cb() end
			end
		else
			Emulator.actions[name] = nil
		end
	end
end

function Emulator:update()
	if _conf.lockfps > 0 then next_time = next_time + min_dt end
	local now = love.timer.getTime()
	if _conf.enableAPI_http then HttpRequest.checkRequests() end
	if self.reboot then self:start() end

	updateShortcut("terminate", "ctrl", "t", function()
			table.insert(self.eventQueue, {"terminate"})
		end)
	updateShortcut("shutdown",  "ctrl", "s", function()
			self:stop()
		end)
	updateShortcut("reboot",    "ctrl", "r", function()
			self:stop(true)
		end)

	if Emulator.state.blink then
		if Screen.lastCursor == nil then
			Screen.lastCursor = now
		end
		if now - Screen.lastCursor >= 0.25 then
			Screen.showCursor = not Screen.showCursor
			Screen.lastCursor = now
			if Emulator.state.cursorY >= 1 and Emulator.state.cursorY <= _conf.terminal_height and Emulator.state.cursorX >= 1 and Emulator.state.cursorX <= _conf.terminal_width then
				Screen.dirty = true
			end
		end
	end
	if _conf.cclite_showFPS then
		if now - self.lastFPS >= 1 then
			self.FPS = love.timer.getFPS()
			self.lastFPS = now
			Screen.dirty = true
		end
	end

	for k, v in pairs(self.actions.timers) do
		if now >= v then
			table.insert(self.eventQueue, {"timer", k})
			self.actions.timers[k] = nil
		end
	end

	for k, v in pairs(self.actions.alarms) do
		if v.day <= api.os.day() and v.time <= api.env.os.time() then
			table.insert(self.eventQueue, {"alarm", k})
			self.actions.alarms[k] = nil
		end
	end
	
	-- Messages
	for i = 1,#messageCache do
		Screen:message(messageCache[i])
	end
	if #messageCache > 0 then
		messageCache = {}
	end
		
	for i = 1, 10 do
		if now - Screen.messages[i][2] > 4 and Screen.messages[i][3] == true then
			Screen.messages[i][3] = false
			Screen.dirty = true
		end
	end
	
	-- Mouse
	if self.mouse.isPressed then
		local mouseX = love.mouse.getX()
		local mouseY = love.mouse.getY()
		local termMouseX = math_bind(math.floor((mouseX - _conf.terminal_guiScale) / Screen.pixelWidth) + 1, 1, _conf.terminal_width)
		local termMouseY = math_bind(math.floor((mouseY - _conf.terminal_guiScale) / Screen.pixelHeight) + 1, 1, _conf.terminal_width)
		if (termMouseX ~= self.mouse.lastTermX or termMouseY ~= self.mouse.lastTermY)
			and (mouseX > 0 and mouseX < Screen.sWidth and
				mouseY > 0 and mouseY < Screen.sHeight) then

			self.mouse.lastTermX = termMouseX
			self.mouse.lastTermY = termMouseY

			table.insert (self.eventQueue, {"mouse_drag", love.mouse.isDown("r") and 2 or 1, termMouseX, termMouseY})
		end
	end

	if #self.eventQueue > 0 then
		for k, v in pairs(self.eventQueue) do
			self:resume(unpack(v))
		end
		self.eventQueue = {}
	end
end

-- Use a more assumptive and non automatic screen clearing version of love.run
function love.run()
	math.randomseed(os.time())
	math.random() math.random()

	love.load(arg)

	-- Main loop time.
	while true do
		-- Process events.
		if love.event then
			love.event.pump()
			for e,a,b,c,d in love.event.poll() do
				if e == "quit" then
					if not love.quit or not love.quit() then
						if love.audio then
							love.audio.stop()
						end
						return
					end
				end
				love.handlers[e](a,b,c,d)
			end
		end

		-- Update the FPS counter
		love.timer.step()

		-- Check update checker
		if _updateCheck ~= nil and _updateCheck.working == true then
			if _updateCheck.thread:isRunning() == false and _updateCheck.channel:getCount() == 0 then
				_updateCheck.working = false
			elseif _updateCheck.channel:getCount() > 0 then
				local data = _updateCheck.channel:pop()
				if type(data) == "string" then
					local tmpFunc = loadstring("return "..data)
					if type(tmpFunc) == "function" then
						data = tmpFunc()
						if data[2] == 200 then
							local buildData = love.filesystem.read("builddate.txt")
							if buildData ~= data[5] then
								Screen:message("Found CCLite Update")
							end
						end
					end
				end
				_updateCheck.working = false
			end
		end

		-- Call update and draw
		Emulator:update()
		if not love.window.isVisible() then Screen.dirty = false end
		if Screen.dirty then
			Screen:draw()
		end

		if _conf.lockfps > 0 then 
			local cur_time = love.timer.getTime()
			if next_time < cur_time then
				next_time = cur_time
			else
				love.timer.sleep(next_time - cur_time)
			end
		end

		if love.timer then love.timer.sleep(0.001) end
		if Screen.dirty then
			love.graphics.present()
			Screen.dirty = false
		end
	end
end
