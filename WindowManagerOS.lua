--!strict

local runService = game:GetService("RunService")
if not runService:IsClient() then
	warn(`[WindowManager]: Can only be used on the client.`)
	return {}
end

local uis = game:GetService("UserInputService")
local rs = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local player = players.LocalPlayer :: Player
local mouse = player:GetMouse()
local playerGui = player:WaitForChild("PlayerGui")

local screen = playerGui:WaitForChild("Screen") :: ScreenGui
local OSLayer = playerGui:WaitForChild("OSLayer") :: ScreenGui

local canvas = screen:WaitForChild("Canvas") :: Frame
local shortcuts = canvas:WaitForChild("Shortcuts")
local taskbar = canvas:WaitForChild("Taskbar")

local updateDesktop = rs:WaitForChild("UpdateDesktop")
local services = rs:WaitForChild("Services")
local Types = require(services:WaitForChild("Types"))
local Settings = require(services:WaitForChild("Settings"))

local HIGHEST_WINDOWLAYER = 10
local WINDOWS_OPENED = 0

local errors = {}
local errorDefaultSize = UDim2.fromScale(0.257,0.232)
local errorSmallSize = UDim2.fromScale(0.228,0.186)

local manager: Types.WindowManager = {
	windows = {}
} :: Types.WindowManager

local ts = game:GetService("TweenService")
local function qTween(x,y,z)
	if z["GroupTransparency"] and not x:IsA("CanvasGroup") then
		z["GroupTransparency"] = nil
	end
	local t = ts:Create(x,y,z)
	task.spawn(function()
		t:Play()
	end)
	return t
end
local function tbiconfromname(filePath: string): ImageButton?
	for _, icon in ipairs(taskbar:GetChildren()) do
		if icon:IsA("ImageButton") then
			if icon.Name == filePath and not icon:GetAttribute("Pointer") then
				return icon
			end
		end
	end
	return nil
end

local function windowsFromName(name: string)
	local screenCanvas = screen:FindFirstChild("Canvas")
	local variable = {}
	for _, window in pairs(screenCanvas:GetChildren()) do
		if window.Name == name then
			table.insert(variable, window)
		end
	end
	return variable
end

local optionsInterrupted = false

uis.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		optionsInterrupted = true
		local options = OSLayer:FindFirstChild("Options")
		if options and options:IsA("Frame") then
			options.Visible = false
		end
	end
end)

function manager.clearShortcuts()
	for _, child in pairs(shortcuts:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIAspectRatioConstraint") then
			child:Destroy()
		end
	end
end

function manager.openOptions(alloptions: {string}): string?
	optionsInterrupted = false
	local mousePos = uis:GetMouseLocation()
	
	local options = OSLayer:FindFirstChild("Options")
	if options and options:IsA("Frame") then
		options.Position = UDim2.fromOffset(mousePos.X, mousePos.Y)
		options.Visible = true
		
		local choice = nil
		for _, c in pairs(options:GetChildren()) do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
		for _, option in ipairs(alloptions) do
			local btn = Instance.new("TextButton", options)
			btn:AddTag("SystemFont")
			btn.Size = UDim2.new(1, 0, 0, OSLayer.AbsoluteSize.Y / 30)
			btn.BackgroundColor3 = Color3.new(1,1,1)
			btn.Text = option
			btn.MouseButton1Click:Connect(function()
				choice = option
			end)
		end

		while true do
			task.wait()
			if choice or optionsInterrupted then
				break
			end
		end
		options.Visible = false
		return choice
		
	else
		return nil
	end
end

function manager.ShortcutToTaskbar(file: Types.File)
	local fileType = file.Type
	local fileIcon = file["Icon"]
	local icon: string = Settings.Icons.Filetypes[fileType] or fileIcon or ""
	local i = Instance.new("ImageButton", taskbar)
	local aspectRatio = Instance.new("UIAspectRatioConstraint", i)
	i.Image = icon
	i.Name = file.Name
	i:SetAttribute("Pointer", file.Path)
	i.Size = UDim2.fromScale(0.5, 0.5)
	i.BackgroundTransparency = 1
	
	i.MouseButton1Click:Connect(function()
		rs.OpenPath:Fire(file.Path)
	end)

	qTween(i, TweenInfo.new(0.3), {Size = UDim2.fromScale(0.02, 0.55)})
	return i
end



function manager.closeWindows(filePath: string)
	print("Closing " .. filePath)
	local taskbarIcon = tbiconfromname(filePath) --manager.getTaskbarIconFromWindow(canvas.Parent)
	if taskbarIcon then
		taskbarIcon:Destroy()
	end

	-- Close all windows
	local windows = manager.windows[filePath]
	if windows then
		repeat
			for _, window in pairs(windows) do
				local index = table.find(windows, window)
				table.remove(windows, index)
				WINDOWS_OPENED -= 1
				local t = qTween(window, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.fromScale(0, 0), GroupTransparency = 1})
				t.Completed:Once(function() window:Destroy() end)
			end
		until #windows == 0
	end
end

function manager.closeWindow(canvas: Frame)
	
	if not canvas then return end
	local window = canvas.Parent
	if not window or not (window:IsA("CanvasGroup") or window:IsA("Frame")) then return end
	
	local filePath = window:GetAttribute("Path")
	local entry = manager.windows[filePath]
	if entry then
		local index = table.find(entry, window)
		if index then
			table.remove(entry, index)
			WINDOWS_OPENED -= 1
			
			local taskbarIcon = tbiconfromname(filePath) --manager.getTaskbarIconFromWindow(canvas.Parent)
			if taskbarIcon then
				local indicator = taskbarIcon:FindFirstChild("Indicator")
				if indicator and indicator:IsA("TextLabel") then
					local n = tonumber(indicator.Text)
					if n then
						if n > 1 then
							local new = n - 1
							indicator.Text = tostring(new)
							indicator.Visible = n > 1
						else
							taskbarIcon:Destroy()
						end
					end
				else
					warn(`[WindowManager - closeWindow]: Taskbar icon has no indicator.`)
					taskbarIcon:Destroy()
				end
			else
				warn(taskbarIcon)
				warn(canvas)
				warn(taskbar)
				warn(filePath)
				warn(`[WindowManager - closeWindow]: No Taskbar icon found for "{window.Name}"`)
			end
			
			local t = qTween(window, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.fromScale(0, 0), GroupTransparency = 1})
			t.Completed:Once(function() window:Destroy()end)
		else
			warn(`[WindowManager - closeWindow]: No entry index found for "{filePath}"`)
		end
	else
		warn(`[WindowManager - closeWindow]: No entry found for "{filePath}"`)
	end
end

function manager.createShortcut(name, iconPath, path)
	
	local shortcut = Instance.new("TextButton", shortcuts)
	shortcut:AddTag("SystemFont")
	shortcut.Text = ""
	shortcut.BackgroundTransparency = 1
	shortcut:SetAttribute("Path", path)
	shortcut.Name = path
	
	local icon = Instance.new("ImageLabel", shortcut)
	icon.Image = iconPath
	icon.Size = UDim2.fromScale(Settings.Shortcut.IconSize, Settings.Shortcut.IconSize)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	
	local title = Instance.new("TextLabel", shortcut)
	title:AddTag("SystemFont")
	title.Text = name
	title.Size = UDim2.fromScale(1, 0.2)
	title.Position = UDim2.fromScale(0.5, 1)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.TextStrokeTransparency = 0
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Name = "Title"

	local renameBox = Instance.new("TextBox", title)
	renameBox:AddTag("SystemFont")
	renameBox.Size = UDim2.fromScale(1,1)
	renameBox.Position = UDim2.fromScale(0, 0)
	renameBox.BackgroundTransparency = 1
	renameBox.ClearTextOnFocus = false
	renameBox.TextEditable = false
	renameBox.Text = ""
	renameBox.Visible = false
	renameBox.TextColor3 = Color3.new(1,1,1)
	renameBox.TextScaled = true
	renameBox.Name = "Rename"
	
	return shortcut
end

function manager.alert(msg, options): string?
	local info: Types.Window = {
		SizeX = 0.3,
		SizeY = 0.2,
		CanMinimize = false,
		CanMaximize = false,
		Title = "Alert",
		CanChangeSize = false,
		DisplayTopbarIcon = true,
		Icon = "rbxassetid://12533969836",
	}
	local popup = manager.openWindow(info, "sys")
	if not popup then return nil end
	local alertTemplate = OSLayer:FindFirstChild("Alert")
	if alertTemplate and alertTemplate:IsA("Frame") then
		local content = alertTemplate:Clone()
		content.Parent = popup
		content.Size = UDim2.fromScale(1,1)
		content.Position = UDim2.fromScale(0, 0)
		local selection = nil
		local stop = false
		content.Visible = true
		
		local textBox = content:FindFirstChild("TextBox") :: TextBox
		if textBox then
			textBox.Text = msg
		end
		
		local window = popup.Parent
		
		window.TopBar.Right.Close.MouseButton1Click:Connect(function()
			selection = nil
			stop = true
		end)
		
		local default = content.Options.DefaultOption
		for _, option in ipairs(options) do
			local o = default:Clone()
			o.Visible = true
			o.TextLabel.Text = option
			o.Size = UDim2.fromScale(1/#options, 0.551)
			o.Parent = default.Parent
			o.MouseButton1Click:Once(function()
				selection = option
				manager.closeWindow(popup)
				stop = true
			end)
		end
		repeat
			task.wait()
		until selection or stop
		return selection
	end
end

function manager.error(msg)
	local info: Window = {
		SizeX = 0.3,
		SizeY = 0.17,
		CanMinimize = false,
		CanMaximize = false,
		Title = "Error",
		CanChangeSize = false,
		DisplayTopbarIcon = true,
		Icon = "rbxassetid://5198838744",
	}
	local popup = manager.openWindow(info, "sys")
	local textbox = Instance.new("TextBox", popup)
	textbox:AddTag("SystemFont")
	textbox.Text = msg or "Error"
	textbox.BackgroundTransparency = 1
	textbox.TextColor3 = Color3.new(1,1,1)
	textbox.Selectable = false
	textbox.TextEditable = false
	textbox.Active = false
	textbox.ClearTextOnFocus = false
	textbox.Size = UDim2.fromScale(0.9, 0.9)
	textbox.MultiLine = true
	textbox.RichText = true
	textbox.TextWrapped = true
	textbox.TextSize = 12
	popup.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
end

function manager.createTaskbarIcon(window, filePath, iconPath)
	local old = tbiconfromname(filePath)
	if old then
		local indicator = old:FindFirstChild("Indicator")
		if indicator and indicator:IsA("TextLabel") then
			local numberText = tonumber(indicator.Text)
			if numberText then
				local new = numberText + 1
				indicator.Text = tostring(new)
				indicator.Visible = new > 1
			end
			return old
		end
	end
	local icon = Instance.new("ImageButton", taskbar)
	local aspectRatio = Instance.new("UIAspectRatioConstraint", icon)
	icon.Image = iconPath
	icon.Name = filePath
	local w = Instance.new("ObjectValue", icon)
	w.Name = "Window"
	w.Value = window
	local indicator = Instance.new("TextLabel", icon)
	local corner = Instance.new("UICorner", indicator)
	local stroke = Instance.new("UIStroke", indicator)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.new(1,0,0)
	stroke.Thickness = 3
	corner.CornerRadius = UDim.new(1, 0)
	indicator.Name = "Indicator"
	indicator.AnchorPoint = Vector2.new(0, 0)
	indicator.Position = UDim2.fromScale(1, 0)
	indicator.Size = UDim2.fromScale(0, 0)
	indicator.TextSize = 8
	indicator.BackgroundColor3 = Color3.new(1,0,0)
	indicator.Text = "1"
	indicator.Visible = false
	indicator.TextColor3 = Color3.new(1,1,1)
	indicator.AutomaticSize = Enum.AutomaticSize.XY
	
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(0.5, 0.5)
	icon.MouseButton2Click:Connect(function()
		local option = manager.openOptions({"Close"})
		if option == "Close" then
			-- Force stop
			local success = rs.ForceExit:Invoke(window:GetAttribute("Path"), -1)
			-- Close all windows
			manager.closeWindows(filePath)
		end
	end)
	qTween(icon, TweenInfo.new(0.3), {Size = UDim2.fromScale(0.02, 0.55)})
	return icon
end

function manager.newGrid(sections: {string}): Frame
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 0.05)
	frame.Position = UDim2.fromScale(0, 0)
	frame.BackgroundTransparency = 1
	local grid = Instance.new("UIListLayout", frame)
	grid.Padding = UDim.new(0, 0)
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.VerticalAlignment = Enum.VerticalAlignment.Center
	for _, section in ipairs(sections) do
		local sectionFrame = Instance.new("TextLabel", frame)
		sectionFrame:AddTag("SystemFont")
		sectionFrame.Size = UDim2.fromScale(1 / #sections, .55)
		sectionFrame.BackgroundTransparency = 1
		sectionFrame.TextScaled = true
		sectionFrame.Text = section
		sectionFrame.TextColor3 = Color3.new(1,1,1)
	end
	return frame
end

local currentIcon = ""
local function setMouseIcon(dirX, dirY)
	local function setIcon(icon)
		currentIcon = icon
		uis.MouseIcon = icon
		mouse.Icon = icon
	end
	if dirX == 0 and dirY == 0 then
		setIcon("")
	elseif dirY == 0 then
		setIcon("rbxasset://textures/StudioUIEditor/icon_resize2.png")
	elseif dirX == 0 then
		setIcon("rbxasset://textures/StudioUIEditor/icon_resize4.png")
	elseif dirX == dirY then
		setIcon("rbxasset://textures/StudioUIEditor/icon_resize1.png")
	elseif dirX ~= dirY then
		setIcon("rbxasset://textures/StudioUIEditor/icon_resize3.png")
	end
end

game:GetService("RunService").Heartbeat:Connect(function()
	if currentIcon ~= "" then
		uis.MouseIcon = currentIcon
		mouse.Icon = currentIcon
	end
end)

local mouse1 = Enum.UserInputType.MouseButton1

local function makeScalable(window: CanvasGroup, info: Types.Window)
	local mouse, uis = mouse, uis
	local parent = window.Parent :: Frame

	local thickness = info["Thickness"] or 16
	local corner = info["CornerRadius"] or 10
	local minSizeX = info.MinSizeX or 0.1
	local minSizeY = info.MinSizeY or 0.1
	local maxSizeX = info.MaxSizeX or 1
	local maxSizeY = info.MaxSizeY or 1

	local halfT = thickness * 0.5

	local scaling = false
	local dirX, dirY = 0, 0
	local conn

	local accX, accY = 0, 0
	local startMX, startMY
	local sx, sy, px, py
	local parentSize

	local function toScale(u)
		return UDim2.fromScale(
			u.X.Scale + u.X.Offset / parentSize.X,
			u.Y.Scale + u.Y.Offset / parentSize.Y
		)
	end

	local function update()
		if not scaling then return end
		local alt = uis:IsKeyDown(Enum.KeyCode.LeftAlt)
		local dx = (mouse.X - startMX) * -dirX
		local dy = (mouse.Y - startMY) *  dirY
		if alt then
			dx *= 2
			dy *= 2
		end

		accX += dx
		accY += dy

		local cx = math.floor(accX / 2) * 2
		local cy = math.floor(accY / 2) * 2

		accX -= cx
		accY -= cy

		-- Calculate the new potential size
		local newSizeX = sx - cx
		local newSizeY = sy - cy
		
		local minX

		-- Clamp size to min/max values
		newSizeX = math.clamp(newSizeX, minSizeX * parentSize.X, maxSizeX * parentSize.X)
		newSizeY = math.clamp(newSizeY, minSizeY * parentSize.Y, maxSizeY * parentSize.Y)

		-- Determine if the size was clamped
		local clampedX = (newSizeX ~= (sx - cx))
		local clampedY = (newSizeY ~= (sy - cy))

		-- Apply the updated size and position
		if cx ~= 0 or cy ~= 0 then
			window.Size = UDim2.fromOffset(newSizeX, newSizeY)
			if alt then return end
			-- Only update the position if the size wasn't clamped for that axis
			if not clampedX	 then
				window.Position = UDim2.fromOffset(px + cx / 2 * -dirX, window.Position.Y.Offset)
			else
				local clampedDiffX = (sx - cx) - newSizeX
				window.Position = UDim2.fromOffset(px + (cx + clampedDiffX) / 2 * -dirX, window.Position.Y.Offset)
			end

			if not clampedY then
				window.Position = UDim2.fromOffset(window.Position.X.Offset, py + cy / 2 * dirY)
			else
				local clampedDiffY = (sy - cy) - newSizeY
				window.Position = UDim2.fromOffset(window.Position.X.Offset, py + (cy + clampedDiffY) / 2 * dirY)
			end
		end

	end

	local function begin(x, y)
		if scaling then return end

		dirX, dirY = x, y
		parentSize = parent.AbsoluteSize

		accX, accY = 0, 0
		startMX, startMY = mouse.X, mouse.Y

		local s, p = window.Size, window.Position
		sx = s.X.Offset + s.X.Scale * parentSize.X
		sy = s.Y.Offset + s.Y.Scale * parentSize.Y
		px = p.X.Offset + p.X.Scale * parentSize.X
		py = p.Y.Offset + p.Y.Scale * parentSize.Y

		window.Size = UDim2.fromOffset(sx, sy)
		window.Position = UDim2.fromOffset(px, py)

		--window.UIDragDetector.Enabled = false
		setMouseIcon(x, y)

		scaling = true
		conn = mouse.Move:Connect(update)
	end

	local function stop()
		if conn then conn:Disconnect() conn = nil end
		setMouseIcon(0, 0)
		window.Size = toScale(window.Size)
		window.Position = toScale(window.Position)
		scaling = false
	end

	local function hit(mx, my)
		local pos = window.AbsolutePosition
		local size = window.AbsoluteSize

		local lx = mx - pos.X
		local rx = mx - (pos.X + size.X)
		local ty = my - pos.Y
		local by = my - (pos.Y + size.Y)

		if math.abs(lx) <= corner and math.abs(ty) <= corner then return -1,  1 end
		if math.abs(rx) <= corner and math.abs(ty) <= corner then return  1,  1 end
		if math.abs(lx) <= corner and math.abs(by) <= corner then return -1, -1 end
		if math.abs(rx) <= corner and math.abs(by) <= corner then return  1, -1 end

		if math.abs(lx) <= halfT and ty >= -halfT and by <= halfT then return -1, 0 end
		if math.abs(rx) <= halfT and ty >= -halfT and by <= halfT then return  1, 0 end
		if math.abs(ty) <= halfT and lx >= -halfT and rx <= halfT then return  0, 1 end
		if math.abs(by) <= halfT and lx >= -halfT and rx <= halfT then return  0,-1 end

		return 0, 0
	end

	uis.InputBegan:Connect(function(i)
		if i.UserInputType ~= mouse1 then return end
		local x, y = hit(mouse.X, mouse.Y)
		if x ~= 0 or y ~= 0 then
			begin(x, y)
		end
	end)

	uis.InputEnded:Connect(function(i)
		if i.UserInputType == mouse1 and scaling then
			stop()
		end
	end)

	mouse.Move:Connect(function()
		if scaling then return end
		local x, y = hit(mouse.X, mouse.Y)
		if x == 0 and y == 0 then
			--window.UIDragDetector.Enabled = false
			setMouseIcon(0, 0)
			
		else
			setMouseIcon(x, y)
		end
	end)
end

local function getDefaultInfo(info: Types.Window): {[string]: any}
	return {
		SizeX = info["SizeX"] or 0.5,
		SizeY = info["SizeY"] or 0.3,

		MinSizeX = info["MinSizeX"] or 0.2,  -- Default to 20% width
		MinSizeY = info["MinSizeY"] or 0.2,  -- Default to 20% height

		MaxSizeX = info["MaxSizeX"] or 1,    -- Default to 100% width
		MaxSizeY = info["MaxSizeY"] or 1,    -- Default to 100% height

		CanChangeSize = info["CanChangeSize"] == nil and true or info["CanChangeSize"],  -- Default to true if not set
		Fullscreen = info["Fullscreen"] or false,  -- Default to false
		Title = info["Title"] or "Window",  -- Default title is "Window"

		DisplayTopbarIcon = info["DisplayTopbarIcon"] == nil and true or info["DisplayTopbarIcon"],  -- Default to true if not set
		Icon = info["Icon"] or "",  -- Default icon asset ID

		Position = info["Position"] or UDim2.fromScale(0.5, 0.5),  -- Default to center of screen
		AnchorPoint = info["AnchorPoint"] or Vector2.new(0.5, 0.5),  -- Default to center anchor point

		CanDrag = info["CanDrag"] == nil and true or info["CanDrag"],  -- Default to true if not set
		CanMinimize = info["CanMinimize"] == nil and true or info["CanMinimize"],  -- Default to true if not set
		CanMaximize = info["CanMaximize"] == nil and true or info["CanMaximize"],  -- Default to true if not set
	}
end

-- Open a new window
function manager.openWindow(originalInfo: Types.Window, filePath: string, postFirstTween: (window: CanvasGroup | Frame) -> ()?): (Frame & {Parent: Frame | CanvasGroup})?
	
	if not originalInfo then return nil end
	if not filePath then return nil end
	
	local timestamp = tick()
	
	local function createWindow()
	
		-- Set default values
		local info = getDefaultInfo(originalInfo)

		local windowTemplate = game:GetService("ReplicatedStorage"):WaitForChild("Gui"):WaitForChild("PerformanceWindow")
		local window = windowTemplate:Clone()
		local topBar = window:WaitForChild("TopBar")
		local minimize = topBar.Right:WaitForChild("Minimize")
		local maximize = topBar.Right:WaitForChild("Maximize")
		
		window:SetAttribute("Path", filePath)
		
		local offsetX = math.random(1, 15) / 100
		local offsetY = math.random(1, 15) / 100
		if math.random(0, 1) == 0 then offsetX = -offsetX end
		if math.random(0, 1) == 0 then offsetY = -offsetY end

		window.ZIndex = HIGHEST_WINDOWLAYER + 1
		window.Name = info.Title
		window.Parent = canvas
		window.Visible = true
		window.Position = info.Position
		if info.CanDrag then
			window.Position += UDim2.fromScale(offsetX, offsetY)
		end
		
		window:SetAttribute("IsMinimized", false)
		window:SetAttribute("IsMaximized", false)
		
		
		
		window.AnchorPoint = info.AnchorPoint
		window.Size = UDim2.fromScale(info.SizeX * 0.9, info.SizeY * 0.9)
		if window:IsA("CanvasGroup") then
			window.GroupTransparency = 1
		end
		
		local startTween = qTween(window, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {GroupTransparency = 0, Size = UDim2.fromScale(info.SizeX, info.SizeY)})
		local dragDetector = window:WaitForChild("UIDragDetector")
		dragDetector.Enabled = false

		startTween.Completed:Once(function(state)
			if Enum.PlaybackState.Completed == state then
				if info.CanChangeSize then
					makeScalable(window, info :: Types.Window)
				end
				
				if info.CanDrag then

					local draggableArea = topBar:WaitForChild("DraggableArea")
					draggableArea.Active = true

					local inArea, dragging = false, false

					dragDetector.DragEnd:Connect(function()
						dragging = false

						if not inArea then dragDetector.Enabled = false end
					end)

					dragDetector.DragStart:Connect(function()
						dragging = true
						HIGHEST_WINDOWLAYER += 1

						window.ZIndex = HIGHEST_WINDOWLAYER
					end)

					draggableArea.MouseEnter:Connect(function() 

						dragDetector.Enabled = true
						inArea = true
					end)

					draggableArea.MouseLeave:Connect(function() 

						inArea = false
						if not dragging then dragDetector.Enabled = false end
					end)

				end
				
				if postFirstTween then
					postFirstTween(window:FindFirstChild("Canvas"))
				end
			end
		end)
		
		topBar.Left.Icon.Visible = info["DisplayTopbarIcon"] and true or false
		topBar.Left.Icon:SetAttribute("Tooltip", info.Title)
		topBar.Left.Icon.Image = info.Icon
		topBar.Left.Title.Text = info.Title
		
		minimize.Visible = info["CanMinimize"] and true or false
		maximize.Visible = info["CanMaximize"] and true or false
		
		local taskbarIcon = manager.createTaskbarIcon(window, filePath, info.Icon)
		taskbarIcon.MouseButton1Click:Connect(function()
			if window:GetAttribute("IsMinimized") then
				window:SetAttribute("IsMinimized", false)
				qTween(window, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(info.SizeX, info.SizeY), GroupTransparency = 0})
			elseif window:GetAttribute("IsMaximized") then
				window:SetAttribute("IsMaximized", false)
				qTween(window, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(info.SizeX, info.SizeY), GroupTransparency = 0})
			elseif info.CanMinimize then
				window:SetAttribute("IsMinimized", true)
				qTween(window, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(0, 0), GroupTransparency = 1})
			else
				window:SetAttribute("IsMinimized", false)
				window:SetAttribute("IsMaximized", false)
				qTween(window, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(info.SizeX, info.SizeY), GroupTransparency = 0})
			end
		end)
		
		if info.CanMinimize then
			minimize.MouseButton1Click:Connect(function()
				qTween(window, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(0, 0), GroupTransparency = 1})
				window:SetAttribute("IsMinimized", true)
				window:SetAttribute("IsMaximized", false)
			end)
		else
			minimize.Visible = false
		end
		
		if info.CanMaximize then
			maximize.MouseButton1Click:Connect(function()
				if window:GetAttribute("IsMaximized") then
					window:SetAttribute("IsMaximized", false)
					qTween(window, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(info.SizeX, info.SizeY), Position = UDim2.fromScale(0.5, 0.5), GroupTransparency = 0})
				else
					qTween(window, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(1, 1 - taskbar.Size.Y.Scale), Position = UDim2.fromScale(0.5, 0.5 - taskbar.Size.Y.Scale / 2), GroupTransparency = 0})
					window:SetAttribute("IsMinimized", false)
					window:SetAttribute("IsMaximized", true)
				end

			end)
		else
			maximize.Visible = false
		end
		
		topBar.Right.Close.MouseButton1Click:Connect(function()
			manager.closeWindow(window.Canvas)
		end)
		
		window.Toolbar.NewButton.Event:Connect(function(text, onClick)
			print("New toolbar btn")
			window.Toolbar.Visible = true
			local button = Instance.new("TextButton", window.Toolbar.Left)
			button:AddTag("SystemFont")
			button.Size = UDim2.fromScale(0.1, 1)
			button.Name = text
			button.Text = text
			button.TextScaled = true
			button.TextColor3 = Color3.new(1,1,1)
			button.BackgroundTransparency = 0.6
			button.BackgroundColor3 = Color3.new(0,0,0)
			
			button.MouseButton1Click:Connect(function()
				onClick()
			end)
		end)
		
		-- Finalize window
		WINDOWS_OPENED += 1
		local entry = manager.windows[filePath]
		if not entry then 
			-- Window is new
			manager.windows[filePath] = {[1] = window}
			entry = manager.windows[filePath]
		else
			table.insert(entry, window)
		end

		-- hard cap
		if #entry > 32 then
			local firstWindow = entry[1]
			if firstWindow then
				local firstCanvas = firstWindow:FindFirstChild("Canvas")
				if firstCanvas and (firstCanvas:IsA("Frame") or firstCanvas:IsA("ScrollingFrame")) then
					manager.closeWindow(firstCanvas)
				else
					warn(firstWindow)
					warn(`[WindowManager - openWindow]: Oldest window of "{filePath}" not found.`)
				end
			else
				warn(`[WindowManager - openWindow]: Oldest window of "{filePath}" not found.`)
			end
		end
		return window
	end
	
	
	local window = createWindow()
	local endTime = tick() - timestamp
	print(`Window created. Time: {math.round(endTime * 10000) / 10000}s`)
	
	return window:FindFirstChild("Canvas")
end

return manager
