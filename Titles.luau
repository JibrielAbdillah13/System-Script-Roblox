-- StarterPlayerScripts/TerlaClient/Titles

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

local TitleAssets = ReplicatedStorage:FindFirstChild("TitleAssets")
if not TitleAssets then return end

local TEMPLATE = TitleAssets:FindFirstChild("OverheadTitlesTemplate")
if not TEMPLATE then return end

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local isTablet = UserInputService.TouchEnabled and UserInputService.KeyboardEnabled

local Config = {
	TextSize = isMobile and 14 or 18,
	MaxLabelWidth = isMobile and 200 or 350,
	MaxNameLength = isMobile and 14 or 22,
	BillboardSize = isMobile and UDim2.new(5, 0, 2, 0) or UDim2.new(7, 0, 2, 0),
	StudsOffset = isMobile and Vector3.new(0, 0.1, 0) or Vector3.new(0, 0, 0),
	Padding = 2,
	LineSpacing = isMobile and -1 or 0,
	Line3TopOffset = isMobile and -6 or -4,
	FrameHeight = isMobile and 18 or 24,
	VerifiedIconSize = isMobile and 14 or 18,
	MaxVisibleDistance = 70,
	UpdateThrottle = 0.1,
	ForceRefreshInterval = 2,
	DeviceWaitTimeout = 3,
}

local gradientData = { Roles = {}, SummitTitles = {} }
local HIDE_SUMMIT_VALUE_CONFIG = {}
local SummitDrivers = {}
local TitlesHidden = false
local labelSizeCache = {}
local lastUpdateTime = {}
local lastForceRefresh = {}
local refreshTitle
local pendingDeviceRefresh = {}

local function getSummitFallbackColor(summitTitle)
	local colors = {
		["Beginner"] = Color3.fromRGB(182, 255, 197),
		["Novice"] = Color3.fromRGB(120, 220, 255),
		["Rookie"] = Color3.fromRGB(255, 205, 120),
		["Veteran"] = Color3.fromRGB(255, 150, 60),
		["Majestic"] = Color3.fromRGB(255, 100, 100),
		["True Warrior"] = Color3.fromRGB(170, 0, 255),
		["Valley Explorer"] = Color3.fromRGB(255, 255, 102),
	}

	local fallback = colors[summitTitle]
	if not fallback then
		for key, color in pairs(colors) do
			if summitTitle:find(key:match("^(%w+)")) then
				return color
			end
		end
	end

	return fallback or Color3.new(1, 1, 1)
end

local function getRoleSequence(roleName)
	local d = gradientData.Roles and gradientData.Roles[roleName]
	if not d then return nil end

	local kps = {}
	for _, kp in ipairs(d.Keypoints or {}) do
		local c = kp.Color
		if c then
			table.insert(kps, ColorSequenceKeypoint.new(
				kp.Offset or 0,
				Color3.new((c.R or 255) / 255, (c.G or 255) / 255, (c.B or 255) / 255)
				))
		end
	end

	return #kps > 0 and ColorSequence.new(kps) or nil
end

local function getRoleSpeed(roleName)
	local d = gradientData.Roles and gradientData.Roles[roleName]
	return (d and d.Speed) or 24
end

local function getSummitTitleSequence(summitTitle)
	local d = gradientData.SummitTitles and gradientData.SummitTitles[summitTitle]

	if not d then
		local fallbackTitle = summitTitle:gsub("Ardace", "Summit"):gsub("Destination", "Summit"):gsub("Race", "Summit")
		d = gradientData.SummitTitles and gradientData.SummitTitles[fallbackTitle]
	end

	if not d then return nil end

	local kps = {}
	for _, kp in ipairs(d.Keypoints or {}) do
		local c = kp.Color
		if c then
			table.insert(kps, ColorSequenceKeypoint.new(
				kp.Offset or 0,
				Color3.new((c.R or 255) / 255, (c.G or 255) / 255, (c.B or 255) / 255)
				))
		end
	end

	return #kps > 0 and ColorSequence.new(kps) or nil
end

local function getSummitTitleSpeed(summitTitle)
	local d = gradientData.SummitTitles and gradientData.SummitTitles[summitTitle]

	if not d then
		local fallbackTitle = summitTitle:gsub("Ardace", "Summit"):gsub("Destination", "Summit"):gsub("Race", "Summit")
		d = gradientData.SummitTitles and gradientData.SummitTitles[fallbackTitle]
	end

	return (d and d.Speed) or 24
end

local function ensureGradient(label)
	local g = label:FindFirstChildOfClass("UIGradient")
	if not g then
		g = Instance.new("UIGradient")
		g.Name = "AnimatedGradient"
		g.Rotation = 0
		g.Parent = label
	end
	return g
end

local function stopGradient(label)
	local g = label and label:FindFirstChildOfClass("UIGradient")
	if g then g.Enabled = false end
end

local function cleanupDriverFor(bill)
	local drv = SummitDrivers[bill]
	if drv then
		if drv.con then
			pcall(function() drv.con:Disconnect() end)
		end
		SummitDrivers[bill] = nil
		bill:SetAttribute("__SyncedMonitored", nil)
	end
end

local function monitorBillboardLifetime(bill)
	if bill:GetAttribute("__SyncedMonitored") then return end
	bill:SetAttribute("__SyncedMonitored", true)

	bill.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanupDriverFor(bill)
		end
	end)
end

local function applySummitGradientSynced(bill, labels, summitTitle)
	monitorBillboardLifetime(bill)

	local seq = getSummitTitleSequence(summitTitle)
	local speed = getSummitTitleSpeed(summitTitle)

	if not seq then
		for _, lbl in ipairs(labels) do
			if lbl then
				stopGradient(lbl)
				lbl.TextColor3 = getSummitFallbackColor(summitTitle)
				lbl.Visible = true
			end
		end
		cleanupDriverFor(bill)
		return
	end

	local drv = SummitDrivers[bill]
	if not drv then
		drv = { angle = 0, speed = speed, list = {} }
		SummitDrivers[bill] = drv
		drv.con = RunService.Heartbeat:Connect(function(dt)
			if not bill.Parent then
				cleanupDriverFor(bill)
				return
			end
			drv.angle = (drv.angle + (drv.speed or 24) * dt) % 360
			for i = #drv.list, 1, -1 do
				local item = drv.list[i]
				if not (item.label and item.label.Parent and item.grad and item.grad.Parent == item.label) then
					table.remove(drv.list, i)
				else
					item.grad.Rotation = drv.angle
				end
			end
		end)
	else
		drv.speed = speed
	end

	for _, lbl in ipairs(labels) do
		if lbl then
			local g = ensureGradient(lbl)
			g.Color = seq
			g.Enabled = true
			lbl.Visible = true

			local already = false
			for _, it in ipairs(drv.list) do
				if it.label == lbl then
					already = true
					it.grad = g
					break
				end
			end
			if not already then
				table.insert(drv.list, { label = lbl, grad = g })
			end
		end
	end
end

local function startRoleGradient(label, roleTitle)
	if not label then return end

	local token = (label:GetAttribute("RoleGradToken") or 0) + 1
	label:SetAttribute("RoleGradToken", token)

	local seq = getRoleSequence(roleTitle)
	local speed = getRoleSpeed(roleTitle)

	if not seq then
		stopGradient(label)
		label.Visible = true
		return
	end

	local g = ensureGradient(label)
	g.Color = seq
	g.Enabled = true

	task.spawn(function()
		local my = token
		while label.Parent and label:GetAttribute("RoleGradToken") == my do
			pcall(function()
				g.Rotation = (g.Rotation + speed * task.wait()) % 360
			end)
		end
	end)
end

local function setupLabel(label)
	if not label then return end
	label.TextScaled = false
	label.TextSize = Config.TextSize
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Visible = true
end

local function truncateText(text, maxLength)
	if not text then return "" end
	if #text <= maxLength then return text end
	return text:sub(1, maxLength - 2) .. ".."
end

local function fitLabelX(label, forceCenter)
	if not label then return end

	local cacheKey = label:GetFullName() .. "_" .. label.Text
	local cached = labelSizeCache[cacheKey]

	if cached and (tick() - cached.time) < 0.5 then
		label.Size = cached.size
		return
	end

	label.TextWrapped = false

	local targetWidth = 0
	local bounds = label.TextBounds

	if bounds and bounds.X > 0 then
		targetWidth = math.ceil(bounds.X)
	else
		local success, size = pcall(function()
			return TextService:GetTextSize(
				label.Text,
				label.TextSize,
				label.Font,
				Vector2.new(10000, label.AbsoluteSize.Y > 0 and label.AbsoluteSize.Y or 24)
			)
		end)

		if success then
			targetWidth = math.ceil(size.X)
		else
			targetWidth = 100
		end
	end

	targetWidth = math.min(targetWidth, Config.MaxLabelWidth)
	targetWidth = math.max(targetWidth, 10)

	local newSize = UDim2.new(0, targetWidth, label.Size.Y.Scale, label.Size.Y.Offset)
	label.Size = newSize

	labelSizeCache[cacheKey] = {
		size = newSize,
		time = tick()
	}

	if forceCenter then
		label.Position = UDim2.new(0.5, -targetWidth/2, label.Position.Y.Scale, label.Position.Y.Offset)
		label.AnchorPoint = Vector2.new(0, 0.5)
	end
end

local function adjustContainerSpacing(container)
	if not container then return end

	local listLayout = container:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		listLayout.Padding = UDim.new(0, Config.LineSpacing)
		listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	end

	local padding = container:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingTop = UDim.new(0, Config.Padding)
		padding.PaddingBottom = UDim.new(0, Config.Padding)
		padding.PaddingLeft = UDim.new(0, Config.Padding)
		padding.PaddingRight = UDim.new(0, Config.Padding)
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") then
			if child.Name == "Line5" then --asalnya3
				local existingPadding = child:FindFirstChildOfClass("UIPadding")
				if not existingPadding then
					existingPadding = Instance.new("UIPadding")
					existingPadding.Parent = child
				end
				existingPadding.PaddingTop = UDim.new(0, Config.Line3TopOffset)
			else
				child.Size = UDim2.new(1, 0, 0, Config.FrameHeight)
			end

			local nestedLayout = child:FindFirstChildOfClass("UIListLayout")
			if nestedLayout then
				nestedLayout.Padding = UDim.new(0, 2)
				nestedLayout.FillDirection = Enum.FillDirection.Horizontal
				nestedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				nestedLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			end
		end
	end
end

local function cleanupDuplicates(character)
	if not character or not character.Parent then return end

	local list = {}
	local function scan(parent)
		if not parent then return end
		for _, ch in ipairs(parent:GetChildren()) do
			if ch:IsA("BillboardGui") and ch.Name == "OverheadTitles" then
				table.insert(list, ch)
			end
		end
	end

	scan(character:FindFirstChild("Head"))
	scan(character)

	table.sort(list, function(a, b)
		return (a:GetAttribute("CreationTime") or 0) > (b:GetAttribute("CreationTime") or 0)
	end)

	for i = 2, #list do
		pcall(function() list[i]:Destroy() end)
	end
end

local function forceCreateTitle(character)
	if not character or not character.Parent then return nil end
	cleanupDuplicates(character)

	local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 2)
	if not head then return nil end

	local bill = TEMPLATE:Clone()
	bill.Name = "OverheadTitles"
	bill.AlwaysOnTop = true
	bill.Size = Config.BillboardSize
	bill.StudsOffsetWorldSpace = Config.StudsOffset
	bill.ExtentsOffsetWorldSpace = Vector3.new(0, 0, 0)
	bill.MaxDistance = Config.MaxVisibleDistance
	bill.Enabled = not TitlesHidden
	bill:SetAttribute("CreationTime", tick())

	local container = bill:FindFirstChild("Container")
	if container then
		adjustContainerSpacing(container)
		container.Position = UDim2.new(0, 0, 0, 0)
		container.AnchorPoint = Vector2.new(0, 0)
	end

	bill.Parent = head

	return bill
end

local function ensureTitle(character)
	if not character or not character.Parent then return nil end
	cleanupDuplicates(character)

	local head = character:FindFirstChild("Head")
	local bill = head and head:FindFirstChild("OverheadTitles")

	if bill and bill:IsA("BillboardGui") then
		bill.AlwaysOnTop = true
		bill.Size = Config.BillboardSize
		bill.StudsOffsetWorldSpace = Config.StudsOffset
		bill.ExtentsOffsetWorldSpace = Vector3.new(0, 0, 0)
		bill.MaxDistance = Config.MaxVisibleDistance

		local container = bill:FindFirstChild("Container")
		if container then
			adjustContainerSpacing(container)
			container.Position = UDim2.new(0, 0, 0, 0)
			container.AnchorPoint = Vector2.new(0, 0)
		end

		return bill
	end

	return forceCreateTitle(character)
end

local function waitForDeviceIcon(plr, timeout)
	timeout = timeout or Config.DeviceWaitTimeout
	local startTime = tick()

	while (tick() - startTime) < timeout do
		local icon = plr:GetAttribute("DeviceIcon")
		if icon and icon ~= "" and icon ~= "?" and icon ~= "❓" then
			return icon
		end
		task.wait(0.1)
	end

	return "💻"
end

local function scheduleDeviceRefresh(plr)
	if pendingDeviceRefresh[plr] then return end

	pendingDeviceRefresh[plr] = true

	task.delay(2, function()
		if not plr or not plr.Parent then
			pendingDeviceRefresh[plr] = nil
			return
		end

		local icon = plr:GetAttribute("DeviceIcon")
		if icon and icon ~= "" and icon ~= "?" and icon ~= "❓" then
			refreshTitle(plr)
		end

		pendingDeviceRefresh[plr] = nil
	end)
end

function refreshTitle(plr)
	if not plr or not plr.Parent then return false end

	local char = plr.Character
	if not char or not char.Parent then return false end

	local bill = ensureTitle(char)
	if not bill then return false end

	local container = bill:FindFirstChild("Container")
	if not container then return false end

	adjustContainerSpacing(container)

	local line2Frame = container:FindFirstChild("Line2")--done ganti
	local line3Frame = container:FindFirstChild("Line3")
	local emoteLabel = line2Frame and line2Frame:FindFirstChild("Emote")
	local titleLabel = line3Frame and line3Frame:FindFirstChild("Title")

	local line1Frame = container:FindFirstChild("Line1")
	local line4Frame = container:FindFirstChild("Line4")
	local roleTitleLabel = line1Frame and line1Frame:FindFirstChild("RoleTitle")--done
	local playerNameLabel = line4Frame and line4Frame:FindFirstChild("PlayerName") --done
	local verifiedIcon = line4Frame and line4Frame:FindFirstChild("VerifiedIcon")

	if line4Frame and not verifiedIcon then
		verifiedIcon = Instance.new("ImageLabel")
		verifiedIcon.Name = "VerifiedIcon"
		verifiedIcon.Size = UDim2.new(0, Config.VerifiedIconSize, 0, Config.VerifiedIconSize)
		verifiedIcon.BackgroundTransparency = 1
		verifiedIcon.Image = "rbxassetid://84384980082325"
		verifiedIcon.Visible = false
		verifiedIcon.LayoutOrder = 999
		verifiedIcon.Parent = line4Frame
	end

	local line5Frame = container:FindFirstChild("Line5")
	local line5Label = line5Frame

	if titleLabel then setupLabel(titleLabel) end
	if emoteLabel then setupLabel(emoteLabel) end
	if roleTitleLabel then setupLabel(roleTitleLabel) end
	if playerNameLabel then setupLabel(playerNameLabel) end
	if line5Label then setupLabel(line5Label) end

	local totalSummit = plr:GetAttribute("SummitNumber") or 0
	local roleTitle = plr:GetAttribute("RoleTitle") or ""
	local secondaryRole = plr:GetAttribute("SecondaryRole") or ""
	local combinedRoleText = plr:GetAttribute("CombinedRoleText") or ""
	local summitTitle = plr:GetAttribute("SummitTitle") or "Beginner"
	local flag = plr:GetAttribute("PlayerFlag") or "🌐"
	local deviceIcon = plr:GetAttribute("DeviceIcon")
	local isVerified = plr:GetAttribute("IsVerified") == true
	local verifiedId = plr:GetAttribute("VerifiedIconId") or "rbxassetid://84384980082325"
	local termName = plr:GetAttribute("TerminologyName") or "Summit"
	local rawPlayerName = plr:GetAttribute("OverheadNameText") or plr.DisplayName or plr.Name
	local playerName = truncateText(rawPlayerName, Config.MaxNameLength)

	if not deviceIcon or deviceIcon == "" or deviceIcon == "?" or deviceIcon == "❓" then
		deviceIcon = "💻"
		scheduleDeviceRefresh(plr)
	end

	if titleLabel then
		local titleText = summitTitle
		titleLabel.Text = isMobile and truncateText(titleText, 20) or titleText
		titleLabel.Visible = true
		titleLabel.TextXAlignment = Enum.TextXAlignment.Center
		fitLabelX(titleLabel)
	end

	if emoteLabel then
		emoteLabel.Text = flag .. " " .. deviceIcon
		emoteLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		emoteLabel.Visible = true
		emoteLabel.TextXAlignment = Enum.TextXAlignment.Center
		fitLabelX(emoteLabel)
	end

	if line2Frame then
		line2Frame.Size = UDim2.new(1, 0, 0, Config.FrameHeight)--asalnya line 2 dah done
		line2Frame.Visible = true
	end

	local hasRole = (roleTitle ~= "" or secondaryRole ~= "")
	local hasRoleGradient = roleTitle ~= "" and (getRoleSequence(roleTitle) ~= nil)

	if hasRole then
		if roleTitleLabel then
			local displayText = combinedRoleText ~= "" and combinedRoleText or (roleTitle ~= "" and "[" .. (plr:GetAttribute("RoleDisplayText") or roleTitle) .. "]" or "")
			roleTitleLabel.Text = isMobile and truncateText(displayText, 18) or displayText
			roleTitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			roleTitleLabel.Visible = true
			roleTitleLabel.TextXAlignment = Enum.TextXAlignment.Center
			fitLabelX(roleTitleLabel)

			if hasRoleGradient then
				startRoleGradient(roleTitleLabel, roleTitle)
			else
				stopGradient(roleTitleLabel)
			end
		end

		if playerNameLabel then
			playerNameLabel.Text = playerName
			playerNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			playerNameLabel.Visible = true
			playerNameLabel.TextXAlignment = Enum.TextXAlignment.Center
			fitLabelX(playerNameLabel)
			stopGradient(playerNameLabel)
		end
	else
		if roleTitleLabel then
			roleTitleLabel.Visible = false
			roleTitleLabel.Text = ""
			stopGradient(roleTitleLabel)
		end

		if playerNameLabel then
			playerNameLabel.Text = playerName
			playerNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			playerNameLabel.Visible = true
			playerNameLabel.TextXAlignment = Enum.TextXAlignment.Center
			fitLabelX(playerNameLabel)
			stopGradient(playerNameLabel)
		end
	end

	if line4Frame then
		line4Frame.Size = UDim2.new(1, 0, 0, Config.FrameHeight)
		line4Frame.Visible = true --ntah ini njir
	end

	if verifiedIcon then
		if isVerified then
			verifiedIcon.Image = verifiedId
			verifiedIcon.Visible = true
			verifiedIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
			verifiedIcon.BackgroundTransparency = 1
			verifiedIcon.Size = UDim2.new(0, Config.VerifiedIconSize, 0, Config.VerifiedIconSize)
			verifiedIcon.LayoutOrder = 999
		else
			verifiedIcon.Visible = false
		end
	end

	local shouldHideSummitValue = false
	if roleTitle ~= "" then
		shouldHideSummitValue = HIDE_SUMMIT_VALUE_CONFIG[roleTitle] == true
	end
	if not shouldHideSummitValue and secondaryRole ~= "" then
		shouldHideSummitValue = HIDE_SUMMIT_VALUE_CONFIG[secondaryRole] == true
	end

	if line5Label then
		if shouldHideSummitValue then
			line5Label.Visible = false
			line5Label.Text = ""
			line5Frame.Visible = false
			line5Frame.Size = UDim2.new(1, 0, 0, 0)
			stopGradient(line5Label)
		else
			local summitText = termName .. ": " .. tostring(totalSummit)
			line5Label.Text = summitText
			line5Label.Visible = true
			line5Label.TextXAlignment = Enum.TextXAlignment.Center
			line5Frame.Visible = true
			line5Frame.Size = UDim2.new(1, 0, 0, Config.FrameHeight)
			fitLabelX(line5Label)
		end
	end

	task.defer(function()
		if not plr or not plr.Parent then return end

		local labelsToSync = {}
		if titleLabel and titleLabel.Visible then table.insert(labelsToSync, titleLabel) end
		if line5Label and line5Label.Visible then table.insert(labelsToSync, line5Label) end

		applySummitGradientSynced(bill, labelsToSync, summitTitle)
	end)

	return true
end

local function applyGradientJson(json)
	local ok, decoded = pcall(function() return HttpService:JSONDecode(json) end)
	gradientData = (ok and decoded) or { Roles = {}, SummitTitles = {} }
end

local function applyHideConfigJson(json)
	local ok, decoded = pcall(function() return HttpService:JSONDecode(json) end)
	HIDE_SUMMIT_VALUE_CONFIG = (ok and decoded) or {}
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("TerlaShared", 10)
	if not folder then return end

	local gradValue = folder:WaitForChild("TitleGradientData", 10)
	if gradValue then
		applyGradientJson(gradValue.Value)
		gradValue:GetPropertyChangedSignal("Value"):Connect(function()
			applyGradientJson(gradValue.Value)
			for _, p in ipairs(Players:GetPlayers()) do
				pcall(function() refreshTitle(p) end)
			end
		end)
	end

	local hideValue = folder:FindFirstChild("HideSummitValueConfig")
	if hideValue then
		applyHideConfigJson(hideValue.Value)
		hideValue:GetPropertyChangedSignal("Value"):Connect(function()
			applyHideConfigJson(hideValue.Value)
			for _, p in ipairs(Players:GetPlayers()) do
				pcall(function() refreshTitle(p) end)
			end
		end)
	end
end)

local function updateDistanceBasedVisibility()
	if not camera then
		camera = workspace.CurrentCamera
		if not camera then return end
	end

	if TitlesHidden then return end

	local now = tick()

	for _, player in ipairs(Players:GetPlayers()) do
		if (now - (lastUpdateTime[player] or 0)) < Config.UpdateThrottle then
			continue
		end
		lastUpdateTime[player] = now

		local char = player.Character
		if not char then continue end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end

		local head = char:FindFirstChild("Head")
		if not head then continue end

		local bill = head:FindFirstChild("OverheadTitles")
		if not bill then continue end

		local distance = (camera.CFrame.Position - hrp.Position).Magnitude

		local container = bill:FindFirstChild("Container")
		if not container then continue end

		local line1 = container:FindFirstChild("Line1")
		local line2 = container:FindFirstChild("Line2")
		local line3 = container:FindFirstChild("Line3")
		local line4 = container:FindFirstChild("Line4")
		local line5 = container:FindFirstChild("Line5")

		if distance > Config.MaxVisibleDistance then
			if line1 then line1.Visible = false end
			if line2 then line2.Visible = false end
			if line3 then line3.Visible = false end
			if line4 then line4.Visible = false end
			if line5 then line5.Visible = false end
		else
			if line1 then line1.Visible = true end
			if line2 then line2.Visible = true end
			if line3 then line3.Visible = true end
			if line4 then line4.Visible = true end

			if line5 then 
				local roleTitle = player:GetAttribute("RoleTitle") or ""
				local secondaryRole = player:GetAttribute("SecondaryRole") or ""
				local shouldHideSummit = (roleTitle ~= "" and HIDE_SUMMIT_VALUE_CONFIG[roleTitle] == true) or (secondaryRole ~= "" and HIDE_SUMMIT_VALUE_CONFIG[secondaryRole] == true)
				line5.Visible = not shouldHideSummit
			end
		end
	end
end

local function forceRefreshAll()
	if TitlesHidden then return end

	for _, p in ipairs(Players:GetPlayers()) do
		local now = tick()
		if (now - (lastForceRefresh[p] or 0)) < Config.ForceRefreshInterval then
			continue
		end
		lastForceRefresh[p] = now

		pcall(function()
			if p.Character and p.Character:FindFirstChild("Head") then
				refreshTitle(p)
			end
		end)
	end
end

local function setTitlesHidden(hidden)
	TitlesHidden = hidden
	task.spawn(function()
		for _, p in ipairs(Players:GetPlayers()) do
			pcall(function()
				local char = p.Character
				if not char then return end

				local head = char:FindFirstChild("Head")
				if not head then return end

				for _, obj in ipairs(head:GetChildren()) do
					if obj:IsA("BillboardGui") and obj.Name == "OverheadTitles" then
						obj.Enabled = not hidden
					end
				end
			end)
		end
	end)
end

local function bindHideButton()
	pcall(function()
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		if not pg then return end

		local gui = pg:FindFirstChild("SummitGUI")
		if not gui then return end

		local btn = gui:FindFirstChild("HideButton")
		if not btn or btn:GetAttribute("Bound") then return end

		btn:SetAttribute("Bound", true)
		btn.Text = TitlesHidden and "Show Title" or "Hide Title"

		local debounce = false

		btn.MouseButton1Click:Connect(function()
			if debounce then return end
			debounce = true

			setTitlesHidden(not TitlesHidden)
			btn.Text = TitlesHidden and "Show Title" or "Hide Title"

			task.delay(0.5, function()
				debounce = false
			end)
		end)
	end)
end

local function hookPlayer(plr)
	local cons = {}

	local function onCharacterAdded(char)
		for _, c in ipairs(cons) do
			pcall(function() c:Disconnect() end)
		end
		cons = {}
		cleanupDuplicates(char)

		task.spawn(function()
			local head = char:WaitForChild("Head", 3)
			if not head then return end
			task.wait(0.3)

			task.spawn(function()
				task.wait(1.5)
				local icon = plr:GetAttribute("DeviceIcon")
				if not icon or icon == "" or icon == "?" or icon == "❓" then
					task.wait(2)
					if plr and plr.Parent then
						refreshTitle(plr)
					end
				end
			end)

			local ok, tries = false, 0
			while not ok and tries < 5 and char.Parent and plr.Parent do
				tries += 1
				cleanupDuplicates(char)
				task.wait(0.1)
				ok = refreshTitle(plr)
				if not ok then
					forceCreateTitle(char)
					task.wait(0.2)
					ok = refreshTitle(plr)
				end
				if not ok and tries < 5 then
					task.wait(0.3)
				end
			end
		end)

		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			table.insert(cons, hum.Died:Connect(function()
				task.wait(0.1)
				cleanupDuplicates(char)
			end))
		end

		table.insert(cons, char.ChildAdded:Connect(function(ch)
			if ch.Name == "Head" then
				task.wait(0.1)
				refreshTitle(plr)
			end
		end))
	end

	plr.CharacterAdded:Connect(onCharacterAdded)
	if plr.Character then onCharacterAdded(plr.Character) end

	plr.CharacterRemoving:Connect(function(char)
		local head = char:FindFirstChild("Head")
		if head then
			local bill = head:FindFirstChild("OverheadTitles")
			if bill then cleanupDriverFor(bill) end
		end
		for _, c in ipairs(cons) do
			pcall(function() c:Disconnect() end)
		end
		cons = {}

		for key, _ in pairs(labelSizeCache) do
			if key:find(plr.Name) then
				labelSizeCache[key] = nil
			end
		end

		lastUpdateTime[plr] = nil
		lastForceRefresh[plr] = nil
		pendingDeviceRefresh[plr] = nil
	end)

	local last = 0
	local pendingRefresh = false

	local function onAttr()
		local now = tick()

		if now - last < 0.15 then
			if not pendingRefresh then
				pendingRefresh = true
				task.delay(0.25, function()
					pendingRefresh = false
					if plr and plr.Parent then
						refreshTitle(plr)
					end
				end)
			end
		else
			last = now
			task.defer(function() 
				if plr and plr.Parent then
					refreshTitle(plr) 
				end
			end)
		end
	end

	plr:GetAttributeChangedSignal("RoleTitle"):Connect(onAttr)
	plr:GetAttributeChangedSignal("RoleDisplayText"):Connect(onAttr)
	plr:GetAttributeChangedSignal("SecondaryRole"):Connect(onAttr)
	plr:GetAttributeChangedSignal("SecondaryRoleDisplayText"):Connect(onAttr)
	plr:GetAttributeChangedSignal("CombinedRoleText"):Connect(onAttr)
	plr:GetAttributeChangedSignal("SummitTitle"):Connect(onAttr)
	plr:GetAttributeChangedSignal("OverheadNameText"):Connect(onAttr)
	plr:GetAttributeChangedSignal("SummitNumber"):Connect(onAttr)
	plr:GetAttributeChangedSignal("PlayerFlag"):Connect(onAttr)
	plr:GetAttributeChangedSignal("DeviceIcon"):Connect(onAttr)
	plr:GetAttributeChangedSignal("IsVerified"):Connect(onAttr)
	plr:GetAttributeChangedSignal("VerifiedIconId"):Connect(onAttr)
	plr:GetAttributeChangedSignal("TerminologyName"):Connect(onAttr)
	plr:GetAttributeChangedSignal("ForceRefreshTitles"):Connect(onAttr)

	plr:GetPropertyChangedSignal("DisplayName"):Connect(onAttr)
end

for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end

Players.PlayerAdded:Connect(hookPlayer)

RunService.RenderStepped:Connect(updateDistanceBasedVisibility)

task.spawn(function()
	while true do
		task.wait(Config.ForceRefreshInterval)
		forceRefreshAll()
	end
end)

if LocalPlayer then
	pcall(function()
		if LocalPlayer:FindFirstChild("PlayerGui") then
			bindHideButton()
		end
		LocalPlayer.PlayerGui.ChildAdded:Connect(function(ch)
			if ch.Name == "SummitGUI" then
				task.defer(bindHideButton)
			end
		end)
	end)
end

return true
