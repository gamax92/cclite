local messageCache = {}

local defaultConf = '_conf = {\n	-- Enable the "http" API on Computers\n	enableAPI_http = true,\n	\n	-- Enable the "cclite" API on Computers\n	enableAPI_cclite = true,\n	\n	-- The height of Computer screens, in characters\n	terminal_height = 19,\n	\n	-- The width of Computer screens, in characters\n	terminal_width = 51,\n	\n	-- The GUI scale of Computer screens\n	terminal_guiScale = 2,\n	\n	-- Enable display of emulator FPS\n	cclite_showFPS = false,\n	\n	-- The FPS to lock CCLite to\n	lockfps = 20,\n	\n	-- Enable emulation of buggy Clipboard handling\n	compat_faultyClip = true,\n	\n	-- Enable https connections through luasec\n	useLuaSec = false,\n	\n	-- Enable usage of Carrage Return for fs.writeLine\n	useCRLF = false,\n	\n	-- Check for updates\n	cclite_updateChecker = true,\n}\n'

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
			complain(type(_conf.compat_faultyClip) == "boolean", "Invalid value for _conf.compat_faultyClip", stat)
			complain(type(_conf.useLuaSec) == "boolean", "Invalid value for _conf.useLuaSec", stat)
			complain(type(_conf.useCRLF) == "boolean", "Invalid value for _conf.useCRLF", stat)
			complain(type(_conf.cclite_updateChecker) == "boolean", "Invalid value for _conf.cclite_updateChecker", stat)
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

love.graphics.setDefaultFilter("nearest", "nearest", 1)

require("http.HttpRequest")
bit = require("bit")
require("emu")
require("render")
require("api")
require("vfs")

if _conf.compat_loadstringMask ~= nil then
	Screen:message("_conf.compat_loadstringMask is obsolete")
end

-- Test if HTTPS is working
function _testLuaSec()
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

modemPool = {}

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

Emulator = {}
Emulator.computers = {}

local L2DScreenW, L2DScreenH = 800, 600
function love.resize(w, h)
	L2DScreenW, L2DScreenH = w, h
	menubar:SetSize(L2DScreenW, 25)
end

local smallfont = love.graphics.newFont(10)

function openLocation(place)
  if love._os == 'OS X' then
    os.execute('open "' .. place .. '"')
  elseif love._os == 'Windows' then -- Tested on Windows 7
    os.execute('start ' .. place)
  elseif love._os == 'Linux' then
    os.execute('xdg-open "' .. place .. '"')
  end
end

local function ui_editConfig()
	local cfgData
	if love.filesystem.exists("/CCLite.cfg") then
		cfgData = love.filesystem.read("/CCLite.cfg")
	else
		love.filesystem.write("/CCLite.cfg", defaultConf)
		cfgData = defaultConf
	end
	local editor = loveframes.Create("frame")
	editor:SetName("Configuration Editor")
	editor:SetSize(640,480)
	editor:CenterWithinArea(0, 0, love.window.getDimensions())
	editor.input_box = loveframes.Create("textinput", editor)
	editor.input_box:SetMultiline(true)
	editor.input_box:SetPos(0,25)
	editor.input_box:SetWidth(640)
	editor.input_box:SetHeight(455)
	editor.input_box:SetText(cfgData)
	editor.input_box:SetFocus(true)
	local internals = editor:GetInternals()
	for k,v in pairs(internals) do
		if v.type == "closebutton" then
			function v.OnClick()
				local cfgData = editor.input_box:GetText()
				validateConfig(cfgData, function(cfgCache)
					-- Config was good, modify things as needed.
					love.filesystem.write("/CCLite.cfg", cfgData)
					Screen.sWidth = (_conf.terminal_width * 6 * _conf.terminal_guiScale) + (_conf.terminal_guiScale * 2)
					Screen.sHeight = (_conf.terminal_height * 9 * _conf.terminal_guiScale) + (_conf.terminal_guiScale * 2)
					Screen.pixelWidth = _conf.terminal_guiScale * 6
					Screen.pixelHeight = _conf.terminal_guiScale * 9
					for i = 32,126 do Screen.tOffset[string.char(i)] = math.floor(3 - Screen.font:getWidth(string.char(i)) / 2) * _conf.terminal_guiScale end
					Screen.tOffset["@"] = 0
					Screen.tOffset["~"] = 0
					for k,v in pairs(Emulator.computers) do
						v.frame:SetSize(Screen.sWidth + 2, Screen.sHeight + 26)
						if cfgCache.terminal_height < _conf.terminal_height then
							for y = 1,cfgCache.terminal_height do
								for x = cfgCache.terminal_width + 1,_conf.terminal_width do
									v.textB[y][x] = " "
									v.backgroundColourB[y][x] = 32768
									v.textColourB[y][x] = 1
								end
							end
							for y = cfgCache.terminal_height + 1, _conf.terminal_height do
								v.textB[y] = {}
								v.backgroundColourB[y] = {}
								v.textColourB[y] = {}
								for x = 1,_conf.terminal_width do
									v.textB[y][x] = " "
									v.backgroundColourB[y][x] = 32768
									v.textColourB[y][x] = 1
								end
							end
						end
					end
					Screen:message("Loaded new config")
					_testLuaSec()
				end)
				editor:Remove()
			end
		end
	end
end

local function _ui_newComputerBox(name)
	local prompt = loveframes.Create("frame")
	prompt:SetName(name)
	prompt:SetSize(243,61)
	prompt:CenterWithinArea(0, 0, love.window.getDimensions())
	prompt.prompt_text = loveframes.Create("text", prompt)
	prompt.prompt_text:SetPos(8,34)
	prompt.prompt_text:SetText("Enter computer id:")
	prompt.input_box = loveframes.Create("textinput", prompt)
	prompt.input_box:SetPos(130,30)
	prompt.input_box:SetWidth(60)
	prompt.input_box:SetText("0")
	prompt.input_box:SetUsable({"0","1","2","3","4","5","6","7,","8","9"})
	prompt.input_box:SetFocus(true)
	prompt.OK_btn = loveframes.Create("button", prompt)
	prompt.OK_btn:SetPos(197,30)
	prompt.OK_btn:SetSize(smallfont:getWidth("OK") + 24, 25)
	prompt.OK_btn:SetText("OK")
	return prompt
end

local function ui_newNormalComputer()
	local prompt = _ui_newComputerBox("Create Normal Computer")
	function prompt.OK_btn:OnClick()
		local compu = emu.newComputer(false,tonumber(prompt.input_box:GetText()) or 0)
		compu:start()
		table.insert(Emulator.computers,compu)
		prompt:Remove()
	end
	prompt.input_box.OnEnter = prompt.OK_btn.OnClick
end

local function ui_newAdvancedComputer()
	local prompt = _ui_newComputerBox("Create Advanced Computer")
	function prompt.OK_btn:OnClick()
		local compu = emu.newComputer(true,tonumber(prompt.input_box:GetText()) or 0)
		compu:start()
		table.insert(Emulator.computers,compu)
		prompt:Remove()
	end
	prompt.input_box.OnEnter = prompt.OK_btn.OnClick
end

local function ui_aboutBox()
	local about = loveframes.Create("frame")
	about:SetName("About CCLite")
	about:SetSize(300,200)
	about:CenterWithinArea(0, 0, love.window.getDimensions())
	about.oText = loveframes.Create("text", about)
	about.oText:SetPos(8,34)
	about.oText:SetText("CCLite by Gamax92. \n \n Credits: \n Sorroko: Original CCLite \n PixelToast: Fixes to CCLite \n #lua @ freenode: Code pieces \n #love @ OFTC: Support \n CC Devs: ComputerCraft \n Searge: Fernflower :P \n nikolairesokav: LoveFrames")
end

function love.load()
	if love.system.getOS() == "Android" then
		love.keyboard.setTextInput(true)
	end
	if _conf.lockfps > 0 then 
		min_dt = 1/_conf.lockfps
		next_time = love.timer.getTime()
	end

	require("libraries.loveframes")
	
	-- LoveFrames has no Menu Bar objects, emulate one.
	menubar = loveframes.Create("panel")
	menubar:SetSize(L2DScreenW, 25)
	menubar.buttons = {}
	local offset = 0
	
	local function addMenuBtn(data)
		local menu = {}
		menu.menu = loveframes.Create("menu")
		menu.menu:SetPos(offset,24)
		for i = 1,#data.options do
			if data.options[i][1] == nil then
				menu.menu:AddDivider()
			else
				menu.menu:AddOption(data.options[i][1], false, data.options[i][2])
			end
		end
		menu.menu:SetVisible(false)
		menu.button = loveframes.Create("button")
		menu.button.menu = menu.menu
		menu.button:SetPos(offset,0)
		menu.button:SetText(data.name)
		menu.button:SetSize(smallfont:getWidth(data.name) + 14, 25)
		function menu.button:OnClick()
			self.menu:SetVisible(true)
		end
		table.insert(menubar.buttons, menu)
		offset = offset + smallfont:getWidth(data.name) + 14
	end
	
	addMenuBtn({
		name = "File",
		options = {
			{"Edit Config",ui_editConfig},
			{},
			{"Exit",function() love.event.quit() end}
		}
	})
	addMenuBtn({
		name = "New",
		options = {
			{"Normal Computer",ui_newNormalComputer},
			{"Advanced Computer",ui_newAdvancedComputer},
		}
	})
	addMenuBtn({
		name = "Help",
		options = {
			{"Help",function() end},
			{},
			{"Forum topic",function() openLocation("http://www.computercraft.info/forums2/index.php?/topic/16823-/") end},
			{"CCLite Wiki",function() openLocation("https://github.com/gamax92/cclite/wiki/_pages") end},
			{"Report a bug",function() openLocation("https://github.com/gamax92/cclite/issues") end},
			{"View the code",function() openLocation("https://github.com/gamax92/cclite") end},
			{},
			{"About",ui_aboutBox}
		}
	})

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
		love.filesystem.createDirectory("data/") -- Make the user data folder
	end
	
	love.keyboard.setKeyRepeat(true)
end

function love.mousereleased(x, y, button)
	loveframes.mousereleased(x, y, button)
	if x < 1 or x > L2DScreenW or y < 1 or y > L2DScreenH then -- Out of screen bounds
		return
	end
	-- Get the active computer
	local Computer,order,highest = nil,-1,-1
	for k,v in pairs(loveframes.base:GetChildren()) do
		if v.draworder > highest then
			highest = v.draworder
			if v.emu ~= nil then
				Computer = v.emu
				order = v.draworder
			end
		end
	end
	if Computer == nil or highest ~= order then return end
	Computer.mouse.isPressed = false
end

function love.mousepressed(x, y, button)
	loveframes.mousepressed(x, y, button)
	if x < 1 or x > L2DScreenW or y < 1 or y > L2DScreenH then -- Out of screen bounds
		return
	end
	-- Get the active computer
	local Computer,order,highest = nil,-1,-1
	for k,v in pairs(loveframes.base:GetChildren()) do
		if v.draworder > highest then
			highest = v.draworder
			if v.emu ~= nil then
				Computer = v.emu
				order = v.draworder
			end
		end
	end
	if Computer == nil or highest ~= order then return end
	-- Does the computer support mouse?
	if not Computer.colored then return end
	-- Are we clicking on the computer?
	if x <= Computer.frame.x or x >= Computer.frame.x + Screen.sWidth + 1 or y <= Computer.frame.y + 24 or y >= Computer.frame.y + Screen.sHeight + 25 then -- Not clicking on computer
		return
	end
	-- Adjust for offset
	x = x - Computer.frame.x - 1
	y = y - Computer.frame.y - 25
	local termMouseX = math_bind(math.floor((x - _conf.terminal_guiScale) / Screen.pixelWidth) + 1,1,_conf.terminal_width)
	local termMouseY = math_bind(math.floor((y - _conf.terminal_guiScale) / Screen.pixelHeight) + 1,1,_conf.terminal_height)

	if button == "l" or button == "m" or button == "r" then
		Computer.mouse.isPressed = true
		Computer.mouse.lastTermX = termMouseX
		Computer.mouse.lastTermY = termMouseY
		if button == "l" then button = 1
		elseif button == "m" then button = 3
		elseif button == "r" then button = 2
		end
		table.insert(Computer.eventQueue, {"mouse_click", button, termMouseX, termMouseY})
	elseif button == "wu" then -- Scroll up
		table.insert(Computer.eventQueue, {"mouse_scroll", -1, termMouseX, termMouseX})
	elseif button == "wd" then -- Scroll down
		table.insert(Computer.eventQueue, {"mouse_scroll", 1, termMouseX, termMouseY})
	end
end

function love.textinput(unicode)
	loveframes.textinput(unicode)
	-- Get the active computer
	local Computer,order,highest = nil,-1,-1
	for k,v in pairs(loveframes.base:GetChildren()) do
		if v.draworder > highest then
			highest = v.draworder
			if v.emu ~= nil then
				Computer = v.emu
				order = v.draworder
			end
		end
	end
	if Computer == nil or highest ~= order then return end
	if not Computer.blockInput then
		-- Hack to get around android bug
		if love.system.getOS() == "Android" and keys[unicode] ~= nil then
			table.insert(Computer.eventQueue, {"key", keys[unicode]})
		end
		if ChatAllowedCharacters[unicode:byte()] then
			table.insert(Computer.eventQueue, {"char", unicode})
		end
	end
end

function love.keypressed(key, isrepeat)
	loveframes.keypressed(key, unicode)
	-- Get the active computer
	local Computer,order,highest = nil,-1,-1
	for k,v in pairs(loveframes.base:GetChildren()) do
		if v.draworder > highest then
			highest = v.draworder
			if v.emu ~= nil then
				Computer = v.emu
				order = v.draworder
			end
		end
	end
	if Computer == nil or highest ~= order then return end
	if love.keyboard.isDown("ctrl") and not isrepeat then
		if Computer.actions.terminate == nil    and key == "t" then
			Computer.actions.terminate = love.timer.getTime()
		elseif Computer.actions.shutdown == nil and key == "s" then
			Computer.actions.shutdown =  love.timer.getTime()
		elseif Computer.actions.reboot == nil   and key == "r" then
			Computer.actions.reboot =    love.timer.getTime()
		end
	else -- Ignore key shortcuts before "press any key" action. TODO: This might be slightly buggy!
		if not Computer.running and not isrepeat then
			Computer:start()
			Computer.blockInput = true
			return
		end
	end

	if love.keyboard.isDown("ctrl") and key == "v" then
		local cliptext = love.system.getClipboardText()
		cliptext = cliptext:gsub("\r\n","\n"):sub(1,127)
		local nloc = cliptext:find("\n") or -1
		if nloc > 0 then
			cliptext = cliptext:sub(1, nloc - (_conf.compat_faultyClip and 2 or 1))
		end
		for i = 1,#cliptext do
			love.textinput(cliptext:sub(i,i))
		end
	elseif isrepeat and love.keyboard.isDown("ctrl") and (key == "t" or key == "s" or key == "r") then
	elseif keys[key] then
		table.insert(Computer.eventQueue, {"key", keys[key]})
		-- Hack to get around android bug
		if love.system.getOS() == "Android" and #key == 1 and ChatAllowedCharacters[key:byte()] then
			table.insert(Computer.eventQueue, {"char", key})
		end
	end
end

function love.keyreleased(key)
	loveframes.keyreleased(key)
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

-- Use a more assumptive and non automatic screen clearing version of love.run
function love.run()
	math.randomseed(os.time())
	math.random() math.random()

	love.event.pump()
	
	love.load(arg)
	
	-- We don't want the first frame's dt to include time taken by love.load.
    love.timer.step()
	
	local dt = 0

	-- Main loop time.
	while true do
		-- Process events.
		love.event.pump()
		for e,a,b,c,d in love.event.poll() do
			if e == "quit" then
				if not love.quit or not love.quit() then
					return
				end
			end
			love.handlers[e](a,b,c,d)
		end

		-- Update the FPS counter
		love.timer.step()
		dt = love.timer.getDelta()
		local now = love.timer.getTime()

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
		
		-- Check HTTP requests
		HttpRequest.checkRequests()
		
		if _conf.lockfps > 0 then next_time = next_time + min_dt end
		
		-- Call update and draw
		for k,v in pairs(Emulator.computers) do
			v:update(dt)
		end
		
		-- Cleanup dead computers.
		local deloff = 0
		for i = 1,#Emulator.computers do
			if Emulator.computers[i-deloff].dead == true then
				table.remove(Emulator.computers,i-deloff)
				deloff = deloff + 1
			end
		end
		
		loveframes.update(dt)

		-- Messages
		for i = 1,#messageCache do
			Screen:message(messageCache[i])
		end
		messageCache = {}

		for i = 1, 10 do
			if now - Screen.messages[i][2] > 4 and Screen.messages[i][3] == true then
				Screen.messages[i][3] = false
				Screen.dirty = true
			end
		end

		if not love.window.isVisible() then Screen.dirty = false end
		if true then --Screen.dirty then
			love.graphics.setColor(0x83, 0xC0, 0xF0, 255)
			love.graphics.rectangle("fill", 0, 0, L2DScreenW, L2DScreenH)
			loveframes.draw()
			-- Render emulator elements
			for i = 1,10 do
				if Screen.messages[i][3] then
					Screen:drawMessage(Screen.messages[i][1],_conf.terminal_guiScale, L2DScreenH - ((Screen.pixelHeight + _conf.terminal_guiScale) * (11 - i)) + _conf.terminal_guiScale)
				end
			end
		end

		if _conf.lockfps > 0 then 
			local cur_time = love.timer.getTime()
			if next_time < cur_time then
				next_time = cur_time
			else
				--love.timer.sleep(next_time - cur_time)
			end
		end

		if love.timer then love.timer.sleep(0.01) end
		if true then --Screen.dirty then
			love.graphics.present()
			Screen.dirty = false
		end
	end
end