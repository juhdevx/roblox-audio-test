--!strict
-- Lists online players ordered by tier (highest first).
local Players = game:GetService("Players")
local Permissions = require(game:GetService("ServerScriptService").Admin.Modules.Permissions)
return function(_context)
	local rows = {}
	for _, player in Players:GetPlayers() do
		table.insert(rows, {Name = player.Name, Id = player.UserId, Tier = Permissions.getTier(player)})
	end
	table.sort(rows, function(a, b) if a.Tier ~= b.Tier then return a.Tier > b.Tier end return a.Name < b.Name end)
	local lines = {}
	for _, row in rows do table.insert(lines, string.format("%s (%d) — %s", row.Name, row.Id, Permissions.tierName(row.Tier))) end
	return if #lines > 0 then table.concat(lines, "\n") else "Ninguém online."
end
