--!strict
-- Owns inventory/equipment rules and exposes copied snapshots to callers.
local Shared = game:GetService("ReplicatedStorage").Shared
local Registry = require(Shared.Registries.EmoteRegistry)
local Config = require(Shared.Config.EmoteConfig)
local Tables = require(Shared.Utils.TableUtils)
local Signal = require(Shared.Utils.Signal)
local Service = {Changed = Signal.new()}
local dataService: any
local remote: RemoteEvent
local function change(player: Player, transform: (any) -> any): boolean
    local ok = dataService.Update(player, "Inventory", transform)
    if ok then
        Service.Changed:Fire(player)
        if player.Parent then remote:FireClient(player, "RefreshInventory") end
    end
    return ok
end
function Service.Init(dependencies: any)
    dataService = dependencies.PlayerDataService
    remote = dependencies.RemoteService.Get("Player", "StartEmote")
end
function Service.GetSnapshot(player: Player): any
    return dataService.Get(player, "Inventory")
end
function Service.Owns(player: Player, name: string): boolean
    local data = Service.GetSnapshot(player)
    return data ~= nil and table.find(data.OwnedEmotes, name) ~= nil
end
function Service.GetOwned(player: Player): {string}
    local data = Service.GetSnapshot(player)
    local owned = if data then data.OwnedEmotes else {}
    table.sort(owned)
    return owned
end
function Service.GetInventory(player: Player): {any}
    local data = Service.GetSnapshot(player)
    if not data then return {} end
    local list = {}
    for _, entry in Registry.All() do
        if table.find(data.OwnedEmotes, entry.Name) then
            local copy = Tables.Copy(entry)
            copy.Loop = copy.Loop or copy.Loop1
            copy.equipped = false
            for slot, name in pairs(data.EquippedSlots) do
                if name == entry.Name then copy.equipped = true; copy.Slot = tonumber(slot); break end
            end
            table.insert(list, copy)
        end
    end
    return list
end
function Service.Equip(player: Player, name: string, slot: number): boolean
    if not Registry.Get(name) or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > Config.MAX_SLOTS then return false end
    return change(player, function(data)
        if not table.find(data.OwnedEmotes, name) then return nil end
        for key, value in pairs(data.EquippedSlots) do if value == name then data.EquippedSlots[key] = nil end end
        data.EquippedSlots[tostring(slot)] = name
        return data
    end)
end
function Service.Grant(player: Player, name: string): boolean
    if not Registry.Get(name) then return false end
    return change(player, function(data)
        if table.find(data.OwnedEmotes, name) then return nil end
        table.insert(data.OwnedEmotes, name)
        return data
    end)
end
function Service.Revoke(player: Player, name: string): boolean
    return change(player, function(data)
        local index = table.find(data.OwnedEmotes, name)
        if not index then return nil end
        table.remove(data.OwnedEmotes, index)
        for slot, value in pairs(data.EquippedSlots) do if value == name then data.EquippedSlots[slot] = nil end end
        return data
    end)
end
function Service.Reset(player: Player): boolean
    return change(player, function(_data)
        local result = {OwnedEmotes=Registry.StarterNames(), EquippedSlots={}}
        for index, name in result.OwnedEmotes do
            if index > Config.MAX_SLOTS then break end
            result.EquippedSlots[tostring(index)] = name
        end
        return result
    end)
end
function Service.Refresh(player: Player)
    Service.Changed:Fire(player)
    if player.Parent then remote:FireClient(player, "RefreshInventory") end
end
Service.ResolveName = Registry.ResolveName
function Service.Start() end
function Service.Destroy() Service.Changed:Destroy() end
return Service
