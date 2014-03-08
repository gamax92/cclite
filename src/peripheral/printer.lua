--TODO: Print in edit doesn't like it when page is already loaded.
--      In MC, the page is ended and life goes on.
local res = {}
res.gui = love.graphics.newImage("res/printer/gui.png")
res.ink_sack = love.graphics.newImage("res/printer/ink_sack.png")
res.paper = love.graphics.newImage("res/printer/paper.png")
res.page = love.graphics.newImage("res/printer/page.png")
function peripheral.base.printer(Computer,sSide)
	local obj = {}
	local paper, paperX, paperY = false, 1, 1
	local paperCount = 0
	local inkCount = 0
	obj.type = "printer"
	function obj.getMethods() return {"write","setCursorPos","getCursorPos","getPageSize","newPage","endPage","getInkLevel","setPageTitle","getPaperLevel"} end
	function obj.ccliteGetMethods() return {"setPaperLevel", "setInkLevel"} end
	function obj.call(sMethod, ...)
		local tArgs = {...}
		if sMethod == "write" then
			local sMsg = unpack(tArgs)
			if paper == false then error("Page not started",2) end
			if type(sMsg) == "string" or type(sMsg) == "number" then
				paperX = paperX + #tostring(sMsg)
			end
		elseif sMethod == "setCursorPos" then
			local nX,nY = unpack(tArgs)
			if type(nX) ~= "number" or type(nY) ~= "number" then
				error("Expected number, number",2)
			end
			if paper == false then error("Page not started",2) end
			paperX, paperY = math.floor(nX), math.floor(nY)
		elseif sMethod == "getCursorPos" then
			if paper == false then error("Page not started",2) end
			return paperX, paperY
		elseif sMethod == "getPageSize" then
			if paper == false then error("Page not started",2) end
			return 25,21
		elseif sMethod == "newPage" then
			if inkCount == 0 or paperCount == 0 then
				return false
			end
			inkCount = inkCount - 1
			paperCount = paperCount - 1
			paper, paperX, paperY = true, 1, 1
			return true
		elseif sMethod == "endPage" then
			if paper == false then error("Page not started",2) end
			paper = false
			return true
		elseif sMethod == "getInkLevel" then
			return inkCount
		elseif sMethod == "setPageTitle" then
			if paper == false then error("Page not started",2) end
		elseif sMethod == "getPaperLevel" then
			return paperCount
		end
	end
	function obj.ccliteCall(sMethod, ...)
		local tArgs = {...}
		if sMethod == "setPaperLevel" then
			local nLevel = unpack(tArgs)
			if type(nLevel) ~= "number" then error("Expected number",2) end
			nLevel = math.floor(nLevel)
			if nLevel < 0 or nLevel > 384 then error("Expected number in range 0-384",2) end
			paperCount = nLevel
		elseif sMethod == "setInkLevel" then
			local nLevel = unpack(tArgs)
			if type(nLevel) ~= "number" then error("Expected number",2) end
			nLevel = math.floor(nLevel)
			if nLevel < 0 or nLevel > 64 then error("Expected number in range 0-64",2) end
			inkCount = nLevel
		end
	end
	local color_darkGrey = {55,55,55}
	local color_grey = {139,139,139}
	local color_white = {255,255,255}
	local function printText(text,iX,iY)
		text = tostring(text)
		local x = iX + 17 - Screen.font:getWidth(text)
		local y = iY + 9
		love.graphics.setColor(color_darkGrey)
		love.graphics.print(text, (x + 1) * _conf.terminal_guiScale, (y + 1) * _conf.terminal_guiScale, 0, _conf.terminal_guiScale, _conf.terminal_guiScale)
		love.graphics.setColor(color_white)
		love.graphics.print(text, x * _conf.terminal_guiScale, y * _conf.terminal_guiScale, 0, _conf.terminal_guiScale, _conf.terminal_guiScale)
	end
	local printerFrame = loveframes.Create("frame")
	printerFrame:SetName("Printer on Computer ID " .. Computer.api.os.getComputerID() .. " side " .. sSide)
	printerFrame:SetSize((170 * _conf.terminal_guiScale) + 2, (55 * _conf.terminal_guiScale) + 26)
	printerFrame:CenterWithinArea(0, 0, love.window.getDimensions())
	printerFrame.olddraw = printerFrame.draw
	function printerFrame:draw()
		self:olddraw()
		love.graphics.translate(self.x + 1, self.y + 25)
		love.graphics.setFont(Screen.font)
		love.graphics.setColor(paper and color_white or color_grey)
		love.graphics.rectangle("fill", 34 * _conf.terminal_guiScale, 12 * _conf.terminal_guiScale, 20 * _conf.terminal_guiScale, 33 * _conf.terminal_guiScale)
		love.graphics.setColor(color_white)
		love.graphics.draw(res.gui, 0, 0, 0, _conf.terminal_guiScale, _conf.terminal_guiScale)
		if inkCount > 0 then
			love.graphics.draw(res.ink_sack, 10 * _conf.terminal_guiScale, 20 * _conf.terminal_guiScale, 0, _conf.terminal_guiScale, _conf.terminal_guiScale)
			printText(inkCount,10,19)
		end
		local paperStacks = math.floor(paperCount/64)
		local extraPaper = paperCount%64
		for i = 1,paperStacks do
			love.graphics.draw(res.paper, ((i - 1) * 18 + 58) * _conf.terminal_guiScale, 6 * _conf.terminal_guiScale, 0, _conf.terminal_guiScale, _conf.terminal_guiScale)
			printText("64",(i - 1) * 18 + 58,6)
		end
		if extraPaper > 0 then
			love.graphics.draw(res.paper, (paperStacks * 18 + 58) * _conf.terminal_guiScale, 6 * _conf.terminal_guiScale, 0, _conf.terminal_guiScale, _conf.terminal_guiScale)
			printText(extraPaper, paperStacks * 18 + 58,6)
		end
		love.graphics.translate(-self.x - 1, -self.y - 25)
	end
	local internals = printerFrame:GetInternals()
	for k,v in pairs(internals) do
		if v.type == "closebutton" then
			v:Remove()
			break
		end
	end
	function obj.detach()
		printerFrame:Remove()
	end
	return obj
end
peripheral.types.printer = "printer"