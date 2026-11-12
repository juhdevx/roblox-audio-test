--!strict
-- Owns accepted emote sessions; all requests pass server authority checks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Shared = ReplicatedStorage.Shared
local Registry = require(Shared.Registries.EmoteRegistry)
local Config = require(Shared.Config.EmoteConfig)
local Tables = require(Shared.Utils.TableUtils)
local Signal = require(Shared.Utils.Signal)
local Maid = require(Shared.Utils.Maid)
local RateLimiter = require(Shared.Utils.RateLimiter)
local DuoResolver = require(Shared.Utils.DuoEmoteResolver)
local SongResolver = require(Shared.Utils.SongResolver)
local Service = {Started=Signal.new(), Stopped=Signal.new()}
local sessions: {[Player]: any} = {}
local pending: {[Player]: number} = {}
local nextId = 0
local inventory: any
local sync: any
local remotes: any
local remote: RemoteEvent
local maid = Maid.new()
local limiter = RateLimiter.new(Config.RATE_TOKENS, Config.RATE_REFILL)
local started = false
function Service.Init(dependencies: any)
    inventory = dependencies.EmoteInventoryService; sync = dependencies.EmoteSyncService
    remotes = dependencies.RemoteService; remote = remotes.Get("Player", "StartEmote")
end
function Service.GetSession(player: Player): any return sessions[player] end
local function validCharacter(player: Player, character: Model?): boolean
    if player.Parent ~= Players or not character or player.Character ~= character or not character:IsDescendantOf(workspace) then return false end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") ~= nil
end
local function startSession(player: Player, name: string, host: Model?, force: boolean?): boolean
    local definition = Registry.Get(name)
    local character = player.Character
    if not definition or sessions[player] or not validCharacter(player, character) then return false end
    local token = (pending[player] or 0) + 1; pending[player] = token
    if host then
        if not sync.Validate(player, definition, host) then return false end
    elseif not force and not inventory.Owns(player, name) then return false end
    if pending[player] ~= token or sessions[player] or not validCharacter(player, character) then return false end
    local hostPlayer = host and Players:GetPlayerFromCharacter(host)
    local hostSession = hostPlayer and sessions[hostPlayer]
    if host and (not hostSession or hostSession.Name ~= name) then return false end
    local data = Tables.Copy(definition)
    if data.Loop1 and data.Loop2 then
        if hostSession then
            data.Loop = if data.SwapRoles == false then hostSession.Data.Loop else DuoResolver.GetOppositeLoop(hostSession.Data.Loop, data)
        else data.Loop = DuoResolver.ResolveSoloLoop(player, data) end
    end
    data.SyncMode = data.SyncMode or "Lock"
    if host and not sync.Join(player, definition, host) then return false end
    if pending[player] ~= token or sessions[player] or not validCharacter(player,character) or (hostPlayer and sessions[hostPlayer] ~= hostSession) then
        if host then sync.Leave(player,host) end
        return false
    end
    nextId += 1
    local session = {Id=nextId, Player=player, Character=character, Name=name, Data=data,
        StartTime=if hostSession then hostSession.StartTime else workspace:GetServerTimeNow(), Host=host}
    sessions[player] = session
    character:SetAttribute("Emoting", name)
    if not host and data.Traversal then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        session.WalkSpeed = humanoid.WalkSpeed
        humanoid.WalkSpeed *= math.clamp(data.Speed or Config.DEFAULT_TRAVERSAL_SPEED, 0.1, 1)
    end
    if not host and data.Syncable then sync.CreatePrompt(session) end
    local song = SongResolver.Resolve(data, ReplicatedStorage.Assets.Sounds)
    if song then
        character:SetAttribute("EmoteSound", HttpService:JSONEncode({Song=song, StartTime=session.StartTime}))
        remote:FireAllClients("PlaySound", character, song, session.StartTime)
    end
    if host then remote:FireClient(player, "SyncStart", name, host, session.StartTime, data, session.Id)
    else remote:FireClient(player, "Started", name, data, session.StartTime, session.Id) end
    Service.Started:Fire(session)
    return true
end
function Service.RequestPlay(player: Player, name: string): boolean return startSession(player, name, nil) end
function Service.RequestSync(player: Player, name: string, host: Model): boolean return startSession(player, name, host) end
-- Admin path: plays any registered emote on the player, ignoring ownership (used by Cmdr playemote/showvideo).
function Service.ForcePlay(player: Player, name: string): boolean
    if sessions[player] then Service.Stop(player) end
    return startSession(player, name, nil, true)
end
function Service.Stop(player: Player)
    pending[player] = (pending[player] or 0) + 1
    local session = sessions[player]
    if not session then return end
    sessions[player] = nil
    for _, participant in sync.GetParticipants(session.Character) do Service.Stop(participant) end
    if session.Host then sync.Leave(player, session.Host) end
    sync.RemovePrompt(session.Character)
    local character = session.Character
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and session.WalkSpeed then humanoid.WalkSpeed = session.WalkSpeed end
    local target = character:FindFirstChild("SyncingWith")
    if target then target:Destroy() end
    character:SetAttribute("Emoting", nil); character:SetAttribute("EmoteSound", nil)
    remote:FireAllClients("StopSound", character)
    if player.Parent == Players then remote:FireClient(player, "StopEmote", true, session.Id) end
    Service.Stopped:Fire(session)
end
function Service.Start()
    if started then return end
    started = true
    local getEmotes = remotes.Get("Player", "GetEmotes")
    getEmotes.OnServerInvoke = function(player)
        if not limiter:Allow(player, "GetEmotes") then return nil end
        return inventory.GetInventory(player)
    end
    maid:Add(function() getEmotes.OnServerInvoke = nil end)
    maid:Add(remote.OnServerEvent:Connect(function(player, action, name, host)
        if not limiter:Allow(player, "StartEmote") then remote:FireClient(player, "Rejected"); return end
        if action == "Stop" then Service.Stop(player); return end
        if (action ~= "Play" and action ~= "Sync") or type(name) ~= "string" or #name > Config.MAX_NAME_LENGTH or not Registry.Get(name) then
            remote:FireClient(player, "Rejected"); return
        end
        local ok = false
        if action == "Play" then ok = Service.RequestPlay(player, name)
        elseif typeof(host) == "Instance" and host:IsA("Model") then ok = Service.RequestSync(player, name, host) end
        if not ok and player.Parent == Players then remote:FireClient(player, "Rejected") end
    end))
    maid:Add(remotes.Get("Player", "UpdateEmoteWheel").OnServerEvent:Connect(function(player, name, slot)
        if not limiter:Allow(player, "Equip") or type(name) ~= "string" or type(slot) ~= "number" then return end
        inventory.Equip(player, name, slot)
    end))
    maid:Add(Players.PlayerRemoving:Connect(function(player) Service.Stop(player); pending[player] = nil; limiter:Remove(player) end))
end
function Service.Destroy()
    for player in pairs(sessions) do Service.Stop(player) end
    maid:Destroy(); limiter:Destroy(); Service.Started:Destroy(); Service.Stopped:Destroy()
end
return Service
