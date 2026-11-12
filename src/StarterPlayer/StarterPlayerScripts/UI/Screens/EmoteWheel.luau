--!strict
-- Mounts one emote screen and releases its previews, input, and effects on removal.
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
local Scope = require(game:GetService("ReplicatedStorage").Shared.Utils.Scope)
local ClientState = require(clientRoot.ClientState)
local Settings = require(clientRoot.Controllers.SettingsController)
local Screen = {Name="EmoteWheel",GuiName="MainUI"}
function Screen.Mount(gui: ScreenGui, router: any)
local scope=Scope.new()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Resources = gui:WaitForChild("Resources",10)
local UpdateEmoteWheel = ReplicatedStorage:WaitForChild("Remotes",10):WaitForChild("Player",10).UpdateEmoteWheel
local GetWorldModel = require(clientRoot.UI.AvatarPreview)
local controller = require(clientRoot.Controllers.EmoteController)
local spectralModule = clientRoot.Controllers.SpectralAudioController
local mediaModule = clientRoot.Controllers.MediaPreparationController
local media = require(mediaModule)

local inventorySnapshot = controller:GetInventory()
local Icon = nil
pcall(function()
	Icon = require(ReplicatedStorage.Packages.TopbarPlus:WaitForChild("Icon",10))
end)

local CONFIG = require(ReplicatedStorage.Shared.Config.EmoteUIConfig)

local GRADIENT_TYPES = {
	{ order = -5, gradient = "Video" },
	{ order = -4, gradient = "Special" },
	{ order = -3, gradient = "Exclusive" },
	{ order = -2, gradient = "Gamepass" },
	{ order = -1, gradient = "Syncable" },
	{ order = 0, gradient = "Traversal" },
}

local slotPositions = {
	UDim2.fromScale(0.5, 0.08),
	UDim2.fromScale(0.08, 0.5),
	UDim2.fromScale(0.92, 0.5),
	UDim2.fromScale(0.5, 0.92),
	UDim2.fromScale(0.18, 0.18),
	UDim2.fromScale(0.82, 0.18),
	UDim2.fromScale(0.18, 0.82),
	UDim2.fromScale(0.82, 0.82),
}

-- NOVO: helper pra tocar SFX sem quebrar se o Sound não existir
local function playSFX(sound: any)
	if not sound then return end
	pcall(function() sound:Play() end)
end

local ui: any = { holder = gui:WaitForChild("EmoteHolder",10) }
ui.wheel = ui.holder:WaitForChild("Wheel",10)
ui.shadow = ui.wheel:WaitForChild("Shadow",10)
ui.contents = ui.wheel.Contents
ui.editButton = ui.wheel:WaitForChild("EditButton",10)
ui.dropdown = ui.holder:WaitForChild("Dropdown",10)
ui.preview = ui.dropdown:WaitForChild("Preview",10)
ui.inventory = ui.dropdown:WaitForChild("Contents",10)
ui.searchBox = ui.dropdown:WaitForChild("TopFrame",10):WaitForChild("TextBox",10)

local audioStatus = scope:Add(Instance.new("TextLabel"))
audioStatus.Name = "AudioStatus"
audioStatus.AnchorPoint = Vector2.new(0.5, 0.5)
audioStatus.Position = UDim2.fromScale(0.5, 0.983)
audioStatus.Size = UDim2.fromScale(0.88, 0.032)
audioStatus.BackgroundTransparency = 1
audioStatus.TextColor3 = Color3.fromRGB(220, 224, 232)
audioStatus.FontFace = ui.preview.Title.FontFace
audioStatus.TextScaled = true
audioStatus.Text = ""
audioStatus.ZIndex = ui.preview.Equip.ZIndex
audioStatus.Parent = ui.preview
local statusSize = Instance.new("UITextSizeConstraint")
statusSize.MinTextSize = 9; statusSize.MaxTextSize = 14; statusSize.Parent = audioStatus
local mediaProgress = Instance.new("Frame")
mediaProgress.Name = "MediaProgress"
mediaProgress.AnchorPoint = Vector2.new(0.5, 0)
mediaProgress.Position = UDim2.fromScale(0.5, 1)
mediaProgress.Size = UDim2.new(1, 0, 0, 2)
mediaProgress.BorderSizePixel = 0
mediaProgress.BackgroundColor3 = audioStatus.TextColor3
mediaProgress.BackgroundTransparency = 0.8
mediaProgress.Visible = false
mediaProgress.ZIndex = audioStatus.ZIndex
mediaProgress.Parent = audioStatus
local mediaFill = Instance.new("Frame")
mediaFill.Size = UDim2.fromScale(0, 1)
mediaFill.BorderSizePixel = 0
mediaFill.BackgroundColor3 = audioStatus.TextColor3
mediaFill.ZIndex = mediaProgress.ZIndex + 1
mediaFill.Parent = mediaProgress
local previewSong: any = nil
local equipHome = ui.preview.Equip.Position
local auditionButton = scope:Add(Instance.new("TextButton"))
auditionButton.Name = "Audition"
auditionButton.AnchorPoint = ui.preview.Equip.AnchorPoint
auditionButton.Position = UDim2.fromScale(0.27, 0.932)
auditionButton.Size = ui.preview.Equip.Size
auditionButton.BackgroundColor3 = Color3.fromRGB(35, 43, 48)
auditionButton.TextColor3 = Color3.fromRGB(238, 242, 246)
auditionButton.FontFace = ui.preview.Equip.FontFace
auditionButton.TextScaled = true
auditionButton.Text = "Listen"
auditionButton.Visible = false
auditionButton.ZIndex = ui.preview.Equip.ZIndex
auditionButton.Parent = ui.preview
local auditionSize = Instance.new("UITextSizeConstraint")
auditionSize.MinTextSize = 10; auditionSize.MaxTextSize = 18; auditionSize.Parent = auditionButton
local function refreshAudioStatus()
    if not previewSong then
        audioStatus.Text = ""
        mediaProgress.Visible = false
        return
    end
    local loading = mediaModule:GetAttribute("Preparing") or spectralModule:GetAttribute("PreviewLoading")
    local progress = if mediaModule:GetAttribute("Preparing") then mediaModule:GetAttribute("Progress") else spectralModule:GetAttribute("PreviewProgress")
    mediaProgress.Visible = loading == true
    mediaFill.Size = UDim2.fromScale(if type(progress) == "number" then math.clamp(progress, 0, 1) else 0, 1)
	local previewTrack = spectralModule:GetAttribute("PreviewTrack")
	local activePreview = previewSong and (previewTrack == previewSong.Track
		or mediaModule:GetAttribute("PreviewTrack") == previewSong.Track)
	auditionButton.Text = if activePreview then "Stop" else "Listen"
	if mediaModule:GetAttribute("PreviewError") then audioStatus.Text = tostring(mediaModule:GetAttribute("PreviewError"))
	elseif mediaModule:GetAttribute("Preparing") then
		local progress = mediaModule:GetAttribute("Progress") or 0
		audioStatus.Text = `Loading media • {math.floor(math.clamp(progress, 0, 1) * 100)}%`
	elseif spectralModule:GetAttribute("PreviewError") then audioStatus.Text = "Audio unavailable"
	elseif spectralModule:GetAttribute("PreviewLoading") then
		local progress = spectralModule:GetAttribute("PreviewProgress")
		audioStatus.Text = if type(progress) == "number" then `Loading audio • {math.floor(math.clamp(progress, 0, 1) * 100)}%`
			else "Preparing audio…"
	elseif activePreview and spectralModule:GetAttribute("State") == "Buffering" then
		audioStatus.Text = "Recovering audio…"
	elseif activePreview then
		audioStatus.Text = "Preview • only you can hear it"
	else audioStatus.Text = "" end
end
scope:Connect(auditionButton.Activated, function()
	if not previewSong then return end
	if spectralModule:GetAttribute("PreviewTrack") == previewSong.Track
		or mediaModule:GetAttribute("PreviewTrack") == previewSong.Track then media.StopPreview()
	else media.Preview(previewSong) end
end)
for _, attribute in {"PreviewTrack", "PreviewLoading", "PreviewError", "PreviewProgress", "State"} do
	scope:Connect(spectralModule:GetAttributeChangedSignal(attribute), refreshAudioStatus)
end
for _, attribute in {"PreviewTrack", "Preparing", "PreviewError", "Progress"} do
	scope:Connect(mediaModule:GetAttributeChangedSignal(attribute), refreshAudioStatus)
end

refreshAudioStatus()

-- Estado
local editMode = false
local inventoryOpen = false
local activeInventorySlot: GuiObject? = nil
local wheelOpen = false
local canOpen = not workspace:GetAttribute("unsafeTime")
local characterDead = false
local blurEffect: BlurEffect? = nil
local previewLoaded = false
local previewModel: Model? = nil
local previewTrack: AnimationTrack? = nil
local previewIntroTrack: AnimationTrack? = nil
local previewData: any = nil
local previewSound: Sound? = nil
local equipConnection: RBXScriptConnection? = nil
local currentPreviewButton: GuiObject? = nil
local characterToken = 0
local inventoryToken = 0
local emptyState = scope:Add(Instance.new("TextLabel"))
emptyState.Name = "EmptySearch"
emptyState.Position = ui.inventory.Position
emptyState.Size = ui.inventory.Size
emptyState.AnchorPoint = ui.inventory.AnchorPoint
emptyState.BackgroundTransparency = 1
emptyState.TextColor3 = audioStatus.TextColor3
emptyState.FontFace = audioStatus.FontFace
emptyState.TextScaled = true
emptyState.TextWrapped = true
emptyState.Visible = false
emptyState.ZIndex = ui.inventory.ZIndex + 1
emptyState.Parent = ui.dropdown
local emptySize = Instance.new("UITextSizeConstraint")
emptySize.MinTextSize = statusSize.MinTextSize
emptySize.MaxTextSize = auditionSize.MaxTextSize
emptySize.Parent = emptyState

local editTweens: { any } = {}
local wheelTweens: { any } = {}
local slotTracks: { [number]: AnimationTrack? } = {}
local slotIntroTracks: { [number]: AnimationTrack? } = {}
local dropdownTasks: { any } = {}
local inventoryItems: { GuiObject } = {}
local wheelSlotButtons: { GuiObject } = {}
local slotHoverPairs: { [GuiObject]: { Tween } } = {}
local characterConnections: { RBXScriptConnection } = {}

local previewScale = scope:Add(Instance.new("UIScale"))
previewScale.Scale = CONFIG.previewZoomStart
previewScale.Parent = ui.preview

local previewSlideTween = scope:Tween(ui.preview, CONFIG.openTween, { Position = CONFIG.previewOpenPosition })
local previewFadeTween = scope:Tween(ui.preview, CONFIG.fadeTween, { GroupTransparency = 0 })
local previewScaleTween = scope:Tween(previewScale, CONFIG.previewZoomTween, { Scale = CONFIG.previewZoomEnd })

local CloseInventory: (instant: boolean?) -> ()
local PreviewEmote: (data: any, candidateButton: GuiObject?, slotButton: GuiObject?) -> ()
local OpenInventory: (slotButton: GuiObject?) -> ()
local toggleGUI: (open: boolean) -> ()
local updateCanOpen: () -> ()

-- ============================================================
-- Utilidades
-- ============================================================

local function clearTweens(list: { any })
	for key, tween in pairs(list) do
		tween:Cancel()
		tween:Destroy()
		list[key] = nil
	end
end

local function withDelay(info: TweenInfo, delayTime: number): TweenInfo
	return TweenInfo.new(info.Time, info.EasingStyle, info.EasingDirection, info.RepeatCount, info.Reverses, delayTime)
end

local function cleanupTask(item: any)
	if typeof(item) == "RBXScriptConnection" then
		item:Disconnect()
	elseif typeof(item) == "Instance" then
		if item:IsA("Tween") then item:Cancel() end
		item:Destroy()
	end
end

local PreviewAnimation=require(clientRoot.UI.Components.PreviewAnimation)
local destroyTrack=PreviewAnimation.destroyTrack
local isValidAnimationId=PreviewAnimation.isValidAnimationId
local loadTrack=PreviewAnimation.loadTrack
local playEmoteLoop=PreviewAnimation.playEmoteLoop
local function getPreviewSound(): Sound
	if previewSound then return previewSound end
	previewSound = Instance.new("Sound")
	previewSound.Name = "PreviewSound"
	previewSound.Looped = true
	previewSound.Parent = script
	previewSound:AddTag("EmoteSound")
	return previewSound
end

-- NOVO: destrói o preview sound (não só para)
local function destroyPreviewSound()
	previewSong = nil
	auditionButton.Visible = false
	ui.preview.Equip.Position = equipHome
	media.StopPreview()
	if previewSound then
		pcall(function() previewSound:Stop() end)
		pcall(function() previewSound:Destroy() end)
		previewSound = nil
	end
    refreshAudioStatus()
end

local function decorateEmoteButton(data: any, button: any)
	for _, gradientType in ipairs(GRADIENT_TYPES) do
		if data[gradientType.gradient] then
			button.LayoutOrder = gradientType.order
			button.Type.Text = "[ " .. string.upper(gradientType.gradient) .. " ]"
			button:SetAttribute(string.lower(gradientType.gradient), true)
			-- NOVO: pcall no fromExisting
			local ok, clone = pcall(function()
				return Instance.fromExisting(Resources.EmoteGradients[gradientType.gradient])
			end)
			if ok and clone then
				clone.Parent = button
			end
			return
		end
	end
	button.LayoutOrder = 1
	button.Type.Text = "[ DEFAULT ]"
	button:SetAttribute("default", true)
	local ok, clone = pcall(function()
		return Instance.fromExisting(Resources.EmoteGradients.Normal)
	end)
	if ok and clone then
		clone.Parent = button
	end
end

local function findSlotData(index: number): any?
	for _, data in ipairs(inventorySnapshot) do
		if data.equipped and data.Slot == index then return data end
	end
	return nil
end

local function refreshSlot(slotButton: any)
	local index = slotButton:GetAttribute("Number")
	local data = findSlotData(index)
	local viewport = slotButton:FindFirstChild("ViewportFrame")

	destroyTrack(slotTracks[index])
	slotTracks[index] = nil
	destroyTrack(slotIntroTracks[index])
	slotIntroTracks[index] = nil

	if not data then
		slotButton.EmoteName.Text = ""
		slotButton:SetAttribute("Emote", "")
		if viewport then viewport.Visible = false end
		return
	end

	slotButton.EmoteName.Text = data.Name
	slotButton:SetAttribute("Emote", data.Name)
	if not viewport then return end
	viewport.Visible = true

	local avatar = viewport:FindFirstChild("CurrentAvatar")
	if not avatar then
		local snapshot = GetWorldModel.GetCurrentAvatar()
		if not snapshot then return end
		avatar = snapshot:Clone()
		avatar.Parent = viewport
		avatar:PivotTo(CFrame.new(0, 0, -5.15) * CFrame.Angles(0, math.pi, 0))
	end

	slotTracks[index], slotIntroTracks[index] = playEmoteLoop(avatar, data)
end

-- ============================================================
-- Ícone mobile
-- ============================================================

local mobileToggleIcon: any = nil
local isMobileToggleActive = false

if Icon then
	mobileToggleIcon = scope:Add(Icon.new()):setImage("rbxassetid://11713358131"):align("Right")
	scope:Connect(mobileToggleIcon.toggled, function(isSelected: boolean)
		if isMobileToggleActive then return end
		toggleGUI(isSelected)
	end)
end

-- ============================================================
-- Estado inicial da UI
-- ============================================================

if workspace.CurrentCamera and workspace.CurrentCamera:FindFirstChild("EMOTE_BLUR") then
	workspace.CurrentCamera.EMOTE_BLUR:Destroy()
end

ui.holder.Visible = false
ui.wheel.Size = CONFIG.wheelClosedSize
ui.wheel.Position = CONFIG.wheelClosedPosition
ui.wheel.Visible = true
ui.shadow.ImageTransparency = CONFIG.shadowClosedAlpha
ui.wheel.Image.ImageTransparency = CONFIG.imageClosedAlpha
ui.editButton.Visible = true
ui.editButton.Selectable = true
ui.editButton.Position = CONFIG.editButtonHome
ui.editButton.TextLabel.TextTransparency = 1
ui.editButton.TextLabel.Position = CONFIG.editLabelHome
ui.dropdown.Visible = false
ui.dropdown.Size = CONFIG.dropdownClosedSize
ui.dropdown.BackgroundTransparency = 1
ui.dropdown.Contents.ScrollBarImageTransparency = 1
ui.preview.Position = CONFIG.previewClosedPosition
ui.preview.GroupTransparency = 1

scope:Connect(ui.editButton.MouseButton1Down, function()
	if inventoryOpen then return end
	clearTweens(editTweens)
	editMode = not editMode
	ui.editButton.Text = editMode and "Cancel" or "Edit"

	local buttonTween = scope:Tween(ui.editButton, CONFIG.editButtonTween, {
		Position = editMode and CONFIG.editButtonActive or CONFIG.editButtonHome,
	})
	local labelTween = scope:Tween(ui.editButton.TextLabel, CONFIG.editLabelTween, {
		TextTransparency = editMode and 0 or 1,
		Position = editMode and CONFIG.editLabelActive or CONFIG.editLabelHome,
	})
	buttonTween:Play()
	labelTween:Play()
	table.insert(editTweens, buttonTween)
	table.insert(editTweens, labelTween)
end)

-- ============================================================
-- Inventário
-- ============================================================

CloseInventory = function(instant: boolean?)
    inventoryToken += 1
	previewData = nil
    emptyState.Visible = false
	destroyTrack(previewTrack); previewTrack = nil
	destroyTrack(previewIntroTrack); previewIntroTrack = nil
	if equipConnection then equipConnection:Disconnect(); equipConnection = nil end
	if previewModel then previewModel:Destroy(); previewModel = nil end
	-- NOVO: destrói em vez de só parar
	destroyPreviewSound()

	previewSlideTween:Cancel()
	previewFadeTween:Cancel()
	previewScaleTween:Cancel()

	inventoryOpen = false
	previewLoaded = false
	editMode = false
	currentPreviewButton = nil

	for _, item in ipairs(inventoryItems) do item:Destroy() end
	table.clear(inventoryItems)

	for key, entry in pairs(dropdownTasks) do
		cleanupTask(entry)
		dropdownTasks[key] = nil
	end

	ui.editButton.Text = "Edit"
	ui.editButton.Visible = true
	ui.editButton.Selectable = true

	if instant then
		ui.preview.Position = CONFIG.previewClosedPosition
		ui.preview.GroupTransparency = 1
		previewScale.Scale = CONFIG.previewZoomStart
		ui.editButton.Position = CONFIG.editButtonHome
		ui.editButton.TextLabel.TextTransparency = 1
		ui.editButton.TextLabel.Position = CONFIG.editLabelHome
		ui.dropdown.Visible = false
		ui.dropdown.Size = CONFIG.dropdownClosedSize
		ui.dropdown.BackgroundTransparency = 1
		ui.dropdown.Contents.ScrollBarImageTransparency = 1
		ui.wheel.Visible = true
		return
	end

	scope:Tween(ui.preview, CONFIG.closeTween, { Position = CONFIG.previewClosedPosition, GroupTransparency = 1 }):Play()
	scope:Tween(previewScale, CONFIG.closeTween, { Scale = CONFIG.previewZoomStart }):Play()
	scope:Tween(ui.editButton, CONFIG.editButtonTween, { Position = CONFIG.editButtonHome }):Play()
	scope:Tween(ui.editButton.TextLabel, CONFIG.editLabelTween, { TextTransparency = 1, Position = CONFIG.editLabelHome }):Play()

	local dropdownTween = scope:Tween(ui.dropdown, CONFIG.closeTween, { Size = CONFIG.dropdownClosedSize, BackgroundTransparency = 1 })
	local scrollTween = scope:Tween(ui.dropdown.Contents, CONFIG.closeTween, { ScrollBarImageTransparency = 1 })
	dropdownTween:Play()
	scrollTween:Play()
	scope:Once(dropdownTween.Completed, function()
		if not inventoryOpen then
			ui.dropdown.Visible = false
			ui.wheel.Visible = true
		end
	end)
end

PreviewEmote = function(data: any, candidateButton: GuiObject?, slotButton: GuiObject?)
	if not inventoryOpen or currentPreviewButton == candidateButton then return end
	currentPreviewButton = candidateButton
	previewData = data

	media.StopPreview()
	local song = data.Song
	previewSong = nil
	auditionButton.Visible = false
	ui.preview.Equip.Position = equipHome
	if song and song.Backend == "Spectral" and type(song.Track) == "string" then
		previewSong = song
		auditionButton.Visible = true
		ui.preview.Equip.Position = UDim2.fromScale(0.73, 0.932)
		media.Preview(song)
	end
	-- Native asset previews share the same selection lifecycle as spectral previews.
	if song and song.Backend ~= "Spectral" and type(song.SoundId) == "string" and song.SoundId ~= "" then
		local sound = getPreviewSound()
		local volume = (song.Volume or 1) / 1.2
		sound:SetAttribute("Volume", volume)
		sound.SoundId = song.SoundId
		sound.Volume = volume
		sound.PlaybackSpeed = song.PlaybackSpeed or 1
		sound.TimePosition = song.StartTime or 0
		pcall(function() sound:Play() end)
	elseif previewSound then
		pcall(function() previewSound:Stop() end)
	end

	if not previewLoaded then
		previewLoaded = true
		previewSlideTween:Play()
		previewFadeTween:Play()
		previewScaleTween:Play()
		local snapshot = GetWorldModel.GetCurrentAvatar()
		if snapshot then
			previewModel = snapshot:Clone()
			previewModel.Parent = ui.preview.ViewportFrame
			previewModel:PivotTo(CFrame.new(0, 0, -6.5) * CFrame.Angles(0, math.pi, 0))
		end
	end

	playSFX(Resources.SelectSFX)

	destroyTrack(previewTrack); previewTrack = nil
	destroyTrack(previewIntroTrack); previewIntroTrack = nil
	if previewModel then
		previewTrack, previewIntroTrack = playEmoteLoop(previewModel, data)
	end

	ui.preview.Title.Text = data.Name
	ui.preview.TitleShadow.Text = data.Name

    refreshAudioStatus()
	if equipConnection then equipConnection:Disconnect() end
	equipConnection = scope:Connect(ui.preview.Equip.MouseButton1Down, function()
		local slotNumber = slotButton and slotButton:GetAttribute("Number") or 1
		playSFX(Resources.SelectSFX)
		if equipConnection then equipConnection:Disconnect(); equipConnection = nil end

		UpdateEmoteWheel:FireServer(data.Name, slotNumber)
        -- Close in this activation; a delayed close could dismiss a newly reopened catalog.
		CloseInventory()
	end)
end

OpenInventory = function(slotButton: GuiObject?)
    inventoryToken += 1
    local token = inventoryToken
    activeInventorySlot=slotButton
	inventoryOpen = true

	local dropdownTween = scope:Tween(ui.dropdown, CONFIG.openTween, { Size = CONFIG.dropdownOpenSize })
	local scrollTween = scope:Tween(ui.dropdown.Contents, CONFIG.openTween, { ScrollBarImageTransparency = 0 })

	ui.wheel.Visible = false
	ui.searchBox.Text = ""
	ui.dropdown.Visible = true
	dropdownTween:Play()
	scrollTween:Play()
	table.insert(dropdownTasks, dropdownTween)
	table.insert(dropdownTasks, scrollTween)

	local seenNames: { [string]: boolean } = {}
	for index = #inventorySnapshot, 1, -1 do
		local name = inventorySnapshot[index].Name
		if seenNames[name] then
			table.remove(inventorySnapshot, index)
		else
			seenNames[name] = true
		end
	end

	local dataByName: { [string]: any } = {}
	local visibleCount = 0

	for _, data in ipairs(inventorySnapshot) do
		if data.equipped then continue end

		visibleCount += 1
		dataByName[data.Name] = data

		local itemButton = Resources.InventoryTemplate:Clone()
		itemButton.Name = data.Name
		itemButton.Title.Text = data.Name
		itemButton.TitleShadow.Text = data.Name
		itemButton.Visible = true
		itemButton.Selectable = true
		decorateEmoteButton(data, itemButton)
		itemButton.Parent = ui.inventory

		local itemScale = Instance.new("UIScale")
		itemScale.Scale = 0
		itemScale.Parent = itemButton

		local entrance = scope:Tween(
			itemScale,
			withDelay(CONFIG.itemEntranceTween, (visibleCount - 1) * CONFIG.itemStagger),
			{ Scale = 1 }
		)
		entrance:Play()
		table.insert(dropdownTasks, entrance)

		table.insert(dropdownTasks, scope:Connect(itemButton.MouseButton1Down, function()
			PreviewEmote(data, itemButton, slotButton)
		end))
		table.insert(dropdownTasks, scope:Connect(itemButton.MouseEnter, function()
			playSFX(Resources.HoverSFX)
		end))
		table.insert(inventoryItems, itemButton)
	end

    ui.searchBox.PlaceholderText = `Search emotes… ({#inventoryItems})`
    emptyState.Text = "All available emotes are already equipped."
    emptyState.Visible = #inventoryItems == 0

	-- Busca
	table.insert(dropdownTasks, scope:Connect(ui.searchBox:GetPropertyChangedSignal("Text"), function()
		local query = string.lower(ui.searchBox.Text):match("^%s*(.-)%s*$") or ""
        local matchCount = 0
		for _, item in ipairs(inventoryItems) do
			local matches = string.find(string.lower(item.Name), query, 1, true) ~= nil
			if not matches then
				for attributeName in pairs(item:GetAttributes()) do
					if string.find(string.lower(attributeName), query, 1, true) then
						matches = true
						break
					end
				end
			end
			item.Selectable = matches
			item.Visible = matches
            if matches then matchCount += 1 end
		end
        emptyState.Text = if #inventoryItems == 0 then "All available emotes are already equipped." else "No emotes found.\nTry a different name or category."
        emptyState.Visible = matchCount == 0
	end))

	-- Navegação por setas
	local function previewByOffset(delta: number)
		local visible: { GuiObject } = {}
		for _, item in ipairs(inventoryItems) do
			if item.Visible then table.insert(visible, item) end
		end
		if #visible == 0 then return end

		local current = table.find(visible, currentPreviewButton) or 0
		local target = visible[((current - 1 + delta) % #visible) + 1]
		local data = target and dataByName[target.Name]
		if data then PreviewEmote(data, target, slotButton) end
	end

	table.insert(dropdownTasks, scope:Connect(UserInputService.InputBegan, function(input, processed)
		if processed or not inventoryOpen or UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.Down then
			previewByOffset(1)
		elseif input.KeyCode == Enum.KeyCode.Up then
			previewByOffset(-1)
		end
	end))

	-- NOVO: guard no Close do searchBox
	local topFrame = ui.searchBox.Parent
	local closeButton = topFrame and topFrame:FindFirstChild("Close")
	if closeButton then
		table.insert(dropdownTasks, scope:Connect(closeButton.MouseButton1Down, function()
			playSFX(Resources.SelectSFX)
			CloseInventory()
		end))
	end

	-- Pré-visualiza o item mais ao topo
	task.wait()
	if not scope:IsAlive() or not inventoryOpen or token ~= inventoryToken then return end

	local topMost = math.huge
	local topButton: GuiObject? = nil
	for _, item in ipairs(inventoryItems) do
		if item.AbsolutePosition.Y < topMost then
			topMost = item.AbsolutePosition.Y
			topButton = item
		end
	end

	local topData = topButton and dataByName[topButton.Name]
	if topData then PreviewEmote(topData, topButton, slotButton) end
end

-- ============================================================
-- Slots da roda
-- ============================================================

for index = 1, 8 do
	local slotButton = Resources.WheelTemplate:Clone()
	slotButton.Parent = ui.contents
	slotButton.Visible = true
	slotButton.Name = "Slot " .. tostring(index)
	slotButton.Position = slotPositions[index]
	slotButton.Size = CONFIG.slotRestSize
	slotButton:SetAttribute("Number", index)

	local hoverTilt = (index % 2 == 0) and CONFIG.slotHoverRotation or -CONFIG.slotHoverRotation
	local hoverInTween = scope:Tween(slotButton, CONFIG.hoverInTween, { Size = CONFIG.slotHoverSize, Rotation = hoverTilt })
	local hoverOutTween = scope:Tween(slotButton, CONFIG.hoverOutTween, { Size = CONFIG.slotRestSize, Rotation = CONFIG.slotRestRotation })
	slotHoverPairs[slotButton] = { hoverInTween, hoverOutTween }

	-- NOVO: função separada chamada por Activated e MouseButton1Down
	local function onSlotActivated()
		playSFX(Resources.SelectSFX)

		if editMode and not inventoryOpen then
			OpenInventory(slotButton)
			return
		end
		if editMode or inventoryOpen then return end

		local emoteName = slotButton:GetAttribute("Emote")
		if not emoteName or emoteName == "" then return end

		if controller:IsEmoting() then
			controller:StopEmote()
			if emoteName ~= script:GetAttribute("Emote") then
				script:SetAttribute("Emote", emoteName)
				controller:Emote(emoteName)
			end
		else
			script:SetAttribute("Emote", emoteName)
			controller:Emote(emoteName)
		end
		toggleGUI(false)
	end

	-- NOVO: Activated funciona em PC + mobile + console
	scope:Connect(slotButton.Activated, function()
		onSlotActivated()
	end)

	scope:Connect(slotButton.MouseEnter, function()
		hoverInTween:Pause()
		hoverOutTween:Pause()
		hoverInTween:Play()
		playSFX(Resources.HoverSFX)
	end)
	scope:Connect(slotButton.MouseLeave, function()
		hoverInTween:Pause()
		hoverOutTween:Pause()
		hoverOutTween:Play()
	end)

	refreshSlot(slotButton)
	table.insert(wheelSlotButtons, slotButton)
end

-- ============================================================
-- Abrir / fechar a roda
-- ============================================================

toggleGUI = function(open: boolean)
	if open then
		if not canOpen or wheelOpen then return end
		ClientState.Set("emoteWheelOpen", true)
		wheelOpen = true

		if mobileToggleIcon then
			isMobileToggleActive = true
			mobileToggleIcon:select()
			isMobileToggleActive = false
		end

		router.CloseOthers("EmoteWheel")

		clearTweens(wheelTweens)
		ui.holder.Visible = true

		local shadowTween = scope:Tween(ui.shadow, CONFIG.fadeTween, { ImageTransparency = CONFIG.shadowOpenAlpha })
		local wheelTween = scope:Tween(ui.wheel, CONFIG.openTween, { Size = CONFIG.wheelOpenSize, Position = CONFIG.wheelOpenPosition })
		local imageTween = scope:Tween(ui.wheel.Image, CONFIG.fadeTween, { ImageTransparency = CONFIG.imageOpenAlpha })

		blurEffect = scope:Add(Instance.new("BlurEffect"))
		blurEffect.Size = 0
		blurEffect.Name = "EMOTE_BLUR"
		blurEffect.Parent = workspace.CurrentCamera
		local blurTween = scope:Tween(blurEffect, CONFIG.fadeTween, { Size = CONFIG.blurSize })

		for _, track in pairs(slotTracks) do
			if track then track.TimePosition = 0 end
		end
		for _, introTrack in pairs(slotIntroTracks) do
			if introTrack then introTrack.TimePosition = 0 end
		end

		for _, descendant in ipairs(ui.wheel:GetDescendants()) do
			if descendant:IsA("ViewportFrame") and descendant.Parent.Name ~= "Preview" then
				if descendant.Parent:GetAttribute("Emote") ~= "" then
					descendant.Visible = true
				end
			elseif descendant:IsA("TextButton") then
				descendant.Active = true
				descendant.Selectable = true
			end
		end

		for _, tween in ipairs({ shadowTween, wheelTween, imageTween, blurTween }) do
			tween:Play()
			table.insert(wheelTweens, tween)
		end

		scope:Once(wheelTween.Completed, function()
			if not wheelOpen then return end
			local breatheTween = scope:Tween(ui.shadow, CONFIG.breatheTween, { ImageTransparency = CONFIG.shadowBreatheAlpha })
			local pulseTween = scope:Tween(ui.wheel, CONFIG.pulseTween, { Size = CONFIG.wheelOpenSize + UDim2.fromScale(0.012, 0.012) })
			breatheTween:Play()
			pulseTween:Play()
			table.insert(wheelTweens, breatheTween)
			table.insert(wheelTweens, pulseTween)
		end)

		for idx, slotButton in ipairs(wheelSlotButtons) do
			local pair = slotHoverPairs[slotButton]
			if pair then pair[1]:Pause(); pair[2]:Pause() end
			local spin = (idx % 2 == 0) and CONFIG.slotSpinAngle or -CONFIG.slotSpinAngle
			slotButton.Size = CONFIG.slotHiddenSize
			slotButton.Rotation = spin
			local entranceTween = scope:Tween(
				slotButton,
				withDelay(CONFIG.slotEntranceTween, (idx - 1) * CONFIG.slotStagger),
				{ Size = CONFIG.slotRestSize, Rotation = CONFIG.slotRestRotation }
			)
			entranceTween:Play()
			table.insert(wheelTweens, entranceTween)
		end
	else
		if not wheelOpen then return end
		ClientState.Set("emoteWheelOpen", false)
		wheelOpen = false

		if mobileToggleIcon then
			isMobileToggleActive = true
			mobileToggleIcon:deselect()
			isMobileToggleActive = false
		end

		clearTweens(wheelTweens)
		clearTweens(editTweens)
		if equipConnection then equipConnection:Disconnect(); equipConnection = nil end

		CloseInventory(true)

		local shadowTween = scope:Tween(ui.shadow, CONFIG.closeTween, { ImageTransparency = CONFIG.shadowClosedAlpha })
		local wheelTween = scope:Tween(ui.wheel, CONFIG.closeTween, { Size = CONFIG.wheelClosedSize, Position = CONFIG.wheelClosedPosition })
		local imageTween = scope:Tween(ui.wheel.Image, CONFIG.closeTween, { ImageTransparency = CONFIG.imageClosedAlpha })

		for _, tween in ipairs({ shadowTween, wheelTween, imageTween }) do
			tween:Play()
			table.insert(wheelTweens, tween)
		end

		for _, descendant in ipairs(ui.wheel:GetDescendants()) do
			if descendant:IsA("TextButton") then
				descendant.Active = false
				descendant.Selectable = false
			end
		end

		for idx, slotButton in ipairs(wheelSlotButtons) do
			local pair = slotHoverPairs[slotButton]
			if pair then pair[1]:Pause(); pair[2]:Pause() end
			local spin = (idx % 2 == 0) and CONFIG.slotSpinAngle or -CONFIG.slotSpinAngle
			local exitTween = scope:Tween(slotButton, CONFIG.slotExitTween, { Size = CONFIG.slotHiddenSize, Rotation = spin * 0.5 })
			exitTween:Play()
			table.insert(wheelTweens, exitTween)
		end

		if blurEffect then
			local fadingBlur = blurEffect
			blurEffect = nil
			local blurTween = scope:Tween(fadingBlur, CONFIG.closeTween, { Size = 0 })
			blurTween:Play()
			scope:Once(blurTween.Completed, function() fadingBlur:Destroy() end)
		end

		scope:Once(wheelTween.Completed, function()
			if wheelOpen then return end
			ui.holder.Visible = false
			for _, descendant in ipairs(ui.wheel:GetDescendants()) do
				if descendant:IsA("ViewportFrame") then descendant.Visible = false end
			end
		end)
	end
end

-- ============================================================
-- Input
-- ============================================================

scope:Connect(UserInputService.InputBegan, function(input, gameProcessed)
	if gameProcessed or input.KeyCode ~= Enum.KeyCode.B then return end
	toggleGUI(true)
end)

scope:Connect(UserInputService.InputEnded, function(input, gameProcessed)
	if input.KeyCode ~= Enum.KeyCode.B then return end
	if wheelOpen and not inventoryOpen then toggleGUI(false) end
end)

-- ============================================================
-- Personagem
-- ============================================================

updateCanOpen = function()
	local humanoid = controller and controller:GetHumanoid()
	local character = controller and controller:GetCharacter()
	-- NOVO: guard
	if not humanoid or not character then
		canOpen = false
		return
	end
	canOpen = not (
		characterDead
			or workspace:GetAttribute("unsafeTime")
			or humanoid:GetAttribute("ragdolled")
			or character:GetAttribute("Ziplining")
	)
	if not canOpen and wheelOpen then toggleGUI(false) end
end

scope:Connect(workspace:GetAttributeChangedSignal("unsafeTime"), updateCanOpen)

local updatingViewports = false
local pendingViewportUpdate = false
local function UpdateViewports()
	if not scope:IsAlive() then return end
	if updatingViewports then pendingViewportUpdate = true; return end
	updatingViewports = true
	repeat
		pendingViewportUpdate = false
		local humanoid = controller and controller:GetHumanoid()
		local character = controller and controller:GetCharacter()
		if not humanoid or not character then break end
		local description: HumanoidDescription? = nil
		pcall(function() description = humanoid:GetAppliedDescription() end)
		local snapshot = GetWorldModel.GetCurrentAvatar()
		local custom = character:GetAttribute("AvatarType") and snapshot ~= nil
		local function apply(avatar: Model)
			if custom then pcall(function() GetWorldModel:ApplyModelDescription(avatar, snapshot) end)
			elseif description then pcall(function() avatar.Humanoid:ApplyDescriptionResetAsync(description) end) end
		end
		for _, slotButton in ipairs(wheelSlotButtons) do
			if not scope:IsAlive() then break end
			local viewport = slotButton:FindFirstChild("ViewportFrame")
			local avatar = viewport and viewport:FindFirstChild("CurrentAvatar")
			if avatar and avatar:FindFirstChild("Humanoid") then
				local index = slotButton:GetAttribute("Number")
				destroyTrack(slotTracks[index]); slotTracks[index] = nil
				destroyTrack(slotIntroTracks[index]); slotIntroTracks[index] = nil
				apply(avatar)
				if scope:IsAlive() and avatar.Parent == viewport then refreshSlot(slotButton) end
			elseif scope:IsAlive() then refreshSlot(slotButton) end
		end
		local avatar = previewModel
		if scope:IsAlive() and inventoryOpen and avatar and avatar:FindFirstChild("Humanoid") then
			destroyTrack(previewTrack); previewTrack = nil
			destroyTrack(previewIntroTrack); previewIntroTrack = nil
			apply(avatar)
			if scope:IsAlive() and inventoryOpen and previewModel == avatar and avatar.Parent then
				if previewData then previewTrack, previewIntroTrack = playEmoteLoop(avatar, previewData) end
			end
		elseif scope:IsAlive() and inventoryOpen and previewData and snapshot then
			previewModel = snapshot:Clone()
			previewModel.Parent = ui.preview.ViewportFrame
			previewModel:PivotTo(CFrame.new(0, 0, -6.5) * CFrame.Angles(0, math.pi, 0))
			previewTrack, previewIntroTrack = playEmoteLoop(previewModel, previewData)
		end
		if description then description:Destroy() end
	until not pendingViewportUpdate or not scope:IsAlive()
	updatingViewports = false
end

local function OnCharacterAdded(character: Model)
	local token = characterToken + 1
	characterToken = token
	characterDead = false
	canOpen = not workspace:GetAttribute("unsafeTime")

	for _, connection in ipairs(characterConnections) do connection:Disconnect() end
	table.clear(characterConnections)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or token ~= characterToken or not scope:IsAlive() then return end

	table.insert(characterConnections, scope:Connect(humanoid:GetAttributeChangedSignal("ragdolled"), updateCanOpen))
	table.insert(characterConnections, scope:Connect(character:GetAttributeChangedSignal("Ziplining"), updateCanOpen))
	table.insert(characterConnections, scope:Connect(character.AncestryChanged, function(_, parent)
		if parent ~= nil then return end
		canOpen = false
		if wheelOpen then toggleGUI(false) end
	end))
	table.insert(characterConnections, scope:Connect(humanoid.Died, function()
		if characterDead then return end
		characterDead = true
		canOpen = false
		if wheelOpen then toggleGUI(false) end
	end))

	-- NOVO: timeout no CharacterAppearanceLoaded
	local deadline = os.clock() + 10
	while scope:IsAlive() and characterToken == token and not controller:GetPlayer():HasAppearanceLoaded() and os.clock() < deadline do
		task.wait(0.1)
	end
	if scope:IsAlive() and characterToken == token then UpdateViewports() end
end

-- ============================================================
-- Init
-- ============================================================

-- NOVO: aplica o refreshSlot em cada slot imediatamente (caso o signal já tenha disparado antes)
for _, slotButton in ipairs(wheelSlotButtons) do
	refreshSlot(slotButton)
end

scope:Connect(controller.InventoryChanged, function()
    inventorySnapshot=controller:GetInventory()
    if inventoryOpen then
        local slot=activeInventorySlot
        local search=ui.searchBox.Text
        CloseInventory(true)
        OpenInventory(slot)
        ui.searchBox.Text=search
    end
	for _, slotButton in ipairs(wheelSlotButtons) do
		refreshSlot(slotButton)
	end
end)

scope:Connect(ReplicatedStorage:WaitForChild("Remotes",10).Gui.UpdateViewport.OnClientEvent, UpdateViewports)
scope:Connect(GetWorldModel.ViewportUpdated, UpdateViewports)

if controller:GetPlayer().Character then scope:Spawn(OnCharacterAdded, controller:GetCharacter()) end

scope:Connect(controller:GetPlayer().CharacterAdded, OnCharacterAdded)
scope:Add(function()
    ClientState.Set("emoteWheelOpen",false)
    if mobileToggleIcon then mobileToggleIcon:destroy() end
    clearTweens(wheelTweens); clearTweens(editTweens)
    for _,item in pairs(dropdownTasks) do cleanupTask(item) end
    for _,track in pairs(slotTracks) do destroyTrack(track) end
    for _,track in pairs(slotIntroTracks) do destroyTrack(track) end
    destroyTrack(previewTrack); destroyTrack(previewIntroTrack)
    destroyPreviewSound()
    if previewModel then previewModel:Destroy() end
    if blurEffect then blurEffect:Destroy() end
    for _,connection in ipairs(characterConnections) do connection:Disconnect() end
    for _,button in ipairs(wheelSlotButtons) do button:Destroy() end
end)
return {Close=function() toggleGUI(false) end, Destroy=function() scope:Destroy() end}

end
return Screen


