--!strict
-- Owns reusable avatar snapshots, description copies and appearance update subscriptions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Scope = require(ReplicatedStorage.Shared.Utils.Scope)
local Signal = require(ReplicatedStorage.Shared.Utils.Signal)
local MAX_DESC_CACHE = 100
local OWNED_ATTRIBUTE = "GWM_Owned"
local AvatarPreview: any = {DescCache = {}, IsConnected = false}
local cacheOrder: {number} = {}
local cacheFolder: Folder? = nil
local scope: any = nil
local initialized = false
local generation = 0
local appearanceToken = 0

local function current(token: number): boolean
	return initialized and generation == token
end

local function clearCache()
	for _, description in AvatarPreview.DescCache do description:Destroy() end
	table.clear(AvatarPreview.DescCache)
	table.clear(cacheOrder)
end

local function cacheKeyValid(key: any): boolean
	return type(key) == "number" and key == key and math.abs(key) < math.huge and key % 1 == 0
end

local function cacheCopy(key: number, description: HumanoidDescription)
	if not cacheFolder then return end
	local previous = AvatarPreview.DescCache[key]
	if previous then previous:Destroy() end
	local index = table.find(cacheOrder, key)
	if index then table.remove(cacheOrder, index) end
	local copy = description:Clone()
	copy.Name = tostring(key)
	copy.Parent = cacheFolder
	AvatarPreview.DescCache[key] = copy
	table.insert(cacheOrder, key)
	while #cacheOrder > MAX_DESC_CACHE do
		local oldest = table.remove(cacheOrder, 1)
		local cached = AvatarPreview.DescCache[oldest]
		if cached then cached:Destroy(); AvatarPreview.DescCache[oldest] = nil end
	end
end

local function humanoidOf(value: any): Humanoid?
	if typeof(value) ~= "Instance" then return nil end
	if value:IsA("Humanoid") then return value end
	return if value:IsA("Model") then value:FindFirstChildOfClass("Humanoid") else nil
end

local function clearOwnedAccessories(model: Model)
	for _, child in model:GetChildren() do
		if (child:IsA("Accessory") or child:IsA("Model")) and child:GetAttribute(OWNED_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

local function descriptionCopy(source: any, userId: number?, key: number?): HumanoidDescription?
	if typeof(source) == "Instance" and source:IsA("HumanoidDescription") then return source:Clone() end
	local cached = if key then AvatarPreview.DescCache[key] else nil
	if cached then return cached:Clone() end
	local humanoid = humanoidOf(source)
	local ok, result = pcall(function()
		if humanoid then return humanoid:GetAppliedDescription() end
		if userId then return Players:GetHumanoidDescriptionFromUserIdAsync(userId) end
		return nil
	end)
	return if ok and typeof(result) == "Instance" and result:IsA("HumanoidDescription") then result else nil
end

local function applyDescription(source: any, target: Humanoid, userId: number?, key: number?): boolean
	local token = generation
	local description = descriptionCopy(source, userId, key)
	if not description then warn("[AvatarPreview] Could not obtain an avatar description"); return false end
	if not current(token) or not target.Parent then description:Destroy(); return false end
	if key and not AvatarPreview.DescCache[key] then cacheCopy(key, description) end
	local parent = target.Parent
	if parent:IsA("Model") then clearOwnedAccessories(parent) end
	local ok, problem = pcall(function() target:ApplyDescriptionResetAsync(description) end)
	description:Destroy()
	if not ok then warn("[AvatarPreview] Could not apply avatar description: " .. tostring(problem)) end
	return ok and current(token) and target.Parent ~= nil
end

local function rig(): Model
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	assert(assets, "AvatarPreview requires ReplicatedStorage.Assets")
	local template = assets:WaitForChild("ViewportRig", 10)
	assert(template and template:IsA("Model"), "AvatarPreview requires a ViewportRig model")
	return template:Clone()
end

local function copyAppearance(target: Model, source: Model)
	clearOwnedAccessories(target)
	for _, child in target:GetChildren() do
		if child:IsA("Clothing") or child:IsA("BodyColors") or child:IsA("CharacterMesh") then child:Destroy() end
	end
	target:SetAttribute("AvatarType", source:GetAttribute("AvatarType"))
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	for _, item in source:GetChildren() do
		if item:IsA("Clothing") or item:IsA("BodyColors") or item:IsA("CharacterMesh") then
			item:Clone().Parent = target
		elseif item:IsA("BasePart") then
			local part = target:FindFirstChild(item.Name)
			if part and part:IsA("BasePart") then part.Transparency = item.Transparency end
		elseif item:IsA("Accessory") and targetHumanoid then
			local accessory = item:Clone()
			accessory:SetAttribute(OWNED_ATTRIBUTE, true)
			local ok = pcall(function() targetHumanoid:AddAccessory(accessory) end)
			if not ok then accessory:Destroy(); continue end
			local handle = accessory:FindFirstChild("Handle")
			local weld = handle and handle:FindFirstChild("AccessoryWeld")
			local stray = handle and handle:FindFirstChild("Look im moving", true)
			if stray then stray:Destroy() end
			if weld and weld:IsA("Weld") and weld.Part1 then
				local part = target:FindFirstChild(weld.Part1.Name)
				if part and part:IsA("BasePart") then weld.Part1 = part end
			end
		end
	end
end

function AvatarPreview.Init(_dependencies: any)
	if initialized then return end
	generation += 1
	initialized = true
	scope = Scope.new()
	cacheFolder = Instance.new("Folder")
	cacheFolder.Name = "AvatarPreviewCache"
	cacheFolder.Parent = script
	AvatarPreview.ViewportUpdated = Signal.new()
end

function AvatarPreview.Start()
	if not initialized then AvatarPreview.Init({}) end
	if AvatarPreview.IsConnected or not RunService:IsClient() then return end
	AvatarPreview.IsConnected = true
	local token = generation
	local currentScope = scope
	local player = Players.LocalPlayer
	assert(player, "AvatarPreview requires LocalPlayer")
	local currentAvatar = rig()
	if not current(token) then currentAvatar:Destroy(); return end
	AvatarPreview.CurrentAvatar = currentAvatar
	AvatarPreview.CurrentAvatar.Name = "CurrentAvatar"
	AvatarPreview.CurrentAvatar.Parent = cacheFolder
	local defaultAvatar = rig()
	if not current(token) then defaultAvatar:Destroy(); return end
	AvatarPreview.DefaultAvatar = defaultAvatar
	AvatarPreview.DefaultAvatar.Name = "DefaultAvatar"
	AvatarPreview.DefaultAvatar.Parent = cacheFolder

	local function updateCurrent(character: Model?)
		appearanceToken += 1
		local request = appearanceToken
		if not character then return end
		local deadline = os.clock() + 10
		while current(token) and request == appearanceToken and not player:HasAppearanceLoaded() and os.clock() < deadline do task.wait(0.1) end
		if not current(token) or request ~= appearanceToken or player.Character ~= character then return end
		local source = character:FindFirstChildOfClass("Humanoid")
		if not source then return end
		local candidate = rig()
		if not current(token) or request ~= appearanceToken then candidate:Destroy(); return end
		candidate.Parent = cacheFolder
		local target = candidate:FindFirstChildOfClass("Humanoid")
		local applied = target and applyDescription(source, target, player.UserId)
		if not applied or not current(token) or request ~= appearanceToken or player.Character ~= character then
			candidate:Destroy(); return
		end
		local previous = AvatarPreview.CurrentAvatar
		candidate.Name = "CurrentAvatar"
		AvatarPreview.CurrentAvatar = candidate
		if previous then previous:Destroy() end
		AvatarPreview.ViewportUpdated:Fire()
	end

	currentScope:Connect(player.CharacterAdded, function(character)
		clearCache()
		updateCurrent(character)
	end)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	local gui = remotes and remotes:WaitForChild("Gui", 10)
	local refresh = gui and gui:WaitForChild("RefreshViewport", 10)
	if not current(token) then return end
	assert(refresh and refresh:IsA("RemoteEvent"), "AvatarPreview requires Gui.RefreshViewport")
	currentScope:Connect(refresh.OnClientEvent, function(source)
		if not current(token) then return end
		if source == "Player" then updateCurrent(player.Character)
		elseif typeof(source) == "Instance" and source:IsA("Model") and AvatarPreview.CurrentAvatar then
			appearanceToken += 1
			copyAppearance(AvatarPreview.CurrentAvatar, source)
			AvatarPreview.ViewportUpdated:Fire()
		end
	end)
	if player.Character then currentScope:Spawn(updateCurrent, player.Character) end
	currentScope:Spawn(function()
		local description = descriptionCopy(nil, player.UserId)
		if not description then return end
		if current(token) and AvatarPreview.DefaultAvatar then
			local target = AvatarPreview.DefaultAvatar:FindFirstChildOfClass("Humanoid")
			if target then applyDescription(description, target) end
		end
		description:Destroy()
	end)
end

function AvatarPreview:RevertToDefaultDescription(source: any, target: Humanoid, userId: number?)
	if not initialized then self.Init({}) end
	if target.Parent then target.Parent:SetAttribute("AvatarType", nil) end
	applyDescription(source, target, userId)
end

function AvatarPreview:CreateModelFromDescription(description: HumanoidDescription): Model
	if not initialized then self.Init({}) end
	local model = rig()
	model.Parent = cacheFolder
	local target = model:FindFirstChildOfClass("Humanoid")
	assert(target, "ViewportRig requires a Humanoid")
	applyDescription(description, target)
	return model
end

function AvatarPreview:ApplyDescription(target: any, source: any, key: number?)
	if not initialized then self.Init({}) end
	local humanoid = humanoidOf(target)
	if not humanoid or not humanoid.Parent then return end
	humanoid.Parent:SetAttribute("AvatarType", nil)
	applyDescription(source, humanoid, nil, if cacheKeyValid(key) then key else nil)
end

function AvatarPreview:WriteNewDesc(description: HumanoidDescription, key: number?)
	if not initialized then self.Init({}) end
	if typeof(description) ~= "Instance" or not description:IsA("HumanoidDescription")
		or not cacheKeyValid(key) or AvatarPreview.DescCache[key] then return end
	cacheCopy(key :: number, description)
end

function AvatarPreview:ApplyModelDescription(target: Model, source: Model)
	copyAppearance(target, source)
end

function AvatarPreview:CreateModelFromCharacter(character: Model): Model
	local model = rig()
	copyAppearance(model, character)
	return model
end

function AvatarPreview.GetCurrentAvatar(): Model? return AvatarPreview.CurrentAvatar end
function AvatarPreview.GetDefaultAvatar(): Model? return AvatarPreview.DefaultAvatar end

function AvatarPreview.Destroy()
	if not initialized then return end
	initialized = false
	generation += 1
	appearanceToken += 1
	scope:Destroy()
	clearCache()
	if cacheFolder then cacheFolder:Destroy(); cacheFolder = nil end
	if AvatarPreview.ViewportUpdated then AvatarPreview.ViewportUpdated:Destroy(); AvatarPreview.ViewportUpdated = nil end
	AvatarPreview.CurrentAvatar = nil
	AvatarPreview.DefaultAvatar = nil
	AvatarPreview.IsConnected = false
	scope = nil
end

return AvatarPreview

