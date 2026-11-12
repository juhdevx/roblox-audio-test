--!strict
-- Revokes every non-default emote of the category from each target.
local ServerScriptService = game:GetService("ServerScriptService")
local Registry = require(game:GetService("ReplicatedStorage").Shared.Registries.EmoteRegistry)
local Inventory = require(ServerScriptService.Services.EmoteInventoryService)
local Notify = require(ServerScriptService.Admin.Modules.Notify)
return function(_context, targets: {Player}, category: string?)
	local key = category or "exclusive"
	local starters = Registry.StarterNames()
	local lines = {}
	for _, target in targets do
		local removed = 0
		for _, name in Registry.ByCategory(key) do
			if not table.find(starters, name) and Inventory.Revoke(target, name) then removed += 1 end
		end
		if removed > 0 then Notify.send(target, string.format("%d emotes removidos (%s).", removed, key), "warn") end
		table.insert(lines, string.format("%s: -%d (%s)", target.Name, removed, key))
	end
	return table.concat(lines, "\n")
end
