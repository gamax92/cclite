local function serialize(value)
	local kw = {
		["and"]=true,["break"]=true, ["do"]=true, ["else"]=true,
		["elseif"]=true, ["end"]=true, ["false"]=true, ["for"]=true,
		["function"]=true, ["goto"]=true, ["if"]=true, ["in"]=true,
		["local"]=true, ["nil"]=true, ["not"]=true, ["or"]=true,
		["repeat"]=true, ["return"]=true, ["then"]=true, ["true"]=true,
		["until"]=true, ["while"]=true
	}
	local id = "^[%a_][%w_]*$"
	local ts = {}
	local function s(v, l)
		local t = type(v)
		if t == "nil" then
			return "nil"
		elseif t == "boolean" then
			return v and "true" or "false"
		elseif t == "number" then
			if v ~= v then
				return "0/0"
			elseif v == math.huge then
				return "math.huge"
			elseif v == -math.huge then
				return "-math.huge"
			else
				return tostring(v)
			end
		elseif t == "string" then
			return string.format("%q", v):gsub("\\\n","\\n")
		elseif t == "table" then
			if ts[v] then
				return "nil"
			end
			ts[v] = true
			local i, r = 1, nil
			local f
			for k, v in pairs(v) do
				if r then
					r = r .. ","
				else
					r = "{"
				end
				local tk = type(k)
				if tk == "number" and k == i then
					i = i + 1
					r = r .. s(v, l + 1)
				else
					if tk == "string" and not kw[k] and string.match(k, id) then
						r = r .. k
					else
						r = r .. "[" .. s(k, l + 1) .. "]"
					end
					r = r .. "=" .. s(v, l + 1)
				end
			end
			ts[v] = nil -- allow writing same table more than once
			return (r or "{") .. "}"
		else
			return "nil"
		end
	end
	return s(value, 1)
end
local socket=require("socket")
function peripheral.base.socketModem(sSide)
	local obj = {}
	local channels = {}
	obj.type = "socketModem"
	function obj.getMethods() return {"isOpen","open","close","closeAll","transmit","isWireless"} end
	function obj.ccliteGetMethods() return {"connect","listen"} end
	local sv,cl
	local clients
	local function svtmit(chan,rchan,txt,sn)
		txt=serialize(txt)
		for k,v in pairs(clients) do
			if k~=sn then
				print("> "..chan..","..rchan..":"..txt)
				k:send(chan..","..rchan..":"..txt.."\n")
			end
		end
	end
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
			if nChannel < 0 or nChannel > 65535 then error("Expected number in range 0-65535",2) end
			if nReply < 0 or nReply > 65535 then error("Expected number in range 0-65535",2) end
			if oMessage == nil then error("2",2) end
			if cl then
				oMessage=serialize(oMessage)
				print("> "..nChannel..","..nReply..":"..oMessage)
				cl:send(nChannel..","..nReply..":"..oMessage.."\n")
			elseif sv then
				svtmit(nChannel,nReply,oMessage)
			end
		elseif sMethod == "isWireless" then
			return true
		end
	end
	local function recv(txt,cl)
		local chan,rchan=txt:match("^(%d+),(%d+):")
		if chan then
			local func,err=loadstring("return "..txt:match("^%d+,%d+:(.+)"))
			if func then
				local res=setfenv(func,{math={huge=math.huge}})()
				if res~=nil then
					if cl then
						svtmit(chan,rchan,res,cl)
					end
					print("< "..tonumber(chan)..","..tonumber(rchan)..":"..serialize(res))
					table.insert(Emulator.eventQueue,{"modem_message",sSide,tonumber(chan),tonumber(rchan),res,100})
				end
			end
		end
	end
	local function close()
		if sv then
			sv:close()
			Emulator.actions.sockets[sv]=nil
			for k,v in pairs(clients) do
				Emulator.actions.sockets[k]=nil
			end
			clients=nil
		elseif cl then
			cl:close()
			Emulator.actions.sockets[cl]=nil
		end
	end
	function obj.ccliteCall(sMethod,...)
		local tArgs = {...}
		if sMethod == "listen" then
			close()
			sv,err=socket.bind(tArgs[2] or "*",tArgs[1])
			error(err,2)
			clients={}
			sv:settimeout(0)
			Emulator.actions.sockets[sv]={
				server=true,
				onAccept=function(cl)
					clients[cl]=true
					cl:settimeout(0)
					Emulator.actions.sockets[cl]={
						onRecv=function(txt)
							recv(txt,cl)
						end
					}
				end
			}
			return true
		elseif sMethod == "connect" then
			close()
			local err
			cl,err=socket.connect(tArgs[1],tArgs[2])
			error(err,2)
			cl:settimeout(0)
			Emulator.actions.sockets[cl]={
				onRecv=function(txt)
					recv(txt)
				end
			}
		end
	end
	function obj.detach()
		close()
	end
	return obj
end
peripheral.types.socketModem = "modem"