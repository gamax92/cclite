local ID = 0
function peripheral.base.diskDrive(sSide)
	-- TODO Fully test this.
	local obj = {}
	local content = {type = ""}
	local side = sSide
	obj.type = "diskDrive"
	function obj.getMethods() return {"isDiskPresent","getDiskLabel","setDiskLabel","hasData","getMountPath","hasAudio","getAudioTitle","playAudio","stopAudio","ejectDisk","getDiskID"} end
	function obj.ccliteGetMethods() return {"diskLoad"} end
	function obj.call(Computer, sMethod, ...)
		local tArgs = {...}
		if sMethod == "isDiskPresent" then
			return content.type ~= ""
		elseif sMethod == "getDiskLabel" then
			return content.label or content.title
		elseif sMethod == "setDiskLabel" then
			sLabel = unpack(tArgs)
			if type(sLabel) ~= "string" and type(sLabel) ~= "nil" then
				error("Expected string",2)
			end
			if content.type == "audio" then
				error("Disk label cannot be changed",2)
			end
			if content.type == "data" then
				content.label = sLabel
			end
		elseif sMethod == "hasData" then
			return content.type == "data"
		elseif sMethod == "getMountPath" then
			if content.type ~= "data" then
				return
			end
			return content.mount
		elseif sMethod == "hasAudio" then
			return content.type == "audio"
		elseif sMethod == "getAudioTitle" then
			return content.title
		elseif sMethod == "playAudio" then
		elseif sMethod == "stopAudio" then
		elseif sMethod == "ejectDisk" then
			if content.type ~= "" then
				table.insert(Computer.eventQueue, {"disk_eject", side})
				if content.type == "data" then
					Computer.vfs.unmount(content.mount)
				end
			end
			content = {type = ""}
		elseif sMethod == "getDiskID" then
			if content.type ~= "data" then
				return
			end
			return content.id
		end
	end
	function obj.ccliteCall(Computer, sMethod, ...)
		local tArgs = {...}
		if sMethod == "diskLoad" then
			local sType, sLabel, nID = unpack(tArgs)
			if type(sType) ~= "string" then error("Expected string",2) end
			if content.type ~= "" then error("Item already in disk drive",2) end
			if sType == "data" then
				if (type(sLabel) ~= "string" and type(sLabel) ~= "nil") or (type(nID) ~= "number" and type(nID) ~= "nil") then error("Expected string, string or nil, number or nil",2) end
				if nID == nil then
					nID = ID
					ID = ID + 1
				end
				content = {type = "data", label = sLabel, id = nID}
				if not love.filesystem.exists("disk/") then
					love.filesystem.createDirectory("disk/")
				end
				if not love.filesystem.exists("disk/" .. nID) then
					love.filesystem.createDirectory("disk/" .. nID)
				end
				if Computer.vfs.exists("/disk") then
					i = 2
					while true do
						if not Computer.vfs.exists("/disk" .. i) then
							Computer.vfs.mount("/disk/" .. nID, "/disk" .. i)
							break
						end
						i = i + 1
					end
					content.mount = "disk" .. i
				else
					Computer.vfs.mount("/disk/" .. nID, "/disk")
					content.mount = "disk"
				end
				table.insert(Computer.eventQueue, {"disk", side})
			elseif sType == "audio" then
				if type(sLabel) ~= "string" then error("Expected string, string",2) end
				content = {type = "audio", title = sLabel}
			else
				error("Invalid type " .. sType,2)
			end
		end
	end
	return obj
end
peripheral.types.diskDrive = "drive"
