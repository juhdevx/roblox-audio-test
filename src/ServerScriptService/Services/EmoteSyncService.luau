--!strict
-- Validates sync joins and owns prompts, participants, and formation placement.
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config.EmoteConfig)
local Service = {}
local emotes: any
local inventory: any
local prompts: {[Model]: ProximityPrompt} = {}
local participants: {[Model]: {[Player]: number}} = {}
function Service.Init(dependencies: any)
    emotes = dependencies.EmoteService
    inventory = dependencies.EmoteInventoryService
end
function Service.Validate(player: Player, definition: any, host: Model): boolean
    local character = player.Character
    if not character or character == host then return false end
    local hostPlayer = Players:GetPlayerFromCharacter(host)
    local session = hostPlayer and emotes.GetSession(hostPlayer)
    if not session or session.Character ~= host or session.Host or session.Name ~= definition.Name or not definition.Syncable then return false end
    if Config.REQUIRE_EXCLUSIVE_SYNC_OWNERSHIP and definition.Exclusive and not inventory.Owns(player, definition.Name) then return false end
    -- Ownership can yield while data loads; validate the same host session again.
    if emotes.GetSession(hostPlayer) ~= session or player.Character ~= character then return false end
    local sourceRoot = character:FindFirstChild("HumanoidRootPart")
    local hostRoot = host:FindFirstChild("HumanoidRootPart")
    local sourceHumanoid = character:FindFirstChildOfClass("Humanoid")
    local hostHumanoid = host:FindFirstChildOfClass("Humanoid")
    if not sourceRoot or not sourceRoot:IsA("BasePart") or not hostRoot or not hostRoot:IsA("BasePart") then return false end
    if not sourceHumanoid or sourceHumanoid.Health <= 0 or not hostHumanoid or hostHumanoid.Health <= 0 then return false end
    if (sourceRoot.Position - hostRoot.Position).Magnitude > Config.SYNC_DISTANCE then return false end
    local members = participants[host]
    if not members or members[player] then return false end
    local count = 0
    for _ in pairs(members) do count += 1 end
    return count < (definition.MaxParticipants or Config.MAX_PARTICIPANTS)
end
local function offsetFor(mode: string, index: number, maximum: number): Vector3
    local side = if index % 2 == 1 then 1 else -1
    local depth = math.ceil(index / 2)
    if mode == "V" then return Vector3.new(side * Config.FORMATION.V * depth, 0, Config.FORMATION.V * depth) end
    if mode == "Line" then return Vector3.new(side * Config.FORMATION.Line * depth, 0, 0) end
    if mode == "Circle" then
        local angle = index / math.max(maximum, 1) * math.pi * 2
        return Vector3.new(math.cos(angle) * Config.FORMATION.Circle, 0, math.sin(angle) * Config.FORMATION.Circle)
    end
    if mode == "Front" then return Vector3.new(0, 0, -Config.FORMATION.Front) end
    return Vector3.zero
end
function Service.CreatePrompt(session: any)
    local character = session.Character
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local folder = Instance.new("Folder")
    folder.Name = "EmoteParticipants"
    folder:SetAttribute("MaxParticipants", session.Data.MaxParticipants or Config.MAX_PARTICIPANTS)
    folder:SetAttribute("CurrentParticipants", 0)
    folder.Parent = character
    participants[character] = {}
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "EmotePrompt"; prompt.ActionText = "Sync"; prompt.ObjectText = session.Name
    prompt.MaxActivationDistance = Config.SYNC_DISTANCE; prompt.RequiresLineOfSight = false
    prompt:SetAttribute("Player", session.Player.Name)
    prompt:AddTag("EmotePrompt"); prompt.Parent = root
    prompts[character] = prompt
end
function Service.Join(player: Player, definition: any, host: Model): boolean
    if not Service.Validate(player, definition, host) then return false end
    local character = player.Character :: Model
    local members = participants[host]
    local count = 1
    local occupied: {[number]: boolean} = {}
    for _, index in pairs(members) do count += 1; occupied[index] = true end
    local slot = 1
    while occupied[slot] do slot += 1 end
    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
    local hostRoot = host:FindFirstChild("HumanoidRootPart") :: BasePart
    if definition.SyncMode ~= "Free" then
        root.CFrame = hostRoot.CFrame * CFrame.new(offsetFor(definition.SyncMode or "Lock", slot, definition.MaxParticipants or Config.MAX_PARTICIPANTS))
        root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
    end
    members[player] = slot
    local folder = host:FindFirstChild("EmoteParticipants") :: Folder
    local value = Instance.new("ObjectValue"); value.Value = player; value.Parent = folder
    folder:SetAttribute("CurrentParticipants", count)
    local target = Instance.new("ObjectValue"); target.Name = "SyncingWith"; target.Value = host; target.Parent = character
    return true
end
function Service.Leave(player: Player, host: Model)
    local members = participants[host]
    if members then members[player] = nil end
    local folder = host:FindFirstChild("EmoteParticipants")
    if folder then
        for _, value in folder:GetChildren() do if value:IsA("ObjectValue") and value.Value == player then value:Destroy() end end
        folder:SetAttribute("CurrentParticipants", #folder:GetChildren())
    end
end
function Service.GetParticipants(host: Model): {Player}
    local result = {}
    for player in pairs(participants[host] or {}) do table.insert(result, player) end
    return result
end
function Service.RemovePrompt(character: Model)
    if prompts[character] then prompts[character]:Destroy(); prompts[character] = nil end
    local folder = character:FindFirstChild("EmoteParticipants")
    if folder then folder:Destroy() end
    participants[character] = nil
end
function Service.Start() end
function Service.Destroy()
    for character in pairs(prompts) do Service.RemovePrompt(character) end
    table.clear(participants)
end
return Service
