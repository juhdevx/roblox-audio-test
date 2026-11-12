--!strict
-- Loads validated player records and serializes revisioned saves per store/player.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(game:GetService("ServerStorage").Config.PersistenceConfig)
local Registry = require(Shared.Registries.EmoteRegistry)
local EmoteConfig = require(Shared.Config.EmoteConfig)
local Validator = require(Shared.Utils.SettingsValidator)
local Tables = require(Shared.Utils.TableUtils)
local Maid = require(Shared.Utils.Maid)
local Service = {}
local records: {[Player]: {[string]: any}} = {}
local stores: {[string]: any} = {}
local maid = Maid.new()
local started = false
local closing = false

local function cleanInventory(saved: any): any
    local result = {OwnedEmotes = {}, EquippedSlots = {}}
    local owned = {}
    if type(saved) == "table" and type(saved.OwnedEmotes) == "table" then
        for _, name in saved.OwnedEmotes do
            if type(name) == "string" and Registry.Get(name) and not owned[name] then
                owned[name] = true; table.insert(result.OwnedEmotes, name)
            end
        end
    end
    for _, name in Registry.StarterNames() do
        if not owned[name] then owned[name] = true; table.insert(result.OwnedEmotes, name) end
    end
    local equipped = {}
    if type(saved) == "table" and type(saved.EquippedSlots) == "table" then
        for index = 1, EmoteConfig.MAX_SLOTS do
            local name = saved.EquippedSlots[tostring(index)] or saved.EquippedSlots[index]
            if type(name) == "string" and owned[name] and not equipped[name] then
                result.EquippedSlots[tostring(index)] = name; equipped[name] = true
            end
        end
    end
    if next(result.EquippedSlots) == nil then
        for index, name in Registry.StarterNames() do
            if index > EmoteConfig.MAX_SLOTS then break end
            result.EquippedSlots[tostring(index)] = name
        end
    end
    return result
end
local cleaners = {Inventory = cleanInventory, Settings = Validator.Clean}

local function retry(callback: () -> any): (boolean, any)
    local lastError
    for attempt = 1, Config.RETRIES do
        local ok, result = pcall(callback)
        if ok then return true, result end
        lastError = result
        if attempt < Config.RETRIES then task.wait(Config.RETRY_DELAY * attempt) end
    end
    return false, lastError
end

local function loadRecord(player: Player, kind: string): any
    local playerRecords = records[player]
    if not playerRecords then
        if closing or player.Parent ~= Players then return nil end
        playerRecords = {}; records[player] = playerRecords
    end
    local record = playerRecords[kind]
    if record then
        local deadline = os.clock() + Config.LOAD_TIMEOUT
        while record.status == "Loading" and os.clock() < deadline and records[player] == playerRecords do task.wait(0.05) end
        return if record.status ~= "Loading" then record else nil
    end
    record = {status = "Loading", data = nil, revision = 0, savedRevision = 0, saving = false, leaving = false, scheduled = nil}
    playerRecords[kind] = record
    local ok, saved = retry(function() return stores[kind]:GetAsync(Config.KEY_PREFIX .. player.UserId) end)
    if records[player] ~= playerRecords or record.leaving then record.status="Cancelled"; return nil end
    record.data = cleaners[kind](if ok then saved else nil)
    record.status = if ok then "Ready" else "Failed"
    if not ok then warn(`[PlayerData] {kind} load failed for {player.UserId}; writes disabled: {saved}`) end
    return record
end

local function saveRecord(player: Player, kind: string, record: any): boolean
    if record.status ~= "Ready" then return false end
    if record.saving then return false end
    if record.revision <= record.savedRevision then return true end
    record.saving = true
    local revision = record.revision
    local snapshot = Tables.Copy(record.data)
    local ok, err = retry(function()
        return stores[kind]:UpdateAsync(Config.KEY_PREFIX .. player.UserId, function(current)
            if kind == "Inventory" then
                local merged = if type(current) == "table" then Tables.Copy(current) else {}
                merged.OwnedEmotes = snapshot.OwnedEmotes
                merged.EquippedSlots = snapshot.EquippedSlots
                return merged
            end
            return snapshot
        end)
    end)
    record.saving = false
    if ok then record.savedRevision = revision
    else warn(`[PlayerData] {kind} save failed for {player.UserId}; revision retained: {err}`) end
    return ok
end

local function scheduleSave(player: Player, kind: string, record: any)
    if record.scheduled or record.leaving or closing then return end
    record.scheduled = task.delay(Config.SAVE_DEBOUNCE, function()
        record.scheduled = nil
        if records[player] and records[player][kind] == record then saveRecord(player, kind, record) end
    end)
end

function Service.Init(_dependencies: any)
    stores.Inventory = DataStoreService:GetDataStore(Config.INVENTORY_STORE)
    stores.Settings = DataStoreService:GetDataStore(Config.SETTINGS_STORE)
end
function Service.Get(player: Player, kind: string): any
    assert(cleaners[kind], "Unknown record kind")
    local record = loadRecord(player, kind)
    return if record and record.data then Tables.Copy(record.data) else nil
end
function Service.Update(player: Player, kind: string, transform: (any) -> any): boolean
    if closing then return false end
    local record = loadRecord(player, kind)
    if not record or record.status ~= "Ready" or record.leaving then return false end
    local candidate = transform(Tables.Copy(record.data))
    if candidate == nil then return false end
    record.data = candidate
    record.revision += 1
    scheduleSave(player, kind, record)
    return true
end
function Service.Status(player: Player, kind: string): string
    local record = records[player] and records[player][kind]
    return if record then record.status else "NotLoaded"
end
function Service.Flush(player: Player, deadline: number?): boolean
    local playerRecords = records[player]
    if not playerRecords then return true end
    local limit = deadline or os.clock() + Config.SHUTDOWN_TIMEOUT
    local success = true
    for kind, record in pairs(playerRecords) do
        if record.scheduled then pcall(task.cancel, record.scheduled); record.scheduled = nil end
        while (record.saving or record.status == "Loading") and os.clock() < limit do task.wait(0.05) end
        if record.status == "Ready" then
            while record.revision > record.savedRevision and os.clock() < limit do
                if not saveRecord(player, kind, record) then success = false; break end
            end
            if record.revision > record.savedRevision then success = false end
        end
    end
    return success
end
function Service.Start()
    if started then return end
    started = true
    local function added(player: Player)
        task.spawn(loadRecord, player, "Inventory")
        task.spawn(loadRecord, player, "Settings")
    end
    maid:Add(Players.PlayerAdded:Connect(added))
    maid:Add(Players.PlayerRemoving:Connect(function(player)
        local playerRecords = records[player]
        if playerRecords then for _, record in pairs(playerRecords) do record.leaving = true end end
        Service.Flush(player)
        records[player] = nil
    end))
    for _, player in Players:GetPlayers() do added(player) end
    maid:Add(task.spawn(function()
        while not closing do
            task.wait(Config.AUTOSAVE_INTERVAL)
            for player, playerRecords in pairs(records) do
                for kind, record in pairs(playerRecords) do
                    if not record.leaving then task.spawn(saveRecord, player, kind, record) end
                end
            end
        end
    end))
    game:BindToClose(function()
        closing = true
        local pending = 0
        local deadline = os.clock() + Config.SHUTDOWN_TIMEOUT
        for player in pairs(records) do
            pending += 1
            task.spawn(function() Service.Flush(player, deadline); pending -= 1 end)
        end
        while pending > 0 and os.clock() < deadline do task.wait(0.05) end
    end)
end
function Service.Destroy()
    closing = true
    maid:Destroy()
    for player in pairs(records) do Service.Flush(player) end
    table.clear(records)
end
return Service
