--!strict
-- Applies player collision policy through tracked part/character events.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local Maid = require(game:GetService("ReplicatedStorage").Shared.Utils.Maid)
local GROUP = "NoPlayerCollisions"
local Service = {}
local maid = Maid.new()
local playerScopes = {}
function Service.Init(_dependencies: any)
    pcall(function() PhysicsService:RegisterCollisionGroup(GROUP) end)
    PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
    PhysicsService:CollisionGroupSetCollidable(GROUP, "Default", true)
    pcall(function() PhysicsService:RegisterCollisionGroup("EmoteNoCollide") end)
    PhysicsService:CollisionGroupSetCollidable("EmoteNoCollide", "Default", false)
end
function Service.Start()
    local function added(player: Player)
        local scope = Maid.new(); playerScopes[player] = scope
        local characterScope = scope:Add(Maid.new())
        local function characterAdded(character: Model)
            characterScope:Clean()
            local partScopes = {}
            local function watch(part: Instance)
                if not part:IsA("BasePart") or partScopes[part] then return end
                local partScope = Maid.new(); partScopes[part] = partScope
                part.CollisionGroup = GROUP
                partScope:Add(part:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
                    if part.CollisionGroup ~= GROUP then part.CollisionGroup = GROUP end
                end))
            end
            characterScope:Add(function() for _, item in pairs(partScopes) do item:Destroy() end end)
            characterScope:Add(character.DescendantAdded:Connect(watch))
            characterScope:Add(character.DescendantRemoving:Connect(function(part)
                if partScopes[part] then partScopes[part]:Destroy(); partScopes[part] = nil end
            end))
            for _, part in character:GetDescendants() do watch(part) end
        end
        scope:Add(player.CharacterAdded:Connect(characterAdded))
        scope:Add(player.CharacterRemoving:Connect(function() characterScope:Clean() end))
        if player.Character then characterAdded(player.Character) end
    end
    maid:Add(Players.PlayerAdded:Connect(added))
    maid:Add(Players.PlayerRemoving:Connect(function(player)
        if playerScopes[player] then playerScopes[player]:Destroy(); playerScopes[player] = nil end
    end))
    for _, player in Players:GetPlayers() do added(player) end
end
function Service.Destroy()
    maid:Destroy()
    for player, scope in pairs(playerScopes) do scope:Destroy(); playerScopes[player] = nil end
end
return Service
