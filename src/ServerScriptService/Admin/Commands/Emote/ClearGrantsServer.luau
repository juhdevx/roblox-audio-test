--!strict
-- Defines the ClearGrantsServer admin command.
-- ClearEmotesServer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EmoteService = require(ServerScriptService.Services.EmoteInventoryService)
local Notify = require(game:GetService("ServerScriptService").Admin.Modules.Notify)

return function(_, target)
	EmoteService.Reset(target)
	Notify.send(target, "Seus emotes voltaram ao padrão.", "warn")
	return "Emotes de " .. target.Name .. " resetados para o padrão."
end
