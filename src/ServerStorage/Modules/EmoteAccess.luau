local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local store = DataStoreService:GetDataStore("EmoteAccess_v1")

local grants = {}
local changed = Instance.new("BindableEvent")

local EmoteAccess = {
	Changed = changed.Event, 
}

local function keyFor(userId)
	return "u_" .. userId
end

local function save(userId)
	local set = grants[userId]
	if not set then return end

	local list = {}
	for emote in pairs(set) do table.insert(list, emote) end
	table.sort(list)

	local ok, err = pcall(function() store:SetAsync(keyFor(userId), list) end)
	if not ok then warn("[EmoteAccess] Falha ao salvar:", err) end
end

local function load(player)
	local userId = player.UserId
	local ok, list = pcall(function() return store:GetAsync(keyFor(userId)) end)

	if not ok then
		warn("[EmoteAccess] Falha ao carregar", player.Name, list)
		return
	end

	local set = {}
	if type(list) == "table" then
		for _, emote in ipairs(list) do set[emote] = true end
	end
	grants[userId] = set
	changed:Fire(player)
end

function EmoteAccess.Has(player, emote)
	local set = player and grants[player.UserId]
	return set ~= nil and set[emote] == true
end

function EmoteAccess.GetGrants(player)
	local list = {}
	local set = player and grants[player.UserId]
	if set then
		for emote in pairs(set) do table.insert(list, emote) end
		table.sort(list)
	end
	return list
end

function EmoteAccess.Grant(player, emote)
	local set = player and grants[player.UserId]
	if not set then return false, "Dados do jogador indisponíveis." end
	if type(emote) ~= "string" or emote == "" then return false, "Nome de emote inválido." end
	if set[emote] then return false, "O jogador já tem esse emote." end

	set[emote] = true
	task.spawn(save, player.UserId)
	changed:Fire(player)
	return true
end

function EmoteAccess.Revoke(player, emote)
	local set = player and grants[player.UserId]
	if not set then return false, "Dados do jogador indisponíveis." end
	if not set[emote] then return false, "O jogador não tem esse emote." end

	set[emote] = nil
	task.spawn(save, player.UserId)
	changed:Fire(player)
	return true
end

function EmoteAccess.ClearAll(player)
	local set = player and grants[player.UserId]
	if not set then return false, "Dados do jogador indisponíveis." end

	table.clear(set)
	task.spawn(save, player.UserId)
	changed:Fire(player)
	return true
end

Players.PlayerAdded:Connect(load)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(load, player)
end

Players.PlayerRemoving:Connect(function(player)
	save(player.UserId)
	grants[player.UserId] = nil
end)

game:BindToClose(function()
	for userId in pairs(grants) do save(userId) end
end)

return EmoteAccess