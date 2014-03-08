local ID = 1
local function baseobj(Computer, sType)
	local obj = {}
	local myID = ID
	ID = ID + 1
	obj.type = sType
	function obj.getMethods() return {"turnOn", "shutdown", "reboot", "getID"} end
	function obj.ccliteGetMethods() return {} end
	function obj.call(sMethod)
		if sMethod == "turnOn" then
		elseif sMethod == "shutdown" then
		elseif sMethod == "reboot" then
		elseif sMethod == "getID" then
			return myID
		end
	end
	return obj
end

function peripheral.base.computer(Computer) return baseobj(Computer, "computer") end
function peripheral.base.turtle(Computer) return baseobj(Computer, "turtle") end
peripheral.types.computer = "computer"
peripheral.types.turtle = "turtle"