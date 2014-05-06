-- Virtal FileSystem for Love2D by Gamax92
-- Adapted from an older private project of mine

local mountTable = {}
vfs = {}
function vfs.normalize(path)
	path = ("/" .. path):gsub("\\", "/")
	local tPath = {}
	for part in path:gmatch("[^/]+") do
   		if part ~= "" and part ~= "." then
   			if part == ".." and #tPath > 0 then
   				table.remove(tPath)
   			else
   				table.insert(tPath, part)
   			end
   		end
	end
	return "/" .. table.concat(tPath, "/")
end
function vfs.getMountContainer(path)
	path = vfs.normalize(path)
	local base
	for i = 1,#mountTable do
		if (path == mountTable[i][2] or path:sub(1,#mountTable[i][2]+1) == mountTable[i][2] .. "/" or (mountTable[i][2] == "/" and path:sub(1,#mountTable[i][2]) == mountTable[i][2])) and (base == nil or #mountTable[i][2] > #mountTable[base][2]) then
			base = i
		end
	end
	if base == nil then
		error("Please mount / first before using vfs",3)
	end
	return mountTable[base]
end
function vfs.fake2real(path)
	path = vfs.normalize(path)
	local mT = vfs.getMountContainer(path)
	return mT[1] .. (mT[2] == "/" and path or path:sub(#mT[2]+1))
end
function vfs.isMountPath(path)
	path = vfs.normalize(path)
	for i = 1,#mountTable do
		if mountTable[i][2] == path then
			return true
		end
	end
	return false
end
local quickPatch = {"append","createDirectory","isFile","lines","load","newFile","read","write"}
for i = 1,#quickPatch do
	vfs[quickPatch[i]] = function(path,...)
		return love.filesystem[quickPatch[i]](vfs.fake2real(path),...)
	end
end
local copyOver = {"getAppdataDirectory","getIdentity","getSaveDirectory","getUserDirectory","getWorkingDirectory","isFused","setIdentity","setSource"}
for i = 1,#copyOver do
	vfs[copyOver[i]] = love.filesystem[copyOver[i]]
end
function vfs.exists(filename)
	return vfs.isMountPath(filename) or love.filesystem.exists(vfs.fake2real(filename))
end
function vfs.getDirectoryItems(dir)
	dir = vfs.normalize(dir)
	local result = love.filesystem.getDirectoryItems(vfs.fake2real(dir))
	-- TODO: Is there any better way to do this?
	if dir == "/" then
		for i = 1,#mountTable do
			local _,count = mountTable[i][2]:gsub("/","")
			if count == 1 and mountTable[i][2] ~= "/" then
				table.insert(result,mountTable[i][2]:sub(2))
			end
		end
	else
		local _,scount = dir:gsub("/","")
		for i = 1,#mountTable do
			local _,count = mountTable[i][2]:gsub("/","")
			if count == scount + 1 and mountTable[i][2]:sub(1,#dir+1) == dir .. "/" then
				table.insert(result,mountTable[i][2]:sub(#dir+2))
			end
		end
	end
	return result
end
function vfs.getLastModified(filename)
	local filename = vfs.normalize(filename)
	for i = 1,#mountTable do
		if mountTable[i][2] == filename then
			return mountTable[i][3]
		end
	end
	return love.filesystem.getLastModifed(vfs.fake2real(filename))
end
function vfs.getSize(filename)
	-- TODO: This most likely should report an error if the path is a mount path
	-- But Love2D crashes on directories so I can't get an example.
	return love.filesystem.getSize(vfs.fake2real(filename))
end
vfs.init = function() end -- love.filesystem.init -- Don't call this, EVER
function vfs.isDirectory(filename)
	return vfs.isMountPath(filename) or love.filesystem.isDirectory(vfs.fake2real(filename))
end
vfs.fsmount = love.filesystem.mount
function vfs.mount(realPath,fakePath,virtualSide) -- Not the same as love.filesystem.mount
	if vfs.isMountPath(fakePath) then
		return false
	end
	table.insert(mountTable,{vfs.normalize(realPath),fakePath,os.time(),virtualSide}) -- TODO: os.time() doesn't guarentee unix epoch time.
	return true
end
function vfs.newFileData(contents,name,decoder)
	if name == nil and decoder == nil then
		return love.filesystem.newFileData(contents,name,decoder)
	end
	return love.filesystem.newFileData(vfs.fake2real(contents))
end
function vfs.remove(filename)
	if vfs.isMountPath(filename) then
		return false
	end
	return love.filesystem.remove(vfs.fake2real(filename))
end
vfs.fsunmount = love.filesystem.unmount
function vfs.unmount(fakePath) -- Not the same as love.filesystem.unmount
	fakePath = vfs.normalize(fakePath)
	for i = 1,#mountTable do
		if mountTable[i][2] == fakePath then
			table.remove(mountTable,i)
			return true
		end
	end
	return false
end