--!strict
-- Grants every emote of the category to each target through the authoritative inventory API.
local ServerScriptService = game:GetService("ServerScriptService")
local Registry = require(game:GetService("ReplicatedStorage").Shared.Registries.EmoteRegistry)
local Inventory = require(ServerScriptService.Services.EmoteInventoryService)
local Notify = require(ServerScriptService.Admin.Modules.Notify)
return function(_context, targets: {Player}, category: string?)
	local key = category or "exclusive"
	local names = Registry.ByCategory(key)
	if #names == 0 then return "Nenhum emote na categoria '" .. key .. "'." end
	local lines = {}
	for _, target in targets do
		local given = 0
		for _, name in names do
			if Inventory.Grant(target, name) then given += 1 end
		end
		if given > 0 then Notify.send(target, string.format("Você recebeu %d emotes (%s).", given, key), "success") end
		table.insert(lines, string.format("%s: +%d novos de %d (%s)", target.Name, given, #names, key))
	end
	return table.concat(lines, "\n")
end
