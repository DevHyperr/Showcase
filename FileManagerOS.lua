
local services = game.ReplicatedStorage:WaitForChild("Services")
local Types = require(services:WaitForChild("Types"))
local Settings = require(services:WaitForChild("Settings"))
local windowManager = require(services:WaitForChild("WindowManager"))
local updateDesktop = game.ReplicatedStorage:WaitForChild("UpdateDesktop")
local uis = game:GetService("UserInputService")

local players = game:GetService("Players")
local player = players.LocalPlayer :: Player
local playerGui = player:WaitForChild("PlayerGui")
local OSLayer = playerGui:WaitForChild("OSLayer") :: ScreenGui
local screen = playerGui:WaitForChild("Screen") :: ScreenGui

local manager = {} :: Types.FileManager
local harddrive: Types.File = {Name = "Harddrive", Path = "", Content = {}, Type = "Folder", Id=0, Size=0, SystemFile = true}

local threads: {[string]: {[number]: thread}} = {}

local function incrementSuffix(str: string): string
	-- check if "_" exists at all
	local lastUnderscore = string.match(str, ".*()_")
	if not lastUnderscore then
		return str .. "_1"
	end

	-- get the part after the last "_"
	local suffix = string.sub(str, lastUnderscore + 1)

	-- check if suffix is a non-negative integer
	if string.match(suffix, "^%d+$") then
		local number = tonumber(suffix)
		return string.sub(str, 1, lastUnderscore) .. tostring(number + 1)
	end

	-- suffix is not numeric
	return str .. "_1"
end

function manager.forceExit(filePath, index): boolean
	local entry = threads[filePath]
	if entry then
		if index == -1 then
			for _, thread in pairs(entry) do
				task.cancel(thread)
			end
			threads[filePath] = nil
			print("force exit")
			return true
		else
			local thread = entry[index]
			if thread then
				task.cancel(thread)
				table.remove(entry, index)
				return true
			else
				warn("Invalid thread index")
				return false
			end
		end
	else
		warn("Invalid file path", filePath)
		return false
	end
end

local function buildPath(parentPath: string, name: string): string
	if parentPath == "" then
		return name
	end
	return parentPath .. "/" .. name
end

function manager.GetHarddrive(): Types.File
	return harddrive
end

function manager.getValidName(parentFolder, name)
	if typeof(parentFolder) == "string" then
		local s
		s, parentFolder = manager.fileFromPath(parentFolder)
	end
	local validName = name
	if manager.hasChildbyName(parentFolder, validName) then
		local alreadyExists = true
		repeat
			local newName = incrementSuffix(validName)
			validName = newName
			task.wait()
			alreadyExists = manager.hasChildbyName(parentFolder, newName)
		until not alreadyExists
	end
	return validName
end

function manager.addListener(actions: {Enum.UserInputType | Enum.KeyCode}, callback: () -> ())
	local listener
	listener = uis.InputBegan:Connect(function(input)
		for _, action in pairs(actions) do
			if action.EnumType == Enum.UserInputType then
				if input.UserInputType == action then
					listener:Disconnect()
					callback()
				end
			elseif action.EnumType == Enum.KeyCode then
				if input.KeyCode == action then
					listener:Disconnect()
					callback()
				end
			end
		end
	end)
end



function manager.fileSelection(filetypes): File?
	local _, explorer = manager.fileFromPath("System/Explorer")
	if explorer then
		if explorer["Execute"] then
			return explorer.Execute(true, filetypes)
		end
	else
		windowManager.error("Explorer was moved.")
		warn("Explorer not found in Programs.")
		return
	end
end

function manager.getLongFiletype(fileType)
	for long, short in pairs(Settings.Filetypes) do
		if short == fileType then
			return long
		end
	end
	return ""
end

function manager.percentage(base, value, round)
	if base and value then
		local n = 1
		if round and round >= 1 then
			n = 10 ^ round
		end
		return math.round((value / base) * 100 * n) / n
	else
		return 0
	end
end

function manager.getShortFiletype(fileType, withDot)
	for long, short in pairs(Settings.Filetypes) do
		if long == fileType then
			if withDot then
				return "."..short
			else
				return short
			end
		end
	end
	return ""
end

function manager.formatDate(timestamp, includeTime)
	local date = os.date("%m/%d/%Y", timestamp)
	local time = os.date("%H:%M", timestamp)
	if includeTime then
		return date .. " " .. time
	else
		return date
	end
end

function manager.updateFileSize(file)
	if file.Type == "Folder" then
		local total = 0
		for _, f in pairs(file.Content) do
			total += f["Size"]
		end
		manager.setFileKey(file, "Size", total)
		return total
	end
	-- Recursive function to calculate the file size
	local function recursive(file, size)
		for key, value in pairs(file) do
			-- Add key length if the file is not a folder
			if typeof(key) == "string" and file.Type ~= "Folder" then
				size = size + #key
			end
			-- Add value length depending on its type
			if typeof(value) == "string" and file.Type ~= "Folder" then
				size = size + #value
			elseif typeof(value) == "number" and file.Type ~= "Folder" then
				size = size + 8  -- assuming numbers take 8 bytes
			elseif typeof(value) == "boolean" and file.Type ~= "Folder" then
				size = size + 1  -- assuming booleans take 1 byte
			elseif typeof(value) == "table" then
				-- Recurse into the nested table and accumulate size
				size = size + recursive(value, 0)  -- start fresh for nested tables
			end
		end
		return size
	end

	-- Calculate size of the file and its contents
	local size = recursive(file, 0)

	-- Update the file size in the file metadata
	manager.setFileKey(file, "Size", size)

	return size
end


-- Creates a file inside a specified path
function manager.createFile(path: string, args: {[string]: any})
	local success, parent = manager.fileFromPath(path)

	if not success or not parent then
		warn("Invalid parent path:", path)
		return
	end

	if parent.Type ~= "Folder" and parent.Name ~= "Harddrive" then
		warn("Files can only be created inside folders or the harddrive.")
		return
	end

	if not args.Name or not args.Type then
		warn("File is missing Name or Type.")
		return
	end

	local newFile = table.clone(args)
	
	

	local originalName = newFile.Name
	if manager.hasChildbyName(parent, originalName) then
		local counter = 1
		repeat
			local newName = originalName .. "_" .. counter
			counter += 1
			newFile.Name = newName
			newFile.Path = buildPath(parent.Path, newName)
		until not manager.hasChildbyName(parent, newName)
	end

	
	newFile.Path = buildPath(path, newFile.Name)
	newFile.LastModified = os.time()
	
	if (args.Type == "Text Document") and newFile["Content"] == nil then
		newFile.Content = ""
	end

	if newFile.Type == "Folder" then
		newFile.Content = newFile.Content or {}
	end

	parent.Content[newFile.Name] = newFile
	newFile.Size = manager.updateFileSize(newFile)
	manager.updateFileSize(parent)
	
	updateDesktop:Fire()
	return newFile
end

function manager.newTextDocument(
	name: string,
	path: string,
	content: string?,
	systemFile: boolean?
)
	return manager.createFile(path, {
		Name = name,
		Type = "Text Document",
		Content = content or "",
		SystemFile = systemFile or false,
	})
end


function manager.newFolder(name: string, path: string, systemFile: boolean?)
	if path == "" then
		local folder = {
			Name = name,
			Type = "Folder",
			Path = name,
			Content = {},
			SystemFile = systemFile or false,
			LastModified = os.time()
		}
		
		harddrive.Content[folder.Name] = folder
		manager.updateFileSize(folder)
		return folder
	end

	return manager.createFile(path, {
		Name = name,
		Type = "Folder",
		Content = {},
		SystemFile = systemFile or false,
		LastModified = os.time()
	})
end

function manager.getFileSize(file: Types.File): number
	if file["Size"] then
		return file.Size
	else
		warn("File has no size")
		warn(file)
	end
end

function manager.formatSize(bytes: number): string
	if bytes then
		local formats = {"B", "KB", "MB", "GB", "TB"}
		local i = 0
		local formated = bytes .. " B"
		for _, format in ipairs(formats) do
			if i == 0 then
				i = 1
			else
				i = i * 1024
			end
			if bytes > i then
				formated = math.round(bytes/i) .. " " .. format
			end
		end
		return formated
	else
		return "0B"
	end
end

function manager.isValidName(name): boolean
	-- 1 to 32 characters
	-- a-Z, 0-9, - and _ only
	local min, max = 1, 32
	if not name then return false end
	if typeof(name) ~= "string" then return false end
	if #name < min or #name > max then return false end
	return name:match("^[A-Za-z0-9-_]+$") ~= nil
end
	
function manager.newExecutable(
	name: string,
	path: string,
	icon: string,
	Execute: () -> (),
	OpenWithFile: (file: {}) -> (),
	systemFile: boolean?
)
	if systemFile then
		return manager.createFile(path, {
			Name = name,
			Type = "System Executable",
			Icon = icon,
			Execute = Execute,
			OpenWithFile = OpenWithFile,
			SystemFile = true,
		})
	else
		return manager.createFile(path, {
			Name = name,
			Type = "Executable",
			Icon = icon,
			Execute = Execute,
			OpenWithFile = OpenWithFile,
			SystemFile = false,
		})
	end
end

function manager.addTextboxEnterListener(textbox, callback)
	-- Ensure callback is a function
	if typeof(callback) ~= "function" then
		error("The second parameter must be a function.")
		return
	end

	-- Check if textbox is actually a valid TextBox
	if not textbox or not textbox:IsA("TextBox") then
		error("The first parameter must be a TextBox.")
		return
	end
	print("Textbox listener active.")
	-- Connect to the InputBegan event
	local conn
	conn = uis.InputBegan:Connect(function(key)
		if (key.KeyCode == Enum.KeyCode.KeypadEnter or key.KeyCode == Enum.KeyCode.Return)  then
			textbox:ReleaseFocus()  -- Release focus from the textbox
			callback()  -- Execute the callback
			conn:Disconnect()  -- Disconnect the event
			print("Done")
			return true  -- Return true to indicate success
			
		end
	end)

	return false  -- Return false by default, Enter hasn't been pressed yet
end

function manager.executeFileWith(executable, file, silent)
	print("execute file with")
	print(executable, file)
	if typeof(executable) == "string" then
		local s, f = manager.fileFromPath(executable)
		if s and f then
			executable = f
		else
			warn(`"{executable}" is an invalid path and can therefore not be executed.`)
			if not silent then
				windowManager.error(`"{executable}" is an invalid path and can therefore not be executed.`)
			end
			return
		end
	end
	if typeof(file) == "string" then
		local s, f = manager.fileFromPath(file)
		if s and f then
			file = f
		else
			warn(`"{file}" is an invalid path and can therefore not be executed.`)
			if not silent then
				windowManager.error(`"{file}" is an invalid path and can therefore not be executed.`)
			end
			return
		end
	end

	if executable.Type == "Executable" or executable.Type == "System Executable" then
		if executable["OpenWithFile"] then
	
			executable.OpenWithFile(file)
		else

			windowManager.error(`"{executable.Path} has no method .OpenWithFile()."`)
		end
	end
end

function manager.executeFile(file, err)
	if typeof(file) == "string" then
		local s, f = manager.fileFromPath(file)
		if s and f then
			file = f
		else
			warn(`"{file}" is an invalid path and can therefore not be executed.`)
			if err then
				windowManager.error(`"{file}" is an invalid path and can therefore not be executed.`)
			end
			return
		end
	end
	if file.Type == "Executable" or file.Type == "System Executable" then
		if file["Execute"] then
			local thread = task.spawn(function() file.Execute() end)
			local entry = threads[file.Path]
			if not entry then
				threads[file.Path] = {}
				entry = threads[file.Path]
			end
			table.insert(entry, thread)
		else
			file.Execute = function() end
		end
	elseif file.Type == "Terminal Script" then
		local content = file["Content"]
		local _, terminalFile = manager.fileFromPath("System/Terminal")
		if content then
			local commands = string.split(content, ";")
			local terminal = terminalFile.Execute(commands)
		else
			terminalFile.Execute()
		end
	
	elseif file.Type == "Shortcut" then
		local s, f = manager.fileFromPath(file.Pointer)
		if s and f then
			manager.executeFile(f)
		else
			warn("Couldnt execute shortcut bc file is missing")
			if err then
				windowManager.error("Shortcut points to an invalid path.")
			end
		end
	
	elseif Settings.OpenWithFileDefaults[file.Type] then
		local _, app = manager.fileFromPath(Settings.OpenWithFileDefaults[file.Type])
		if app then
			app.OpenWithFile(file)
		else
			local selection = manager.fileSelection({ "sys", "exe" })
			if selection then
				manager.executeFileWith(selection, file)
			end
		end
		
	else
		warn("Cant execute file.")
		if err then
			windowManager.error("File has no method for execution specified.")
		end
	end
end

function manager.PathToTaskbar(path)
	local _, file = manager.fileFromPath(path)
	if file then
		windowManager.ShortcutToTaskbar(file)
	end
end

game.ReplicatedStorage.OpenPath.Event:Connect(function(path)
	local s, file = manager.fileFromPath(path)
	if s and file then
		manager.executeFile(file)
	end
end)

game.ReplicatedStorage.ForceExit.OnInvoke = function(path, index)
	return manager.forceExit(path, index)
end

function manager.newShortcut(
	name: string,
	targetPath: string,
	icon: string?,
	systemFile: boolean?
)
	local success, target = manager.fileFromPath(targetPath)
	if not success then
		warn("Shortcut points to invalid path:", targetPath)
	end

	local shortcut = {
		Name = manager.getValidName("Desktop", name),
		Type = "Shortcut",
		Icon = icon or (target and Settings.Icons.Filetypes[target.Type]),
		Pointer = targetPath,
		SystemFile = systemFile or false,
		LastModified = os.time(),
	}

	shortcut.Path = buildPath("Desktop", name)
	local s,f = manager.fileFromPath("Desktop")
	f.Content[shortcut.Name] = shortcut
	manager.updateFileSize(shortcut)
	return shortcut
end

uis.InputBegan:Connect(function(key)

	if key.KeyCode == Enum.KeyCode.H and uis:IsKeyDown(Enum.KeyCode.LeftControl) then
		warn(harddrive)
	end
	
	if key.KeyCode == Enum.KeyCode.T and uis:IsKeyDown(Enum.KeyCode.LeftShift) then

		local info = {
			SizeX = 0.22,
			SizeY = 0.164,
			MinSizeX = 0.1,
			MinSizeY = 0.1,
			Title = "Task Manager",
			Icon = "rbxassetid://14510534759",
		}
		local window = windowManager.openWindow(info, "sys")
		local entryTemplate = game.ReplicatedStorage.Gui.ExplorerEntry
		local function newEntry(thread)
			local entry = entryTemplate:Clone()
			entry.Parent = window
			local frame = entry.Frame
			frame.Icon.Image = ""
			frame.FileExtension:Destroy()
			frame.FileName.Text = thread.Name
			frame.FileSize:Destroy()
			frame.FileSizePercentage:Destroy()
			frame.FileType:Destroy()
			frame.LastModified:Destroy()
			entry.MouseButton1Click:Connect(function()
				local option = windowManager.openOptions({"End Task"})
				if option == "End Task" then
					manager.forceExit(thread.Name, thread.Index)
				end
			end)
		end
		newEntry({Name = "Application"})
		for path, data in pairs(threads) do
			for index, t in pairs(data) do
				newEntry({Name = path, Thread = t, Index = index})
			end
		end

	end
	if key.KeyCode == Enum.KeyCode.R and uis:IsKeyDown(Enum.KeyCode.LeftControl) then
		local info = {
			SizeX = 0.22,
			SizeY = 0.164,
			MinSizeX = 0.22,
			MinSizeY = 0.164,
			MaxSizeX = 0.22,
			MaxSizeY = 0.164,
			CanChangeSize = false,
			Fullscreen = false,
			Title = "Execute",

			DisplayTopbarIcon = true,
			Icon = "rbxassetid://86399617792252",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 20, 1, -20),
			CanDrag = false,

			CanMinimize = false,
			CanMaximize = false,
		}
		local window = windowManager.openWindow(info, "sys")
		local content = OSLayer.WinR:Clone()
		content.Parent = window
		content.Size = UDim2.fromScale(1,1)
		content.Position = UDim2.fromScale(0, 0)
		content.Path.TextBox:CaptureFocus()
		content.Visible = true
		
		local function open()
			local path = content:WaitForChild("Path"):WaitForChild("TextBox").Text
			windowManager.closeWindow(window)
			if path == "cmd" then
				manager.executeFile("System/Terminal")
			else
				manager.executeFile(path, true)
			end
		end
		manager.addTextboxEnterListener(content.Path.TextBox, open)
		content.Open.MouseButton1Click:Connect(open)
	end
end)

function manager.setFileKey(file, key, value): boolean
	if file and key then
		if typeof(file) == "string" then
			local s, f = manager.fileFromPath(file)
			if s and f then
				file = f
			else
				warn("File path not found.")
				return false
			end
		end
		if file["SystemFile"] then
			if file.SystemFile and key == "Name" then
				windowManager.error("Cannot rename a system file.")
				return false
			end
		end
		if key == "Pointer" and file.Type == "Shortcut" then
			local s, r = manager.fileFromPath(value, true)
			if s and r then
				if r.Type == "Shortcut" then
					windowManager.error(`Shortcut pointer can't point to another shortcut.`)
					return false
				end
			end
		end
		local oldName = file["Name"]
		file[key] = value
		if key == "Name" then
			local parent = manager.parent(file)
			if parent then
				file.Path = buildPath(parent.Path, value)
				parent.Content[file.Name] = file
				parent.Content[oldName] = nil
			else
				warn(`[FILE - SET KEY]: File has no parent.`)
				return false
			end
		end
		file.LastModified = os.time()
		if key ~= "Size" then
			manager.updateFileSize(file)
		end
		if file.Id ~= 0 then
			local f = manager.parent(file)
			if f then
				f.LastModified = os.time()
				manager.updateFileSize(f)
			end
		end
		updateDesktop:Fire()
		return true
	else
		return false
	end
end

function manager.stringPath(file)
	return file.Path
end

-- Returns the parent file of a child file, folder or path.
function manager.parent(fileOrPath): Types.File?
	if not fileOrPath then
		warn(`[FILE - PARENT]: File or path is nil.`)
		return nil
	end
	if typeof(fileOrPath) == "string" then
		local s, f = manager.fileFromPath(fileOrPath)
		if s and f then
			fileOrPath = f
		else
			warn(`[FILE - PARENT]: File not found.`)
			return nil
		end
	end
	if fileOrPath["Id"] and fileOrPath["Id"] == 0 then
		return harddrive
	end
	local path = string.split(fileOrPath.Path, "/")
	table.remove(path, #path)
	local parentPath = table.concat(path, "/")
	local s, result = manager.fileFromPath(parentPath)
	if s and result then
		
		return result
	else
		warn(`[FILE - PARENT]: An error occured.`)
		warn(fileOrPath)
		return nil
	end
end

function manager.deepClone(tbl)
	local clone = {}
	for k, v in pairs(tbl) do
		clone[k] = (type(v) == "table") and manager.deepClone(v) or v
	end
	return clone
end

function manager.hasChild(parentFile: File, childFile: Types.File): boolean
	if not parentFile then
		warn(`[FILE - HAS CHILD]: Parent file is nil.`)
		return false
	elseif not childFile then
		warn(`[FILE - HAS CHILD]: Child file is nil.`)
		return false
	end
	for _, child in pairs(parentFile["Content"]) do
		if child == childFile then
			return true
		end
	end
	return false
end

function manager.showProperties(file)
	local propertiesInfo: Types.Window = {
		SizeX = 0.2,
		SizeY = 0.4,
		CanDrag = true,
		CanMaximize = false,
		CanChangeSize = false,
		CanMinimize = false,
		Title = "Properties",
		DisplayTopbarIcon = true,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Icon = file["Icon"] or Settings.Icons.Filetypes[file.Type],
	}
	local propertiesWindow = windowManager.openWindow(propertiesInfo, "sys")
	propertiesWindow.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local label = Instance.new("TextBox", propertiesWindow)
	label:AddTag("SystemFont")
	label.TextEditable = false
	label.ClearTextOnFocus = false
	label.Selectable = false
	label.Active = false
	label.RichText = true
	label.MultiLine = true
	label.ShowNativeInput = false
	label.Size = UDim2.fromScale(0.9, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1,1,1)
	label.TextScaled = false
	label.TextSize = 12
	label.Text = ""
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true

	for key, value in pairs(file) do
		if typeof(value) ~= "table" and typeof(value) ~= "function" then

			if key == "Path" or key=="Pointer" or key=="Icon" or key=="Content" then
				label.Text = label.Text .. `<b>{key}: </b>"{value}"\n`
			elseif key == "Size" then
				label.Text = label.Text .. `<b>{key}: </b>{manager.formatSize(value)} ({value} bytes)\n`
			elseif key == "LastModified" then
				label.Text = label.Text .. `<b>{key}: </b>{manager.formatDate(value)}\n`
			elseif key == "Type" and value ~= "Folder" then
				label.Text = label.Text .. `<b>{key}: </b>{value} (.{manager.getShortFiletype(value)})\n`

			else
				label.Text = label.Text .. `<b>{key}: </b>{value}\n`
			end


		end
	end
end


-- Requires 2 paths. Copies the file linked to the first path into the second.
function manager.copyFile(originalPath, toPath): boolean
	print(`[FILE - COPY]: Copying file from "{originalPath}" to "{toPath}"...`)
	local s1, originalFile = manager.fileFromPath(originalPath)
	local s2, toFolder = manager.fileFromPath(toPath)
	if not s1 then
		warn(`[FILE - COPY]: originalPath is invalid: "{originalPath}"`)
		windowManager.error("Directory is invalid.")
		return false
	elseif not s2 then
		warn(`[FILE - COPY]: toPath is invalid: "{toPath}"`)
		windowManager.error("Target Directory does not exist.")
		return false
	elseif toFolder.Type ~= "Folder" then
		warn(`[FILE - COPY]: toPath is not a folder: "{toPath}"`)
		windowManager.error("Target Directory is not a folder.")
		return false
	elseif originalFile["SystemFile"] then
		warn(`[FILE - COPY]: Cannot copy system files.`)
		windowManager.error("Can't duplicate SystemFiles.")
		return false
	end
	
	
	local copy = manager.deepClone(originalFile)
	if not copy then
		warn(`[FILE - COPY]: Failed to clone file.`)
		windowManager.error("Internal error: Failed to duplicate file.")
		return false
	end
	copy.LastModified = os.time()
	copy.SystemFile = false -- Remove an exploit where people can duplicate systemFiles.
	local originalParent = manager.parent(originalFile)
	
	
	local validName = manager.getValidName(toFolder, copy.Name)
	copy.Name = validName
	copy.Path = buildPath(toFolder.Path, validName)
	
	local newContent =  toFolder["Content"]
	newContent[copy.Name] = copy
	manager.setFileKey(toFolder, "Content", newContent)
	manager.updateFileSize(copy)
	manager.assignPaths()
	
	task.wait()
	-- Check
	local originalCheck = manager.hasChild(originalParent, originalFile)
	local cloneCheck = manager.hasChild(toFolder, copy)
	
	if originalCheck and cloneCheck then
		print(`[FILE - COPY]: File copied successfully.`)
		updateDesktop:Fire()
		return true
	else
		windowManager.error("An interal error occured.")
		warn(`[FILE - COPY]: File copy failed. Reason: `)
		warn(`=> Check failed. Original File: {originalCheck and "Exists ✅" or "Does not exist ❌"}; Copied File: {cloneCheck and "Exists ✅" or "Does not exist ❌"}`)
		return false
	end
end

function manager.hasChildbyName(file, name)
	if not file then
		warn(`[FILE - HasChildByName]: Invalid file.`)
		warn(file, name)
		return false
	end
	for _, child in pairs(file.Content) do
		if child.Name == name then
			return true
		end
	end
	return false
end

function manager.moveFile(fromPath, toPath)
	print(`Moving file "{fromPath}" to folder "{toPath}"...`)
	local exists, fromFile = manager.fileFromPath(fromPath)
	if exists and fromFile then
		if not fromFile["SystemFile"] then
			local copied = manager.copyFile(fromPath, toPath)
			if not copied then 
				warn(`Copying the file failed.`)
				windowManager.error("An internal error occured. Error: moveFile.copyFailed")
				return false
			end
			local deleted = manager.deleteFile(fromPath)
			if not deleted then
				warn(`Deleting the original file failed.`)
				windowManager.error("An internal error occured. Error: moveFile.deleteFailed")
				return false
			end
			updateDesktop:Fire()
			return copied and deleted
		else
			windowManager.error("Cannot move a SystemFile.")
			return false
		end
	else
		windowManager.error("Invalid directory.")
		warn(`[FILE - MOVE]: File "{fromPath}" not found.`)
		return false
	end
end

-- Deletes a specified file or path.
function manager.deleteFile(fileOrPath: Types.File | string): boolean
	if not fileOrPath then
		warn("[FILE - DELETE]: Invalid argument #1: fileOrPath is nil.")
		return false
	end

	local file: Types.File?
	if typeof(fileOrPath) == "string" then
		local success, result = manager.fileFromPath(fileOrPath)
		if not success or not result then
			warn(`[FILE - DELETE]: Directory "{fileOrPath}" is invalid.`)
			return false
		end
		file = result
	else
		file = fileOrPath
	end

	if not file then
		warn("[FILE - DELETE]: File is nil.")
		return false
	end

	-- block all system files
	if file.SystemFile then
		windowManager.error("Cannot delete a SystemFile.")
		return false
	end

	local parentFolder = manager.parent(file)
	if not parentFolder or not parentFolder.Content then
		warn("[FILE - DELETE]: Parent folder not found.")
		return false
	end

	if not parentFolder.Content[file.Name] then
		warn(`[FILE - DELETE]: File does not exist in parent. File: "{file.Path}"`)
		return false
	end

	parentFolder.Content[file.Name] = nil
	parentFolder.LastModified = os.time()
	manager.updateFileSize(parentFolder)

	print(`Successfully deleted "{file.Name}".`)
	updateDesktop:Fire()
	return true
end


function manager.assignPaths()

	local function recursive(file: Types.File, currentPath: string)
		-- Assign path to this file/folder
		file.Path = currentPath
		
		-- If it's a folder, recurse into its contents
		if file.Type == "Folder" and file.Content then
			for _, child in pairs(file.Content) do
				recursive(child, currentPath .. "/" .. child.Name)
			end
		end
	end

	for _, file in pairs(harddrive.Content) do
		recursive(file, file.Name)
	end
end

function manager.read(file, key, default)
	if file and key then
		if file[key] then
			return file[key]
		else
			return default
		end
	else
		return default
	end
end

--[[
	Returns a <strong>File</strong> from a specified <strong>path</strong>.
	
	```
	<code>
	local path = "System/Terminal"
	local file = manager.file(path)
	</code>
	```
]]

local function loop(t: {[any]: any}, cond: (e: any) -> boolean): any
	for key, value in pairs(t) do
		if cond(value) then
			return value
		end
	end
end

function manager.file(path: string, silent: boolean?): Types.File?
	local function WARN(msg) if not silent then warn("[FILE]: " .. msg) end return nil end
	if not path then return WARN("Path is nil.") end
	if path == "" then return harddrive end
	local steps, file = string.split(path, "/"), harddrive
	for _, name in ipairs(steps) do
		if not file or not file["Content"] or file["Type"] ~= "Folder" then return WARN(`{name} is not a folder.`) end
		file = file.Content[name] or loop(file.Content, function(e) return e["Name"] == name end) or nil
	end
	return file
end

@deprecated function manager.fileFromPath(filePath: string, silent: boolean?): (boolean, File)
	local function WARN(msg)
		if not silent then
			warn(msg)
		end
	end
	-- Check if filePath exists
	if filePath == nil then
		WARN("[FILE - fileFromPath]: filePath is nil.")
		WARN(debug.traceback("", 2))
		return false, nil
	end
	-- Check if filePath is a string
	if typeof(filePath) ~= "string" then
		WARN("[FILE - fileFromPath]: filePath is not a string.")
		WARN(debug.traceback("", 2))
		return false, nil
	end
	
	-- Instant return for harddrive
	if filePath == "" then return true, harddrive end

	-- Quick return function
	local function childByName(f, n): Types.File?
		for _, child in pairs(f.Content) do
			if child.Name == n then
				return child
			end
		end
		return nil
	end

	local parts = string.split(filePath, "/")
	local currentFile: File? = harddrive

	for _, part in ipairs(parts) do
		if not currentFile or not currentFile.Content then
			WARN(`[FILE - fileFromPath]: "{part}" is not inside a folder.`)
			return false, nil
		end

		local nextFile = childByName(currentFile, part)
		if not nextFile then
			WARN(`[FILE - fileFromPath]: "{currentFile.Path}" has no child "{part}"`)
			return false, nil
		end

		currentFile = nextFile
	end

	return true, currentFile
end

return manager
