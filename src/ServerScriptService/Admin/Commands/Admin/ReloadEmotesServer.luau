--!strict
-- Defines the ReloadEmotesServer admin command.
--!strict
-- Refreshes inventory/catalog views through the authoritative inventory API.
local Players = game:GetService("Players")
local Inventory = require(game:GetService("ServerScriptService").Services.EmoteInventoryService)
local Notify = require(game:GetService("ServerScriptService").Admin.Modules.Notify)
return function(_context)
    for _, player in Players:GetPlayers() do Inventory.Refresh(player) end
    Notify.broadcast("Emote inventory and catalog views refreshed.", "info")
    return "Emote inventory and catalog views refreshed."
end
