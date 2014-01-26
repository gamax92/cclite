--TODO: Print in edit doesn't like it when page is already loaded.
--      In MC, the page is ended and life goes on.
function peripheral.base.printer()
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
	return obj
end
peripheral.types.printer = "printer"