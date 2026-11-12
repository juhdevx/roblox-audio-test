--!strict
-- Persists the rank through Permissions.setRank and notifies the player when online.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Permissions = require(ServerScriptService.Admin.Modules.Permissions)
local Notify = require(ServerScriptService.Admin.Modules.Notify)
return function(context, userId: number, tier: number)
	if userId == context.Executor.UserId then return "Você não pode mudar o próprio cargo." end
	local ok, err = Permissions.setRank(userId, tier)
	if not ok then return "Falhou: " .. tostring(err) end
	local label = Permissions.tierName(tier)
	local player = Players:GetPlayerByUserId(userId)
	if player then Notify.send(player, "Seu cargo agora é " .. label .. ".", "info") end
	return string.format("%s (%d) agora é %s.", if player then player.Name else "UserId", userId, label)
end
