--!strict
-- Owns bounded friend-description caches and fetch scheduling per player.
local Players = game:GetService("Players")
local Maid = require(game:GetService("ReplicatedStorage").Shared.Utils.Maid)
local limits = require(game:GetService("ServerStorage").Config.EffectServerConfig)
local CONFIG = {MaxFriendsFetched=limits.MAX_FRIENDS, InitialDescriptionPreload=limits.PRELOAD, PrefetchAheadCount=limits.PREFETCH, DescriptionRetryAttempts=limits.RETRIES, DescriptionRetryDelay=limits.RETRY_DELAY, MaxDescriptionsPerPool=limits.CACHE_LIMIT, MaxConcurrentFetches=limits.CONCURRENCY}
local SettingsService: any
local maid = Maid.new()
local Service = {}
type Pool = {
    closed: boolean?,
	friendsList: { number },
	descriptions: { [number]: HumanoidDescription },
	currentIndex: number,
	_fetchCount: number,
}

local playerFriendPools: { [number]: Pool } = {}

-- NOVO: fila global de fetches em andamento
local activeFetches = 0
local fetchQueue: { { userId: number, callback: (HumanoidDescription?) -> () } } = {}

local function processFetchQueue()
	while activeFetches < CONFIG.MaxConcurrentFetches and #fetchQueue > 0 do
		local job = table.remove(fetchQueue, 1)
		if job then
			activeFetches += 1
			task.spawn(function()
				local desc = nil
				for attempt = 1, CONFIG.DescriptionRetryAttempts do
					local ok, result = pcall(function()
						return Players:GetHumanoidDescriptionFromUserIdAsync(job.userId)
					end)
					if ok and result then
						desc = result
						break
					end
					if attempt < CONFIG.DescriptionRetryAttempts then
						task.wait(CONFIG.DescriptionRetryDelay)
					end
				end
				activeFetches -= 1
				job.callback(desc)
				processFetchQueue()
			end)
		end
	end
end

local function fetchDescriptionAsync(userId: number, callback: (HumanoidDescription?) -> ())
	table.insert(fetchQueue, { userId = userId, callback = callback })
	processFetchQueue()
end

-- ============================================================
-- Helpers (mantidos)
-- ============================================================

local function shuffleTable(t: { number })
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
end

local function warmDescriptions(pool: Pool, ids: { number })
	for _, id in ipairs(ids) do
		if not pool.descriptions[id] then
			-- NOVO: cap no número de descriptions
			if pool._fetchCount >= CONFIG.MaxDescriptionsPerPool then
				break
			end
			pool._fetchCount += 1
			fetchDescriptionAsync(id, function(desc)
				if desc and pool.descriptions and not pool.closed then
					pool.descriptions[id] = desc
                elseif desc then desc:Destroy()
				end
			end)
		end
	end
end

-- ============================================================
-- Cache de amigos por player (mantido)
-- ============================================================

local function initPlayerCache(player: Player)
	if playerFriendPools[player.UserId] then return end

	local pool: Pool = {
		friendsList = {},
		descriptions = {},
		currentIndex = 1,
		_fetchCount = 0,
	}
	playerFriendPools[player.UserId] = pool

	task.spawn(function()
		local success, pages = pcall(function()
			return Players:GetFriendsAsync(player.UserId)
		end)

		local friendsList = {}
		if success and pages then
			while true do
				for _, item in ipairs(pages:GetCurrentPage()) do
					table.insert(friendsList, item.Id)
					if #friendsList >= CONFIG.MaxFriendsFetched then break end
				end
				if pages.IsFinished or #friendsList >= CONFIG.MaxFriendsFetched then break end
				local advanced = pcall(function() pages:AdvanceToNextPageAsync() end)
				if not advanced then break end
			end
		end

		if #friendsList == 0 then
			table.insert(friendsList, player.UserId)
		else
			shuffleTable(friendsList)
		end

		if pool.closed then return end
		pool.friendsList = friendsList

		local preloadIds = {}
		for i = 1, math.min(CONFIG.InitialDescriptionPreload, #friendsList) do
			table.insert(preloadIds, friendsList[i])
		end

		local chosenFriend = SettingsService.Get(player, "DummyFriend")
		if chosenFriend and not table.find(preloadIds, chosenFriend) then
			table.insert(preloadIds, chosenFriend)
		end

		warmDescriptions(pool, preloadIds)
	end)
end



local function getNextFriendId(player: Player, pool: Pool): number
	local chosenFriend = SettingsService.Get(player, "DummyFriend")
	if chosenFriend then
		return chosenFriend
	end

	if #pool.friendsList == 0 then
		return player.UserId
	end

	local friendId = pool.friendsList[pool.currentIndex]

	pool.currentIndex += 1
	if pool.currentIndex > #pool.friendsList then
		pool.currentIndex = 1
		shuffleTable(pool.friendsList)
	end

	local total = #pool.friendsList
	local aheadIds = {}
	for i = 1, math.min(CONFIG.PrefetchAheadCount, total) do
		local futureIndex = ((pool.currentIndex + i - 2) % total) + 1
		local id = pool.friendsList[futureIndex]
		if id then
			table.insert(aheadIds, id)
		end
	end
	warmDescriptions(pool, aheadIds)

	return friendId
end


local function remove(player: Player)
    local pool = playerFriendPools[player.UserId]
    if not pool then return end
    pool.closed = true
    for _, description in pairs(pool.descriptions) do description:Destroy() end
    table.clear(pool.descriptions)
    playerFriendPools[player.UserId] = nil
end
function Service.Init(dependencies: any) SettingsService = dependencies.SettingsService end
function Service.Start()
    maid:Add(Players.PlayerAdded:Connect(initPlayerCache))
    maid:Add(Players.PlayerRemoving:Connect(remove))
    for _, player in Players:GetPlayers() do initPlayerCache(player) end
end
function Service.GetDescription(player: Player): HumanoidDescription?
    local pool = playerFriendPools[player.UserId]
    if not pool then initPlayerCache(player); pool = playerFriendPools[player.UserId] end
    local id = getNextFriendId(player, pool)
    local cached = pool.descriptions[id]
    if cached then return cached:Clone() end
    local complete = Instance.new("BindableEvent")
    local done = false
    local result: HumanoidDescription? = nil
    local abandoned = false
    fetchDescriptionAsync(id, function(description)
        if abandoned or pool.closed then if description then description:Destroy() end; return end
        result = description; done = true; complete:Fire()
    end)
    local timeout = task.delay(8, function() if not done then done = true; complete:Fire() end end)
    if not done then complete.Event:Wait() end
    abandoned = true
    pcall(task.cancel, timeout); complete:Destroy()
    return result
end
function Service.Destroy()
    maid:Destroy()
    for _, player in Players:GetPlayers() do remove(player) end
    table.clear(fetchQueue)
end
return Service
