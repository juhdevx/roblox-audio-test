--!strict
-- Resolves server-side permission tiers from PermissionConfig.
-- Owners come only from PermissionConfig; Moderator/Staff can also be granted at runtime and persist.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Permissions = {}

local CONFIG = require(game:GetService("ServerStorage").Config.PermissionConfig)
local store = DataStoreService:GetDataStore("Ranks_v1")
local overrides: {[number]: number} = {}

Permissions.Tier = {
	User = 0,
	Moderator = 1,
	Staff = 2,
	Owner = 3,
}
Permissions.Names = {[0] = "User", [1] = "Moderator", [2] = "Staff", [3] = "Owner"}

local function idIn(player, list)
	if not player then return false end
	return table.find(list, player.UserId) ~= nil
end

local function load(player: Player)
	local ok, value = pcall(function() return store:GetAsync("u_" .. player.UserId) end)
	if not ok then warn("[Permissions] Falha ao carregar cargo de", player.Name, value); return end
	if type(value) == "number" and player.Parent then overrides[player.UserId] = math.clamp(value, 0, 2) end
end

function Permissions.getTier(player)
	if not player then return Permissions.Tier.User end
	if idIn(player, CONFIG.Owners) then return Permissions.Tier.Owner end
	local saved = overrides[player.UserId]
	if saved then return saved end
	if idIn(player, CONFIG.Staff) then return Permissions.Tier.Staff end
	if idIn(player, CONFIG.Moderators) then return Permissions.Tier.Moderator end
	return Permissions.Tier.User
end

function Permissions.tierName(tier: number): string
	return Permissions.Names[tier] or "User"
end

-- Persists a Moderator/Staff rank (tier 1-2) or removes it (tier 0). Owners cannot be changed here.
function Permissions.setRank(userId: number, tier: number): (boolean, string?)
	if tier < 0 or tier > 2 or tier % 1 ~= 0 then return false, "Cargo inválido (use user, moderator ou staff)." end
	if table.find(CONFIG.Owners, userId) then return false, "Owners são definidos no PermissionConfig." end
	local ok, err = pcall(function()
		if tier == 0 then store:RemoveAsync("u_" .. userId) else store:SetAsync("u_" .. userId, tier) end
	end)
	if not ok then return false, "DataStore: " .. tostring(err) end
	overrides[userId] = if tier == 0 then nil else tier
	return true, nil
end

Players.PlayerAdded:Connect(load)
for _, player in Players:GetPlayers() do task.spawn(load, player) end
Players.PlayerRemoving:Connect(function(player) overrides[player.UserId] = nil end)

function Permissions.isOwner(player)
	return Permissions.getTier(player) == Permissions.Tier.Owner
end

function Permissions.atLeast(player, tier)
	return Permissions.getTier(player) >= tier
end

function Permissions.addToList(listName, userId)
	local list = CONFIG[listName]
	if not list then return false end
	if table.find(list, userId) then return false end
	table.insert(list, userId)
	return true
end

function Permissions.removeFromList(listName, userId)
	local list = CONFIG[listName]
	if not list then return false end
	local idx = table.find(list, userId)
	if not idx then return false end
	table.remove(list, idx)
	return true
end

return Permissions
