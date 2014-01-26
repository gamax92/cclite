function peripheral.base.wirelessModem()
	local obj = {}
	local channels = {}
	obj.type = "wirelessModem"
	function obj.getMethods() return {"isOpen", "open", "close", "closeAll", "transmit", "isWireless"} end
	function obj.ccliteGetMethods() return {} end
	function obj.call(sMethod, ...)
		local tArgs = {...}
		if sMethod == "isOpen" then
			local nChannel = unpack(tArgs)
			if type(nChannel) ~= "number" then error("Expected number",2) end
			nChannel = math.floor(nChannel)
			if nChannel < 0 or nChannel > 65535 then error("Expected number in range 0-65535",2) end
			return channels[nChannel] == true
		elseif sMethod == "open" then
			local nChannel = unpack(tArgs)
			if type(nChannel) ~= "number" then error("Expected number",2) end
			nChannel = math.floor(nChannel)
			if nChannel < 0 or nChannel > 65535 then error("Expected number in range 0-65535",2) end
			channels[nChannel] = true
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
			return true
		end
	end
	return obj
end
peripheral.types.wirelessModem = "modem"