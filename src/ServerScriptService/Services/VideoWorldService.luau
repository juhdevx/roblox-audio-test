--!strict
-- Replaces an accepted video emote's visible avatar with a replicated, non-colliding screen.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.VideoSequence.Config)
local Catalog = require(script.Parent.Parent.VideoSequence.VideoCatalog)
local Scope = require(Shared.Utils.Scope)
local Service = {}
local scope: any
local owners: {[Player]: any} = {}
local screens: Folder?
local active = false
local settings: any
local function boundedScale(value: any): number
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return 1 end
	return math.clamp(value, Config.ScreenScaleMin, Config.ScreenScaleMax)
end
local function rootToFloor(character: Model, root: BasePart, humanoid: Humanoid): number
	local distance = math.max(0, humanoid.HipHeight) + root.Size.Y / 2
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = character:FindFirstChild("Left Leg") or character:FindFirstChild("Right Leg")
		distance += if leg and leg:IsA("BasePart") then leg.Size.Y else root.Size.Y
	end
	return distance
end
local function watchPlayer(player: Player)
	if owners[player] then return end
	local owner = Scope.new()
	owners[player] = owner
	local characterScope: any
	local restore: (() -> ())?
	local currentScale = 1
	local applyGeometry: (() -> ())?
	local function release()
		applyGeometry = nil
		if restore then restore(); restore = nil end
	end
	owner:Add(release)
	owner:Add(function() if characterScope then characterScope:Destroy() end end)
	owner:Connect(settings.Changed, function(changedPlayer: Player, name: string, value: any)
		if changedPlayer ~= player or name ~= "VideoScreenScale" then return end
		currentScale = boundedScale(value)
		if applyGeometry then applyGeometry() end
	end)
	owner:Spawn(function()
		local savedScale = settings.Get(player, "VideoScreenScale", 1)
		if not owner:IsAlive() then return end
		currentScale = boundedScale(savedScale)
		if applyGeometry then applyGeometry() end
	end)
	local function watchCharacter(character: Model)
		release()
		if characterScope then characterScope:Destroy() end
		characterScope = Scope.new()
		local key = ""
		local function refresh()
			local encoded = character:GetAttribute("EmoteSound")
			local ok, descriptor = pcall(function() return HttpService:JSONDecode(encoded :: string) end)
			local song = if ok and type(descriptor) == "table" then descriptor.Song else nil
			local track = if type(song) == "table" and type(song.Video) == "string" then Catalog.Manifest[song.Video] else nil
			local root = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not active or not track or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then key = ""; release(); return end
			if key == encoded then return end
			release()
			key = encoded :: string
			local saved: {[Instance]: any} = {}
			local added: RBXScriptConnection?
			local part = Instance.new("Part")
			part.Name = Config.ScreenPartName
			part.Color = Color3.new(0, 0, 0)
			part.Material = Enum.Material.SmoothPlastic
			part.CanCollide = false; part.CanTouch = false; part.CanQuery = false
			part.CastShadow = false; part.Massless = true
			part:SetAttribute("OwnerUserId", player.UserId)
			part:SetAttribute("VideoTrack", song.Video)
			part:SetAttribute("StartTime", descriptor.StartTime)
			part:SetAttribute("PlaybackSpeed", song.PlaybackSpeed or 1)
			local weld = Instance.new("Weld")
			weld.Name = "VideoScreenWeld"
			local geometryScope = Scope.new()
			local geometryQueued = false
			local function resize()
				if not root.Parent then return end
				local height = Config.ScreenHeight * currentScale
				part.Size = Vector3.new(height * track.Width / track.Height, height, 0.08)
				local offset = height / 2 - rootToFloor(character, root, humanoid) + Config.ScreenOffset
				weld.C0 = CFrame.new(0, offset, 0)
				part:SetAttribute("ScreenScale", currentScale)
			end
			local function queueGeometry()
				if geometryQueued then return end
				geometryQueued = true
				geometryScope:Defer(function() geometryQueued = false; resize() end)
			end
			resize()
			part.CFrame = root.CFrame * weld.C0
			weld.Part0 = root; weld.Part1 = part; weld.Parent = part
			applyGeometry = queueGeometry
			geometryScope:Connect(root:GetPropertyChangedSignal("Size"), queueGeometry)
			geometryScope:Connect(humanoid:GetPropertyChangedSignal("HipHeight"), queueGeometry)
			local leg = character:FindFirstChild("Left Leg") or character:FindFirstChild("Right Leg")
			if leg and leg:IsA("BasePart") then
				geometryScope:Connect(leg:GetPropertyChangedSignal("Size"), queueGeometry)
			end
			local target = Instance.new("ObjectValue")
			target.Name = "VideoEmoteScreen"; target.Value = part; target.Parent = character
			part.Parent = screens
			local function hide(object: Instance)
				if object:IsA("BasePart") or object:IsA("Decal") then
					saved[object] = {Property = "Transparency", Value = object.Transparency, Applied = 1}
					object.Transparency = 1
				elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
					or object:IsA("BillboardGui") or object:IsA("Highlight") then
					saved[object] = {Property = "Enabled", Value = (object :: any).Enabled, Applied = false}
					(object :: any).Enabled = false
				elseif object:IsA("Humanoid") then
					saved[object] = {Property = "DisplayDistanceType", Value = object.DisplayDistanceType,
						Applied = Enum.HumanoidDisplayDistanceType.None}
					object.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				end
			end
			for _, object in character:GetDescendants() do hide(object) end
			added = character.DescendantAdded:Connect(hide)
			restore = function()
				if applyGeometry == queueGeometry then applyGeometry = nil end
				geometryScope:Destroy()
				if added then added:Disconnect() end
				target:Destroy(); part:Destroy()
				for object, entry in saved do
					if object.Parent and (object :: any)[entry.Property] == entry.Applied then
						(object :: any)[entry.Property] = entry.Value
					end
				end
				table.clear(saved)
			end
		end
		characterScope:Connect(character:GetAttributeChangedSignal("EmoteSound"), refresh)
		characterScope:Connect(character.ChildAdded, function(child: Instance)
			if child.Name == "HumanoidRootPart" then refresh() end
		end)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then characterScope:Connect(humanoid.Died, function() key = ""; release() end) end
		refresh()
	end
	owner:Connect(player.CharacterAdded, watchCharacter)
	owner:Connect(player.CharacterRemoving, function() release(); if characterScope then characterScope:Destroy(); characterScope = nil end end)
	if player.Character then watchCharacter(player.Character) end
end
function Service.Init(dependencies: any)
	if scope then Service.Destroy() end
	settings = assert(dependencies.SettingsService, "VideoWorldService requires SettingsService")
	scope = Scope.new()
	local folder = workspace:FindFirstChild("VideoEmoteScreens")
	if folder then assert(folder:IsA("Folder"), "VideoEmoteScreens must be a Folder")
	else folder = Instance.new("Folder"); folder.Name = "VideoEmoteScreens"; folder.Parent = workspace end
	screens = folder :: Folder
end
function Service.Start()
	if active then return end
	active = true
	scope:Connect(Players.PlayerAdded, watchPlayer)
	scope:Connect(Players.PlayerRemoving, function(player: Player)
		if owners[player] then owners[player]:Destroy(); owners[player] = nil end
	end)
	for _, player in Players:GetPlayers() do watchPlayer(player) end
end
function Service.Destroy()
	active = false
	for player, owner in owners do owner:Destroy(); owners[player] = nil end
	if scope then scope:Destroy(); scope = nil end
	if screens and #screens:GetChildren() == 0 then screens:Destroy() end
	screens = nil
end
return Service
