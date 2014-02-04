local function math_bind(val,lower,upper)
	return math.min(math.max(val,lower),upper)
end

emu = {}
function emu.newComputer()
	local Computer = {
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
		minecraft = {
			time = 0,
			day = 0,
		},
		mouse = {
			isPressed = false,
		},
		lastFPS = love.timer.getTime(),
		FPS = love.timer.getFPS(),
		textB = {},
		backgroundColourB = {},
		textColourB = {},
	}
	for y = 1, _conf.terminal_height do
		Computer.textB[y] = {}
		Computer.backgroundColourB[y] = {}
		Computer.textColourB[y] = {}
		for x = 1, _conf.terminal_width do
			Computer.textB[y][x] = " "
			Computer.backgroundColourB[y][x] = 32768
			Computer.textColourB[y][x] = 1
		end
	end

	function Computer:start()
		self.reboot = false
		for y = 1, _conf.terminal_height do
			local screen_textB = Computer.textB[y]
			local screen_backgroundColourB = Computer.backgroundColourB[y]
			for x = 1, _conf.terminal_width do
				screen_textB[x] = " "
				screen_backgroundColourB[x] = 32768
			end
		end
		Screen.dirty = true
		self.api = api.init(self)

		local fn, err = loadstring(love.filesystem.read("/lua/bios.lua"),"@bios")

		if not fn then
			print(err)
			return
		end

		setfenv(fn, self.api.env)

		self.proc = coroutine.create(fn)
		self.running = true
		self:resume({})
	end

	function Computer:stop(reboot)
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

	function Computer:resume(...)
		if not self.running then return end
		debug.sethook(self.proc,function() error("Too long without yielding",2) end,"",9e7)
		local ok, err = coroutine.resume(self.proc, ...)
		debug.sethook(self.proc)
		if not self.proc then return end -- Computer:stop could be called within the coroutine resulting in proc being nil
		if coroutine.status(self.proc) == "dead" then -- Which could cause an error here
			self:stop()
		end
		if not ok then
			error(err,math.huge) -- Bios was unable to handle error, crash CCLite
		end
		self.blockInput = false
		return ok, err
	end
	
	local function updateShortcut(name, key1, key2, cb)
		if Computer.actions[name] ~= nil then
			if love.keyboard.isDown(key1) and love.keyboard.isDown(key2) then
				if love.timer.getTime() - Computer.actions[name] > 1 then
					Computer.actions[name] = nil
					if cb then cb() end
				end
			else
				Computer.actions[name] = nil
			end
		end
	end

	function Computer:update(dt)
		if _conf.lockfps > 0 then next_time = next_time + min_dt end
		loveframes.update(dt)
		tween.update(dt)
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

		if self.api.comp.blink then
			if Screen.lastCursor == nil then
				Screen.lastCursor = now
			end
			if now - Screen.lastCursor >= 0.25 then
				Screen.showCursor = not Screen.showCursor
				Screen.lastCursor = now
				if self.api.comp.cursorY >= 1 and self.api.comp.cursorY <= _conf.terminal_height and self.api.comp.cursorX >= 1 and self.api.comp.cursorX <= _conf.terminal_width then
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
			if v.day <= self.api.os.day() and v.time <= self.api.os.time() then
				table.insert(self.eventQueue, {"alarm", k})
				self.actions.alarms[k] = nil
			end
		end
		
		-- Mouse
		if self.mouse.isPressed then
			local mouseX = love.mouse.getX() - Computer.frame.x
			local mouseY = love.mouse.getY() - Computer.frame.y
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

	Computer.frame = loveframes.Create("frame")
	Computer.frame.emu = Computer
	Computer.frame:SetName("Advanced Computer")
	Computer.frame:SetSize(Screen.sWidth + 2, Screen.sHeight + 26)
	Computer.frame:CenterWithinArea(0, 0, love.window.getDimensions())
	Computer.frame.olddraw = Computer.frame.draw
	function Computer.frame:draw()
		self:olddraw()
		love.graphics.translate(self.x + 1, self.y + 25)
		Screen:draw(self.emu)
		love.graphics.translate(-self.x - 1, -self.y - 25)
	end
	return Computer
end