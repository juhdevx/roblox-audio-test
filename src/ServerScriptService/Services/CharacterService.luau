--!strict
-- Owns player/character connections and stops sessions at character boundaries.
local Players = game:GetService("Players")
local Maid = require(game:GetService("ReplicatedStorage").Shared.Utils.Maid)
local Service = {}
local maid = Maid.new()
local players: {[Player]: any} = {}
local emotes: any
local viewport: RemoteEvent
function Service.Init(dependencies: any)
    emotes = dependencies.EmoteService; viewport = dependencies.RemoteService.Get("Gui", "UpdateViewport")
end
function Service.Start()
    local function added(player: Player)
        if players[player] then return end
        local playerMaid = Maid.new(); players[player] = playerMaid
        local characterMaid = playerMaid:Add(Maid.new())
        local function characterAdded(character: Model)
            characterMaid:Clean()
            characterMaid:Add(task.spawn(function()
                local humanoid = character:WaitForChild("Humanoid", 10)
                if player.Character ~= character or not humanoid or not humanoid:IsA("Humanoid") then return end
                characterMaid:Add(humanoid.Died:Connect(function() emotes.Stop(player) end))
            end))
        end
        playerMaid:Add(player.CharacterAdded:Connect(characterAdded))
        playerMaid:Add(player.CharacterRemoving:Connect(function() emotes.Stop(player); characterMaid:Clean() end))
        playerMaid:Add(player.CharacterAppearanceLoaded:Connect(function() viewport:FireClient(player) end))
        if player.Character then characterAdded(player.Character) end
    end
    maid:Add(Players.PlayerAdded:Connect(added))
    maid:Add(Players.PlayerRemoving:Connect(function(player)
        if players[player] then players[player]:Destroy(); players[player] = nil end
    end))
    for _, player in Players:GetPlayers() do added(player) end
end
function Service.Destroy()
    maid:Destroy()
    for player, playerMaid in pairs(players) do playerMaid:Destroy(); players[player] = nil end
end
return Service
