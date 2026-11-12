--!strict
-- Defines the GrantEmoteServer admin command.
-- GiveEmoteServer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EmoteService = require(ServerScriptService.Services.EmoteInventoryService)
local Notify = require(game:GetService("ServerScriptService").Admin.Modules.Notify)

return function(_, target, emote)
	local name = EmoteService.ResolveName(emote)
	if not name then return "Emote '" .. tostring(emote) .. "' não existe." end

	if not EmoteService.Grant(target, name) then
		return target.Name .. " já tem '" .. name .. "'."
	end

	Notify.send(target, "Emote liberado: " .. name, "success")
	return target.Name .. " recebeu '" .. name .. "'."
end
