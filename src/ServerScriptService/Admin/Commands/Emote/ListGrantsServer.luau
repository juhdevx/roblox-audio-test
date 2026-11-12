--!strict
-- Defines the ListGrantsServer admin command.
-- EmoteGrantsServer
local ServerScriptService = game:GetService("ServerScriptService")

local EmoteService = require(ServerScriptService.Services.EmoteInventoryService)

return function(_, target)
	local list = EmoteService.GetOwned(target)
	if #list == 0 then return target.Name .. " não tem emotes." end
	return target.Name .. " (" .. #list .. "): " .. table.concat(list, ", ")
end
