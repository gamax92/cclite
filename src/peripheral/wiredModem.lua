local typeC = {}
function peripheral.base.wiredModem()
	local obj = {}
	local remote = {}
	local channels = {}
	obj.type = "wiredModem"
	function obj.getMethods() return {"open","isOpen","close","closeAll","transmit","isWireless","getNamesRemote","isPresentRemote","getTypeRemote","getMethodsRemote","callRemote"} end
	function obj.ccliteGetMethods() return {"peripheralAttach","peripheralDetach"} end
	function obj.call(sMethod, ...)
		local tArgs = {...}
		if sMethod == "open" then
			local nChannel = unpack(tArgs)
			if type(nChannel) ~= "number" then error("Expected number",2) end
			nChannel = math.floor(nChannel)
			if nChannel < 0 or nChannel > 65535 then error("Expected number in range 0-65535",2) end
			channels[nChannel] = true
		elseif sMethod == "isOpen" then
			local nChannel = unpack(tArgs)
			if type(nChannel) ~= "number" then error("Expected number",2) end
			nChannel = math.floor(nChannel)
			if nChannel < 0 or nChannel > 65535 then error("Expected number in range 0-65535",2) end
			return channels[nChannel] == true
		elseif sMethod == "close" then
			local nChannel = unpack(tArgs)
			if type(nChannel) ~= "number" then error("Expected number",2) end
			nChannel = math.floor(nChannel)
			if nChannel < 0 or nChannel > 65535 then error("Expected number in range 0-65535",2) end
			channels[nChannel] = false
		elseif sMethod == "closeAll" then
			for k,v in pairs(channels) do
				channels[k] = false
			end
		elseif sMethod == "transmit" then
			local nChannel, nReply, oMessage = unpack(tArgs)
			if type(nChannel) ~= "number" or type(nReply) ~= "number" then error("Expected number",2) end
			if oMessage == nil then error("2",2) end
		elseif sMethod == "isWireless" then
			return false
		elseif sMethod == "getNamesRemote" then
			local names = {}
			for k,v in pairs(remote) do
				table.insert(names,k)
			end
			return names
		elseif sMethod == "isPresentRemote" then
			local sSide = unpack(tArgs)
			if type(sSide) ~= "string" then error("Expected string",2) end
			return remote[sSide] ~= nil
		elseif sMethod == "getTypeRemote" then
			local sSide = unpack(tArgs)
			if type(sSide) ~= "string" then error("Expected string",2) end
			if remote[sSide] then return peripheral.types[remote[sSide].type] end
			return
		elseif sMethod == "getMethodsRemote" then
			local sSide = unpack(tArgs)
			if type(sSide) ~= "string" then error("Expected string",2) end
			if remote[sSide] then return remote[sSide].getMethods() end
			return
		elseif sMethod == "callRemote" then
			local sSide, sMethod = unpack(tArgs)
			if type(sSide) ~= "string" then error("Expected string",2) end
			if type(sMethod) ~= "string" then error("Expected string, string",2) end
			if not remote[sSide] then error("No peripheral attached",2) end
			if not remote[sSide].cache[sMethod] then
				error("No such method " .. sMethod,2)
			end
			return remote[sSide].call(sMethod, unpack(tArgs,3))
		end
	end
	function obj.ccliteCall(sMethod, ...)
		local tArgs = {...}
		if sMethod == "peripheralAttach" then
			local sType = unpack(tArgs)
			if type(sType) ~= "string" then
				error("Expected string",2)
			end
			if not peripheral.base[sType] then
				error("No virtual peripheral of type " .. sType,2)
			end
			local objType = peripheral.types[sType]
			typeC[objType] = (typeC[objType] or -1) + 1
			local sSide = objType .. "_" .. typeC[objType]
			remote[sSide] = peripheral.base[sType](sSide)
			local methods = remote[sSide].getMethods()
			remote[sSide].cache = {}
			for i = 1,#methods do
				remote[sSide].cache[methods[i]] = true
			end
			local ccliteMethods = remote[sSide].ccliteGetMethods()
			remote[sSide].ccliteCache = {}
			for i = 1,#ccliteMethods do
				remote[sSide].ccliteCache[ccliteMethods[i]] = true
			end
			table.insert(Emulator.eventQueue, {"peripheral",sSide})
		elseif sMethod == "peripheralDetach" then
			local sSide = unpack(tArgs)
			if type(sSide) ~= "string" then error("Expected string",2) end
			if not remote[sSide] then
				error("No peripheral attached to " .. sSide,2)
			end
			remote[sSide] = nil
			table.insert(Emulator.eventQueue, {"peripheral_detach",sSide})
		end
	end
	return obj
end
peripheral.types.wiredModem = "modem"