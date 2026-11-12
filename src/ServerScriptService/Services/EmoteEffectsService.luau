--!strict
-- Runs registered effects only for accepted server sessions and owns every handle.
local Shared = game:GetService("ReplicatedStorage").Shared
local Maid = require(Shared.Utils.Maid)
local Tables = require(Shared.Utils.TableUtils)
local RegistryLoader = require(Shared.Utils.RegistryLoader)
local effectsRoot = script.Parent.Parent.Effects
local Service = {}
local emotes: any
local effectTypes: any
local configs: any
local active: {[number]: any} = {}
local maid = Maid.new()
local friendPool = require(effectsRoot.FriendAvatarPool)
local function stop(session: any)
    local scope = active[session.Id]
    if scope then active[session.Id] = nil; scope:Destroy() end
end
local function start(session: any)
    if emotes.GetSession(session.Player) ~= session then return end
    local config = configs[session.Name]
    if not config then return end
    local scope = Maid.new(); active[session.Id] = scope
    local handles = {}
    for index, entry in ipairs(config) do
        local effect = effectTypes[entry.Type]
        if not effect then warn(`[Effects] Unknown type {entry.Type}`); continue end
        local id = entry.Id or tostring(index)
        if entry.Action == "Stop" then
            local previous = handles[id]
            if previous then previous(); handles[id] = nil end
            continue
        end
        -- A plugin may yield. Its returned handle is cleaned if the session ended meanwhile.
        task.defer(function()
            if emotes.GetSession(session.Player) ~= session then return end
            local ok, state = pcall(effect.Start, session.Player, session.Character, Tables.Copy(entry.Params or {}))
            if not ok then warn(`[Effects] {entry.Type}: {state}`); return end
            if not state then return end
            local stopped = false
            local function dispose()
                if stopped then return end
                stopped = true
                local success, err = pcall(effect.Stop, state)
                if not success then warn(err) end
            end
            handles[id] = dispose
            scope:Add(dispose)
            if emotes.GetSession(session.Player) ~= session then dispose() end
        end)
    end
end
function Service.Init(dependencies: any)
    emotes = dependencies.EmoteService
    effectTypes = RegistryLoader.Load(effectsRoot.Types)
    configs = RegistryLoader.Load(effectsRoot.Emotes, "Name")
    friendPool.Init(dependencies)
    for _, effect in pairs(effectTypes) do if effect.Init then effect.Init(dependencies) end end
end
function Service.Start()
    friendPool.Start()
    maid:Add(emotes.Started:Connect(start))
    maid:Add(emotes.Stopped:Connect(stop))
end
function Service.Destroy()
    maid:Destroy()
    for id, scope in pairs(active) do scope:Destroy(); active[id] = nil end
    for _, effect in pairs(effectTypes) do if effect.Destroy then effect.Destroy() end end
    friendPool.Destroy()
end
return Service
