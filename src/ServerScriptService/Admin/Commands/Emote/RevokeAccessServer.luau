--!strict
-- Defines the RevokeAccessServer admin command.
-- TakeEmoteServer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EmoteService = require(ServerScriptService.Services.EmoteInventoryService)
local Notify = require(game:GetService("ServerScriptService").Admin.Modules.Notify)

return function(_, target, emote)
	local name = EmoteService.ResolveName(emote)
	if not name then return "Emote '" .. tostring(emote) .. "' não existe." end

	if not EmoteService.Revoke(target, name) then
		return target.Name .. " não tem '" .. name .. "'."
	end

	Notify.send(target, "Emote removido: " .. name, "warn")
	return "Removido '" .. name .. "' de " .. target.Name .. "."
end
