--!strict
-- Validates setting requests against the shared schema before storing them.
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage").Shared
local Validator = require(Shared.Utils.SettingsValidator)
local RateLimiter = require(Shared.Utils.RateLimiter)
local Maid = require(Shared.Utils.Maid)
local Signal = require(Shared.Utils.Signal)
local Service = {Changed = Signal.new()}
local dataService: any
local remotes: any
local maid = Maid.new()
local limiter = RateLimiter.new(20, 10)
local started = false
function Service.Init(dependencies: any)
    dataService = dependencies.PlayerDataService
    remotes = dependencies.RemoteService
end
function Service.GetAll(player: Player): {[string]: any}
    return dataService.Get(player, "Settings") or Validator.Clean(nil)
end
function Service.Get(player: Player, key: string, default: any): any
    local value = Service.GetAll(player)[key]
    return if value == nil then default else value
end
function Service.Set(player: Player, key: any, value: any): boolean
    if not Validator.Validate(key, value) then return false end
    local ok = dataService.Update(player, "Settings", function(data) data[key] = value; return data end)
    if ok then Service.Changed:Fire(player, key, value) end
    return ok
end
function Service.Start()
    if started then return end
    started = true
    local getAll = remotes.Get("Settings", "GetAllSettings")
    local getOne = remotes.Get("Settings", "GetSetting")
    getAll.OnServerInvoke = function(player)
        if not limiter:Allow(player, "Get") then return nil end
        return Service.GetAll(player)
    end
    getOne.OnServerInvoke = function(player, key)
        if not limiter:Allow(player, "Get") or type(key) ~= "string" then return nil end
        return Service.Get(player, key, nil)
    end
    maid:Add(function() getAll.OnServerInvoke = nil; getOne.OnServerInvoke = nil end)
    maid:Add(remotes.Get("Settings", "SetSetting").OnServerEvent:Connect(function(player, key, value)
        if limiter:Allow(player, "Set") then Service.Set(player, key, value) end
    end))
    maid:Add(Players.PlayerRemoving:Connect(function(player) limiter:Remove(player) end))
end
function Service.Destroy() maid:Destroy(); limiter:Destroy(); Service.Changed:Destroy() end
return Service
