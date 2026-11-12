--!strict
-- Mounts settings controls using the persistent settings API.
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
local Scope = require(game:GetService("ReplicatedStorage").Shared.Utils.Scope)
local ClientState = require(clientRoot.ClientState)
local Settings = require(clientRoot.Controllers.SettingsController)
local Screen={Name="Settings",GuiName="SettingsUI"}
function Screen.Mount(gui: ScreenGui,router: any)
local scope=Scope.new()
--!strict
-- Mounts the settings screen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local SettingsDefinitions = require(ReplicatedStorage.Shared.Config.SettingsDefinitions)

local PlayerRemote = ReplicatedStorage:WaitForChild("Remotes",10):WaitForChild("Settings",10)
local GetAllSettings = PlayerRemote:WaitForChild("GetAllSettings",10)
local SetSetting = PlayerRemote:WaitForChild("SetSetting",10)

local Icon = nil
pcall(function()
	Icon = require(ReplicatedStorage.Packages.TopbarPlus:WaitForChild("Icon",10))
end)

local CONFIG = require(ReplicatedStorage.Shared.Config.SettingsUIConfig)

local function withDelay(info: TweenInfo, delayTime: number): TweenInfo
	return TweenInfo.new(info.Time, info.EasingStyle, info.EasingDirection, info.RepeatCount, info.Reverses, delayTime)
end

local function playTween(obj: Instance, info: TweenInfo, props: any): Tween
    if Settings.Get("ReduceMotion") then info = TweenInfo.new(0) end
	local tween = scope:Tween(obj, info, props)
	tween:Play()
	return tween
end

local function modifyColor(color: Color3, amount: number): Color3
	return Color3.new(
		math.clamp(color.R + (amount / 255), 0, 1),
		math.clamp(color.G + (amount / 255), 0, 1),
		math.clamp(color.B + (amount / 255), 0, 1)
	)
end

local function createRipple(element: GuiObject, inputPos: Vector3)
    if Settings.Get("ReduceMotion") then return end
	element.ClipsDescendants = true
	local ripple = Instance.new("Frame")
	ripple.BackgroundColor3 = Color3.new(1, 1, 1)
	ripple.BackgroundTransparency = 0.6
	ripple.BorderSizePixel = 0
	ripple.Position = UDim2.new(0, inputPos.X - element.AbsolutePosition.X, 0, inputPos.Y - element.AbsolutePosition.Y)
	ripple.Size = UDim2.new(0, 0, 0, 0)
	ripple.AnchorPoint = Vector2.new(0.5, 0.5)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ripple
	ripple.Parent = element

	local maxDist = math.max(element.AbsoluteSize.X, element.AbsoluteSize.Y) * 1.8
	local tween = playTween(ripple, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, maxDist, 0, maxDist),
		BackgroundTransparency = 1,
	})

	scope:Once(tween.Completed, function()
		ripple:Destroy()
	end)
end

local function bindInteractiveScale(element: GuiObject, hoverScale: number, clickScale: number)
	local scale = element:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = element

	scope:Connect(element.MouseEnter, function()
		playTween(scale, CONFIG.hoverTween, { Scale = hoverScale })
	end)

	scope:Connect(element.MouseLeave, function()
		playTween(scale, CONFIG.hoverTween, { Scale = 1 })
	end)

	scope:Connect(element.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			playTween(scale, CONFIG.clickTween, { Scale = clickScale })
			createRipple(element, input.Position)
		end
	end)

	scope:Connect(element.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			playTween(scale, CONFIG.hoverTween, { Scale = hoverScale })
		end
	end)
end

local holder = gui:WaitForChild("SettingsHolder",10)
local templates = gui.Resources:WaitForChild("Templates",10)
local main = holder:WaitForChild("Main",10)

local tabBar = main:WaitForChild("TabBar",10)
local content = main:WaitForChild("Content",10)
local rows = content:WaitForChild("Rows",10)
local friendBrowser = main:WaitForChild("FriendBrowser",10)
local friendList = friendBrowser:WaitForChild("List",10)
local friendSearchBox = friendBrowser:WaitForChild("SearchBox",10)

local mainScale = scope:Add(Instance.new("UIScale"))
mainScale.Scale = 1
mainScale.Parent = main

local fbScale = scope:Add(Instance.new("UIScale"))
fbScale.Scale = 1
fbScale.Parent = friendBrowser

local openTransparency = main.BackgroundTransparency
local friendBrowserOpenTransparency = friendBrowser.BackgroundTransparency

local applySetting: (string,any)->()
local openFriendBrowser: (any)->()
local closeFriendBrowser: ()->()
local settingsCache: { [string]: any } = {}
local rowRefs: { [string]: any } = {}
local tabButtons: { [string]: any } = {}
local activeTabId: string? = nil
local friendsListCache: { { Id: number, Name: string } }? = nil
local activeFriendDef: any = nil
local friendBrowserToken = 0
local friendsLoading = false
local isOpen = false
local blurEffect: BlurEffect? = nil
local pendingSaves: { [string]: thread } = {}

-- NOVO: garante que shared.Settings existe


-- ============================================================
-- Slider (COM FIX CRÍTICO DO LEAK)
-- ============================================================

local setupSlider = require(clientRoot.UI.Components.Slider)({CONFIG=CONFIG,settingsCache=settingsCache,rowRefs=rowRefs,applySetting=function(...) return applySetting(...) end,playTween=playTween,modifyColor=modifyColor,bindInteractiveScale=bindInteractiveScale,openFriendBrowser=function(...) return openFriendBrowser(...) end},scope)
local setupToggle = require(clientRoot.UI.Components.Toggle)({CONFIG=CONFIG,settingsCache=settingsCache,rowRefs=rowRefs,applySetting=function(...) return applySetting(...) end,playTween=playTween,modifyColor=modifyColor,bindInteractiveScale=bindInteractiveScale,openFriendBrowser=function(...) return openFriendBrowser(...) end},scope)
local setupFriendPicker = require(clientRoot.UI.Components.FriendPicker)({CONFIG=CONFIG,settingsCache=settingsCache,rowRefs=rowRefs,applySetting=function(...) return applySetting(...) end,playTween=playTween,modifyColor=modifyColor,bindInteractiveScale=bindInteractiveScale,openFriendBrowser=function(...) return openFriendBrowser(...) end},scope)
local function clearRows(callback: (() -> ())?)
	local validChildren: { GuiObject } = {}
	for _, child in ipairs(rows:GetChildren()) do
		if child:IsA("GuiObject") then
			table.insert(validChildren, child)
		end
	end

	if #validChildren == 0 then
		if callback then callback() end
		return
	end

	for i, child in ipairs(validChildren) do
		local scale = child:FindFirstChildOfClass("UIScale")
		local group = child:FindFirstChildOfClass("CanvasGroup")

		if scale and group then
			playTween(scale, withDelay(CONFIG.hoverTween, (i - 1) * 0.02), { Scale = 0.9 })
			playTween(group, withDelay(CONFIG.hoverTween, (i - 1) * 0.02), { Position = UDim2.new(0, -30, 0, 0) })
			local t = playTween(group, withDelay(CONFIG.hoverTween, (i - 1) * 0.02), { GroupTransparency = 1 })

			if i == #validChildren then
				scope:Once(t.Completed, function()
					for _, c in ipairs(validChildren) do c:Destroy() end
					if callback then callback() end
				end)
			end
		else
			child:Destroy()
			if i == #validChildren and callback then callback() end
		end
	end
	table.clear(rowRefs)
end

local function animateRowIn(row: any, order: number)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = row

	local group = Instance.new("CanvasGroup")
	group.Size = UDim2.new(1, 0, 1, 0)
	group.Position = UDim2.new(0, 30, 0, 0)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1

	for _, child in ipairs(row:GetChildren()) do
		if child ~= scale and child ~= group then
			child.Parent = group
		end
	end
	group.Parent = row

	local delayInfo = withDelay(CONFIG.rowEntranceTween, (order - 1) * CONFIG.rowStagger)
	local fadeDelayInfo = withDelay(CONFIG.fadeTween, (order - 1) * CONFIG.rowStagger)

	playTween(scale, delayInfo, { Scale = 1 })
	playTween(group, delayInfo, { Position = UDim2.new(0, 0, 0, 0) })
	playTween(group, fadeDelayInfo, { GroupTransparency = 0 })
end

local function renderTab(tabDef: any)
	clearRows(function()
        if not scope:IsAlive() or activeTabId ~= tabDef.Id then return end
		for index, settingDef in ipairs(tabDef.Settings) do
			local template = templates:FindFirstChild(settingDef.Type)
			if not template then continue end

			local row = template:Clone()
			row.Name = settingDef.Id
			row.Visible = true
			row.LayoutOrder = index
			row.Parent = rows

			if settingDef.Type == "Slider" then
				setupSlider(row, settingDef)
			elseif settingDef.Type == "Toggle" then
				setupToggle(row, settingDef)
			elseif settingDef.Type == "FriendPicker" then
				setupFriendPicker(row, settingDef)
			end

			animateRowIn(row, index)
		end
	end)
end

local function setActiveTab(tabDef: any)
	activeTabId = tabDef.Id
	for id, button in pairs(tabButtons) do
		local isActive = id == tabDef.Id
		button:SetAttribute("Selected", isActive)

		playTween(button, CONFIG.tabFadeTween, {
			BackgroundColor3 = isActive and CONFIG.InactiveColor or Color3.fromRGB(20, 20, 20),
		})

		local label = button:FindFirstChild("TabName")
		if label then
			playTween(label, CONFIG.tabFadeTween, {
				TextTransparency = isActive and 0 or 0.5,
			})
		end
	end
	renderTab(tabDef)
end

local function createTabButton(tabDef: any, order: number)
	local button = templates.TabButton:Clone()
	button.Name = tabDef.Id
	button.LayoutOrder = order
	button:WaitForChild("TabName",10).Text = tabDef.Name
	button.Parent = tabBar

	bindInteractiveScale(button, 1.06, 0.93)

	scope:Connect(button.MouseEnter, function()
		if activeTabId ~= tabDef.Id then
			playTween(button, CONFIG.hoverTween, {
				BackgroundColor3 = modifyColor(CONFIG.InactiveColor, CONFIG.HoverColorModifier),
			})
		end
	end)

	scope:Connect(button.MouseLeave, function()
		if activeTabId ~= tabDef.Id then
			playTween(button, CONFIG.hoverTween, { BackgroundColor3 = Color3.fromRGB(20, 20, 20) })
		end
	end)

	scope:Connect(button.MouseButton1Click, function()
		if activeTabId ~= tabDef.Id then
			setActiveTab(tabDef)
		end
	end)

	tabButtons[tabDef.Id] = button
end

for index, tabDef in ipairs(SettingsDefinitions) do
	createTabButton(tabDef, index)
end

-- ============================================================
-- Amigos
-- ============================================================

local function clearFriendList()
	for _, child in ipairs(friendList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function selectFriend(userId: number?)
	if not activeFriendDef then return end
	applySetting(activeFriendDef.Id, userId)
	if rowRefs[activeFriendDef.Id] then
		rowRefs[activeFriendDef.Id].refresh(userId)
	end
	closeFriendBrowser()
end

local function createFriendEntry(userId: number?, displayName: string, order: number)
	local entry = templates.FriendEntry:Clone()
	entry.Name = displayName
	entry.LayoutOrder = order
	entry:WaitForChild("NameLabel",10).Text = displayName

	local group = Instance.new("CanvasGroup")
	group.Size = UDim2.new(1, 0, 1, 0)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.Position = UDim2.new(0, 15, 0, 0)

	for _, child in ipairs(entry:GetChildren()) do
		if child:IsA("GuiObject") then
			child.Parent = group
		end
	end
	group.Parent = entry
	entry.Parent = friendList

	bindInteractiveScale(entry, 1.03, 0.96)

	scope:Connect(entry.MouseButton1Click, function()
		selectFriend(userId)
	end)

	local delayInfo = withDelay(CONFIG.rowEntranceTween, order * 0.03)
	playTween(group, delayInfo, { GroupTransparency = 0, Position = UDim2.new(0, 0, 0, 0) })
end

local function loadFriendsList()
    while friendsLoading and scope:IsAlive() do task.wait() end
	if friendsListCache or not scope:IsAlive() then return end
    friendsLoading = true
	friendsListCache = {}

	local ok, pages = pcall(Players.GetFriendsAsync, Players, LocalPlayer.UserId)
	if ok and pages then
		while true do
			for _, item in ipairs(pages:GetCurrentPage()) do
				table.insert(friendsListCache :: any, { Id = item.Id, Name = item.Username })
				-- NOVO: cap
				if #(friendsListCache :: any) >= CONFIG.FriendCacheCap then break end
			end
			if pages.IsFinished or #(friendsListCache :: any) >= CONFIG.FriendCacheCap then break end
			local advanced = pcall(function() pages:AdvanceToNextPageAsync() end)
			if not advanced then break end
		end
	end
    friendsLoading = false
end

openFriendBrowser = function(def: any)
    friendBrowserToken += 1
    local token = friendBrowserToken
	activeFriendDef = def
	clearFriendList()
	friendSearchBox.Text = ""

	friendBrowser.Visible = true
	friendBrowser.BackgroundTransparency = 1
	friendBrowser.Rotation = 3
	fbScale.Scale = 0.85

	playTween(friendBrowser, CONFIG.fadeTween, { BackgroundTransparency = friendBrowserOpenTransparency })
	playTween(friendBrowser, CONFIG.openTween, { Rotation = 0 })
	playTween(fbScale, CONFIG.openTween, { Scale = 1 })

	createFriendEntry(nil, "Random", 0)
	scope:Spawn(function()
		loadFriendsList()
		for index, friend in ipairs(friendsListCache or {}) do
			if not scope:IsAlive() or token ~= friendBrowserToken or not friendBrowser.Visible or activeFriendDef ~= def then break end
			createFriendEntry(friend.Id, friend.Name, index)
			if index % 12 == 0 then task.wait() end
		end
	end)
end

closeFriendBrowser = function()
    friendBrowserToken += 1
    local token = friendBrowserToken
    activeFriendDef = nil
	playTween(fbScale, CONFIG.closeTween, { Scale = 0.85 })
	playTween(friendBrowser, CONFIG.closeTween, { Rotation = -3 })
	local tween = playTween(friendBrowser, CONFIG.fadeTween, { BackgroundTransparency = 1 })

	scope:Once(tween.Completed, function()
        if token ~= friendBrowserToken then return end
		friendBrowser.Visible = false
		clearFriendList()
	end)
end

-- ============================================================
-- Search / Persistência
-- ============================================================

local searchScale = Instance.new("UIScale")
searchScale.Parent = friendSearchBox
searchScale.Scale = 1

scope:Connect(friendSearchBox.Focused, function()
	playTween(searchScale, CONFIG.hoverTween, { Scale = 1.02 })
end)

scope:Connect(friendSearchBox.FocusLost, function()
	playTween(searchScale, CONFIG.hoverTween, { Scale = 1 })
end)

scope:Connect(friendSearchBox:GetPropertyChangedSignal("Text"), function()
	local query = string.lower(friendSearchBox.Text)
	for _, child in ipairs(friendList:GetChildren()) do
		if child:IsA("GuiButton") and child.Name ~= "Random" then
			child.Visible = query == "" or string.find(string.lower(child.Name), query, 1, true) ~= nil
		end
	end
end)

-- SettingsController signals the owning controller, including its temporary emote ducking.
local LiveAppliers: { [string]: (value: any) -> () } = {}

applySetting = function(id: string, value: any)
	settingsCache[id] = value


	Settings.Set(id,value)

	-- NOVO: pcall no applier
	if LiveAppliers[id] then
		pcall(LiveAppliers[id], value)
	end


end

-- ============================================================
-- Abrir / Fechar
-- ============================================================

local function openSettings()
    router.CloseOthers("Settings")
	if isOpen then return end
	isOpen = true
    ClientState.Set("settingsOpen", true)

	holder.Visible = true
	main.BackgroundTransparency = 1
	main.Rotation = -4
	mainScale.Scale = 0.75

	blurEffect = scope:Add(Instance.new("BlurEffect"))
	blurEffect.Size = 0
	blurEffect.Name = "SETTINGS_BLUR"
	blurEffect.Parent = workspace.CurrentCamera

	playTween(mainScale, CONFIG.openTween, { Scale = 1 })
	playTween(main, CONFIG.openTween, { Rotation = 0 })
	playTween(main, CONFIG.fadeTween, { BackgroundTransparency = openTransparency })
	playTween(blurEffect, CONFIG.fadeTween, { Size = CONFIG.BlurSize })

	if not activeTabId and SettingsDefinitions[1] then
		setActiveTab(SettingsDefinitions[1])
	end
end

local function closeSettings()
	if not isOpen then return end
	isOpen = false
    ClientState.Set("settingsOpen", false)

	if friendBrowser.Visible then
		closeFriendBrowser()
	end

	playTween(mainScale, CONFIG.closeTween, { Scale = 0.8 })
	playTween(main, CONFIG.closeTween, { Rotation = 3 })
	playTween(main, CONFIG.fadeTween, { BackgroundTransparency = 1 })

	-- NOVO: guard nil no blurEffect
	if blurEffect then
		local fadingBlur = blurEffect
		blurEffect = nil
		playTween(fadingBlur, CONFIG.fadeTween, { Size = 0 })
		scope:Delay(CONFIG.fadeTween.Time, function()
			if fadingBlur and fadingBlur.Parent then
				fadingBlur:Destroy()
			end
		end)
	end

	scope:Delay(CONFIG.closeTween.Time, function()
		if not isOpen then
			holder.Visible = false
		end
	end)
end

-- ============================================================
-- Ícone Topbar
-- ============================================================

local gearIcon: any
if Icon then
	gearIcon = Icon.new()
		:setImage(CONFIG.GearIconId)
		:align("Left")

	scope:Connect(gearIcon.toggled, function(isSelected: boolean)
		if isSelected then
			openSettings()
		else
			closeSettings()
		end
	end)
end

-- ============================================================
-- Init
-- ============================================================

local function initSettings()
	local ok, data = pcall(function()
		return table.clone(Settings.GetSnapshot())
	end)

	if ok and type(data) == "table" then
		for key,value in pairs(data) do settingsCache[key]=value end
	end



	for _, tabDef in ipairs(SettingsDefinitions) do
		for _, settingDef in ipairs(tabDef.Settings) do
			if settingsCache[settingDef.Id] == nil then
				settingsCache[settingDef.Id] = settingDef.Default
			end

		end
	end

	for id, applier in pairs(LiveAppliers) do
		pcall(applier, settingsCache[id])
	end
end

initSettings()
scope:Connect(UserInputService.InputBegan, function(input, processed)
    if not isOpen or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
        closeSettings()
        if gearIcon then gearIcon:deselect() end
    end
end)
scope:Connect(Settings.Changed,function(id,value)
    settingsCache[id]=value
    if rowRefs[id] then rowRefs[id].refresh(value) end
end)
scope:Add(function()
    ClientState.Set("settingsOpen", false)
    if gearIcon then gearIcon:destroy() end
    if blurEffect then blurEffect:Destroy() end
end)
return {Close=function() closeSettings(); if gearIcon then gearIcon:deselect() end end,Destroy=function() scope:Destroy() end}

end
return Screen
