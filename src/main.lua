-- Verify configuration
assert(type(_conf.enableAPI_http) == "boolean", "Invalid value for _conf.enableAPI_http")
assert(type(_conf.enableAPI_cclite) == "boolean", "Invalid value for _conf.enableAPI_cclite")
assert(type(_conf.terminal_height) == "number", "Invalid value for _conf.terminal_height")
assert(type(_conf.terminal_width) == "number", "Invalid value for _conf.terminal_width")
assert(type(_conf.terminal_guiScale) == "number", "Invalid value for _conf.terminal_guiScale")
assert(type(_conf.cclite_showFPS) == "boolean", "Invalid value for _conf.cclite_showFPS")
assert(type(_conf.lockfps) == "number", "Invalid value for _conf.lockfps")
assert(type(_conf.compat_faultyClip) == "boolean", "Invalid value for _conf.compat_faultyClip")
assert(type(_conf.useLuaSec) == "boolean", "Invalid value for _conf.useLuaSec")
assert(type(_conf.useCRLF) == "boolean", "Invalid value for _conf.useCRLF")

if _conf.enableAPI_http then require("http.HttpRequest") end
bit = require("bit")
require("emu")
require("render")
require("api")
require("vfs")

if _conf.compat_loadstringMask ~= nil then
	Screen:message("_conf.compat_loadstringMask is obsolete")
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
	
	table.insert(Emulator.computers,emu.newComputer())
	table.insert(Emulator.computers,emu.newComputer())
	
	-- LoveFrames has no Menu Bar objects, emulate one.
	menubar = loveframes.Create("panel")
	menubar:SetSize(L2DScreenW, 25)
	menubar.buttons = {}
	local smallfont = love.graphics.newFont(10)
	local offset = 0
	
	local function addMenuBtn(data)
		local menu = {}
		menu.menu = loveframes.Create("menu")
		menu.menu:SetPos(offset,25)
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
		function menu.button.OnClick(object)
			object.menu:SetVisible(true)
		end
		table.insert(menubar.buttons, menu)
		offset = offset + smallfont:getWidth(data.name) + 14
	end
	
	addMenuBtn({
		name = "File",
		options = {
			{"Something",function() end},
			{},
			{"Exit",function() end}
		}
	})
	addMenuBtn({
		name = "New",
		options = {
			{"Normal Computer",function() end},
			{"Advanced Computer",function() end}
		}
	})
	addMenuBtn({
		name = "Help",
		options = {
			{"Help",function() end},
			{},
			{"Forum topic",function() end},
			{"CCLite Wiki",function() end},
			{"Report a bug",function() end},
			{"View the code",function() end},
			{},
			{"About",function() end}
		}
	})
	
	love.filesystem.setIdentity("ccemu")

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

	vfs.mount("/data","/")
	vfs.mount("/lua/rom","/rom")
	
	love.keyboard.setKeyRepeat(true)

	for k,v in pairs(Emulator.computers) do
		v:start()
	end
end

function love.mousereleased(x, y, button)
	loveframes.mousereleased(x, y, button)
	if x < 1 or x > L2DScreenW or y < 1 or y > L2DScreenH then -- Out of screen bounds
		return
	end
	-- Get the active computer
	local Computer,order = nil,-1
	for k,v in pairs(Emulator.computers) do
		if v.frame.draworder > order then
			Computer = v
			order = v.frame.draworder
		end
	end
	if Computer == nil then return end
	Computer.mouse.isPressed = false
end

function love.mousepressed(x, y, button)
	loveframes.mousepressed(x, y, button)
	if x < 1 or x > L2DScreenW or y < 1 or y > L2DScreenH then -- Out of screen bounds
		return
	end
	-- Get the active computer
	local Computer,order = nil,-1
	for k,v in pairs(Emulator.computers) do
		if v.frame.draworder > order then
			Computer = v
			order = v.frame.draworder
		end
	end
	if Computer == nil then return end
	-- Are we clicking on the computer?
	if x <= Computer.frame.x or x >= Computer.frame.x + Screen.sWidth + 1 or y <= Computer.frame.y + 24 or y >= Computer.frame.y + Screen.sHeight + 25 then -- Not clicking on computer
		return
	end
	-- Adjust for offset
	x = x - Computer.frame.x
	y = y - Computer.frame.y
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
	local Computer,order = nil,-1
	for k,v in pairs(Emulator.computers) do
		if v.frame.draworder > order then
			Computer = v
			order = v.frame.draworder
		end
	end
	if Computer == nil then return end
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
	local Computer,order = nil,-1
	for k,v in pairs(Emulator.computers) do
		if v.frame.draworder > order then
			Computer = v
			order = v.frame.draworder
		end
	end
	if Computer == nil then return end
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
		end

		if _conf.lockfps > 0 then 
			local cur_time = love.timer.getTime()
			if next_time < cur_time then
				next_time = cur_time
			else
				--love.timer.sleep(next_time - cur_time)
			end
		end

		if love.timer then love.timer.sleep(0.001) end
		if true then --Screen.dirty then
			love.graphics.present()
			Screen.dirty = false
		end
	end
end