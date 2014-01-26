function peripheral.base.commandBlock()
	local obj = {}
	local cmd = ""
	obj.type = "commandBlock"
	function obj.getMethods() return {"getCommand", "setCommand", "runCommand"} end
	function obj.ccliteGetMethods() return {} end
	function obj.call(sMethod, ...)
		local tArgs = {...}
		if sMethod == "getCommand" then
			return cmd
		elseif sMethod == "setCommand" then
			if type(tArgs[1]) ~= "string" then error("Expected string",2) end
			cmd = tArgs[1]
		elseif sMethod == "runCommand" then
		end
	end
	return obj
end
peripheral.types.commandBlock = "command"