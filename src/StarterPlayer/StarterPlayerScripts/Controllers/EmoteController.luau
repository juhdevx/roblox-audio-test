--!strict
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
local Scope = require(game:GetService("ReplicatedStorage").Shared.Utils.Scope)
local ClientState = require(clientRoot.ClientState)
local Settings = require(clientRoot.Controllers.SettingsController)
--!strict
-- Coordinates accepted emote playback through focused runtime modules.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Signal = require(ReplicatedStorage.Shared.Utils.Signal)
local Maid = require(ReplicatedStorage.Shared.Utils.Maid)
local SetOtherPlayersVolume = require(clientRoot.Emotes.SoundVolume)
local EmoteSyncCache = require(clientRoot.Emotes.EmoteSyncCache)
local AnimationLengthCache = require(clientRoot.Emotes.AnimationLengthCache)
local EmotePreloader = require(clientRoot.Emotes.EmotePreloader)
local GetVFXFolder = require(ReplicatedStorage.Shared.Utils.GetVFXFolder)

local EmoteController = {}
EmoteController.__index = EmoteController

local CONFIG = require(ReplicatedStorage.Shared.Config.PlaybackConfig)

local StateRemap = { [Enum.HumanoidStateType.RunningNoPhysics] = Enum.HumanoidStateType.Running }
local BlockedStates = {
	Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Flying, Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Jumping,
}

local PlayerRemote = ReplicatedStorage.Remotes.Player
local GetEmotes = PlayerRemote.GetEmotes
local StartEmote = PlayerRemote.StartEmote
local CurrentCamera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- Helpers (mantidos)
-- ============================================================

local function Exists(obj: any): boolean
	return typeof(obj) == "Instance" and obj:IsDescendantOf(workspace)
end

local function ValidateEmoteState(character: Model?, state: Enum.HumanoidStateType): boolean
	if not character or not Exists(character) then return false end
	if not character:FindFirstChild("Torso") then return false end
	if not character:FindFirstChild("HumanoidRootPart") then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not humanoid:IsDescendantOf(workspace) then return false end
	if humanoid.Health <= 0 then return false end
	if table.find(BlockedStates, state) then return false end
	if ClientState.Get("inBooth") then return false end
	if character:GetAttribute("InBooth") then return false end
	if humanoid:GetAttribute("ragdolled") then return false end
	if character:GetAttribute("Ziplining") then return false end
	return true
end

local function FindEmote(inventory: { any }, name: string): any?
	for _, data in ipairs(inventory) do
		if data.Name == name then return data end
	end
	return nil
end

local function CreateCamera(character: Model): BasePart
	local part = Instance.new("Part")
	part.Name = "emoteCamera"
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(1, 1, 1)
	part.Parent = character
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		part.CFrame = root.CFrame * CFrame.new(0, 2.5, 0)
	end
	return part
end

local function setSyncingWith(character: Model, target: Model?)
	local existing = character:FindFirstChild("SyncingWith")
	if existing then existing:Destroy() end
	if target then
		local ov = Instance.new("ObjectValue")
		ov.Name = "SyncingWith"
		ov.Value = target
		ov.Parent = character
	end
end

local function CircularDrift(a: number, b: number, length: number): number
	if length <= 0 then return math.abs(a - b) end
	local raw = math.abs(a - b)
	return math.min(raw, length - raw)
end

local function GetInventory(inventory: { any }, signal: any?)
	local ok, serverInventory = pcall(function()
		return GetEmotes:InvokeServer()
	end)
	if ok and type(serverInventory) == "table" then
        table.clear(inventory)
		for _, data in ipairs(serverInventory) do
			table.insert(inventory, data)
		end
	end
	if signal then signal:Fire() end
end

-- ============================================================
-- Build
-- ============================================================


function EmoteController.Build()
	local self = setmetatable({}, EmoteController)
	self.maid = Maid.new()
    self.scope = Scope.new()
    self.maid:Add(self.scope)
    local scope = self.scope
	self.equippedEmotes = {}
	self.inventory = {}
	self.syncTarget = nil
	self.inventorySignal = Signal.new()
	self.emotePrompts = {}
	self.remoteSounds = {}
	self.remoteStart = {}
	self.remoteBorn = {}
	self.syncCache = EmoteSyncCache.new()
	self.lengthCache = AnimationLengthCache.new()
	self.preloader = EmotePreloader.new(self.lengthCache, CONFIG.SoundFolder)
	self.currentSyncKey = nil
	self.player = LocalPlayer
	self.character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	self.humanoid = self.character:WaitForChild("Humanoid", 10) :: Humanoid
    assert(self.humanoid, "Character Humanoid missing")
	self.state = StateRemap[self.humanoid:GetState()] or self.humanoid:GetState()
	self.rootPart = self.character:WaitForChild("HumanoidRootPart", 10) :: BasePart
	self.currentTrack = nil
	self.currentIntroTrack = nil
	self.currentSound = nil
	self.currentSessionId = nil
	self.emoteNamePlaying = nil
	self.isMutingOthers = false
	self.playbackToken = 0
	self.destroyed = false
	local context = {State=self, Scope=self.scope, Exists=Exists, FindEmote=FindEmote, ValidateEmoteState=ValidateEmoteState, CircularDrift=CircularDrift, CreateCamera=CreateCamera, SetSyncingWith=setSyncingWith}
    self._audio = require(clientRoot.Controllers.EmoteAudioController).new(context)
    self._playback = require(clientRoot.Emotes.AnimationPlayback).new(context)
    self._afterImage = require(clientRoot.Emotes.AfterImageEffect).new(context)
    self._camera = require(clientRoot.Controllers.EmoteCameraController).new(context)
    self.otherPlayersVolumeBackup = type(SetOtherPlayersVolume) == "table"
		and SetOtherPlayersVolume.Get()
		or 1
	self.anchorWasSet = false

	local stateConn: RBXScriptConnection? = self.humanoid.StateChanged:Connect(function(_, newState)
		local mapped = StateRemap[newState] or newState
		if mapped ~= self.state then self.state = mapped end
	end)

	self.maid:GiveTask(LocalPlayer.CharacterAdded:Connect(function(char)
		if stateConn then stateConn:Disconnect() stateConn = nil end
		self:StopEmote(true)
		self.character = char
		self.humanoid = char:WaitForChild("Humanoid", 10) :: Humanoid
		self.rootPart = char:WaitForChild("HumanoidRootPart", 10) :: BasePart
		self.state = StateRemap[self.humanoid:GetState()] or self.humanoid:GetState()
		self.currentTrack = nil
		self.currentIntroTrack = nil
		self.currentSound = nil
		self.emoteNamePlaying = nil
		self.isMutingOthers = false
		self.anchorWasSet = false
		stateConn = self.humanoid.StateChanged:Connect(function(_, newState)
			local mapped = StateRemap[newState] or newState
			if mapped ~= self.state then self.state = mapped end
		end)
	end))

	self.maid:Add(function() if stateConn then stateConn:Disconnect() end end)
	-- Inventory preloading
	local function PreloadInventory()
		self.preloader:PreloadAll(self.inventory)
	end

	-- Recebe eventos do servidor
	self.maid:GiveTask(StartEmote.OnClientEvent:Connect(function(action, ...)
		if action == "StopEmote" then
			local noFire, sessionId = ...
			if sessionId ~= nil and sessionId ~= self.currentSessionId then return end
			self:StopEmote(noFire)
		elseif action == "RefreshInventory" then
			GetInventory(self.inventory, self.inventorySignal)
			PreloadInventory()
		elseif action == "PlaySound" then
			local character, songData, startTime = ...
			self:PlayRemoteSound(character, songData, startTime)
		elseif action == "StopSound" then
			local character = ...
			if typeof(character) == "Instance" then
				self:StopRemoteSound(character)
			end
		elseif action == "Rejected" then
			ClientState.Set("emoting", self.emoteNamePlaying ~= nil)
		elseif action == "Started" then
			local emoteName, emoteData, startTime, sessionId = ...
			self.currentSessionId = sessionId
			self:BeginPlayback(emoteName, emoteData, nil, startTime, false)
		elseif action == "SyncStart" then
			local emoteName, syncCharacter, startTime, emoteData, sessionId = ...
			self.currentSessionId = sessionId
			if Settings.GetSnapshot() and Settings.GetSnapshot().AllowSyncing == false then
				self:BeginPlayback(emoteName, emoteData, nil, startTime, false)
			else
				self:BeginPlayback(emoteName, emoteData, syncCharacter, startTime, true)
			end
		end
	end))

	-- Prompts de sync
	self.maid:GiveTask(ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
		if triggeringPlayer ~= LocalPlayer then return end
		local targetChar = self.emotePrompts[prompt]
		if not targetChar then return end
		local ownerName = prompt:GetAttribute("Player")
		if not ownerName or ownerName == LocalPlayer.Name then return end
		local model = prompt.Parent and prompt.Parent.Parent
		if not model or not model:IsA("Model") then return end
		if not model:FindFirstChild("Humanoid") then return end
		local emoteName = model:GetAttribute("Emoting")
		if not emoteName then return end
		self:Emote(emoteName, model)
	end))

	local function addPrompt(prompt: Instance)
		if prompt:IsA("ProximityPrompt")
			and prompt.Parent
			and prompt.Parent.Parent
			and prompt.Parent.Parent:IsA("Model")
		then
			self.emotePrompts[prompt] = prompt.Parent.Parent
		end
	end

	for _, prompt in ipairs(CollectionService:GetTagged("EmotePrompt")) do addPrompt(prompt) end
	self.maid:GiveTask(CollectionService:GetInstanceAddedSignal("EmotePrompt"):Connect(addPrompt))
	self.maid:GiveTask(CollectionService:GetInstanceRemovedSignal("EmotePrompt"):Connect(function(prompt)
		self.emotePrompts[prompt] = nil
	end))

	-- Jump cancela emote
	self.maid:GiveTask(UserInputService.JumpRequest:Connect(function()
		if ClientState.Get("emoting") then self:StopEmote() end
	end))

	-- Loop principal (com throttle NOVO)
	local frameCount = 0
	self.maid:GiveTask(RunService.PreRender:Connect(function(dt)
		frameCount += 1

		-- Prompts: atualiza toda frame (leve)
		for prompt, character in pairs(self.emotePrompts) do
			local participants = character:FindFirstChild("EmoteParticipants")
			if participants then
				local current = participants:GetAttribute("CurrentParticipants")
				local max = participants:GetAttribute("MaxParticipants")
				local otherPlayer = Players:GetPlayerFromCharacter(character)
				local blockGlobalSync = Settings.GetSnapshot() and Settings.GetSnapshot().AllowSyncing == false
				local disabled = prompt:GetAttribute("Player") == LocalPlayer.Name
					or self.syncTarget == character
					or blockGlobalSync
					or (otherPlayer and otherPlayer:GetAttribute("SYNCING_DISABLED"))

				prompt.Enabled = not disabled and (current or 0) < (max or 0)
			end
		end

		-- Validação do emote: roda a cada N frames (NOVO)
		if self.emoteCheckConnection and frameCount % CONFIG.ValidateEveryNFrames == 0 then
			-- Esse bloco é chamado pelo connection específico abaixo — mantido vazio aqui
		end
	end))

	-- Inventário inicial — ✅ FIX CRÍTICO: passa o signal
	GetInventory(self.inventory, self.inventorySignal)
	PreloadInventory()

    local soundScopes = {}
    local function watchPlayer(player)
        if player == LocalPlayer or soundScopes[player] then return end
        local owner = Scope.new(); soundScopes[player] = owner; self.maid:Add(owner)
        local characterScope = nil
        local function watchCharacter(character)
            if characterScope then characterScope:Destroy() end
            characterScope = Scope.new(); owner:Add(characterScope)
            characterScope:Connect(character:GetAttributeChangedSignal("EmoteSound"), function() self:SyncRemoteSounds() end)
            characterScope:Connect(character.ChildAdded, function(child) if child.Name == "HumanoidRootPart" then self:SyncRemoteSounds() end end)
            self:SyncRemoteSounds()
        end
        owner:Connect(player.CharacterAdded, watchCharacter)
        owner:Connect(player.CharacterRemoving, function(character) self:StopRemoteSound(character); if characterScope then characterScope:Destroy() end end)
        if player.Character then watchCharacter(player.Character) end
    end
    self.scope:Connect(Players.PlayerAdded,watchPlayer)
    self.scope:Connect(Players.PlayerRemoving,function(player) if soundScopes[player] then soundScopes[player]:Destroy(); soundScopes[player]=nil end end)
    self.scope:Connect(workspace:GetAttributeChangedSignal("EmoteShowActive"),function() self:SyncRemoteSounds() end)
    for _, player in Players:GetPlayers() do watchPlayer(player) end

	return self
end

function EmoteController:BeginPlayback(emoteName: string, data: any, syncCharacter: Model?, startTime: number, shouldSync: boolean)
	CurrentCamera = workspace.CurrentCamera
	self.syncTarget = syncCharacter or nil
	if syncCharacter then setSyncingWith(self.character, syncCharacter) end

	ClientState.Set("emoting", true)
	ClientState.Set("emoting", true)

	self.playbackToken += 1
	local token = self.playbackToken
	local cacheKey = syncCharacter or self.character
	self.currentSyncKey = shouldSync and cacheKey or nil

	self:PlayEmote(emoteName, data, startTime, cacheKey, token, shouldSync)

	self._camera.BindCamera(data, token)
end

function EmoteController:StopEmote(noFire: boolean?)
	self.currentSessionId = nil
	require(clientRoot.Controllers.MediaPreparationController).CancelPreparation()
	self.playbackToken += 1
	self:StopCurrentTrack()

	if self.anchorWasSet then
		self.rootPart.Anchored = false
		self.anchorWasSet = false
	end
	if self.currentSyncKey then
		self.syncCache:Clear(self.currentSyncKey)
		self.currentSyncKey = nil
	end
	if self.isMutingOthers then
		SetOtherPlayersVolume(self.otherPlayersVolumeBackup or 1)
		self.isMutingOthers = false
	end

	ClientState.Set("emoting", false)

	if self.syncTarget then
		self.syncTarget = nil
		setSyncingWith(self.character, nil)
	end
	if self.emoteCamera then
		self.emoteCamera:Destroy()
		self.emoteCamera = nil
	end
	if self.emoteCheckConnection then
		self.emoteCheckConnection:Disconnect()
		self.emoteCheckConnection = nil
	end
	if self.humanoid then
		workspace.CurrentCamera.CameraSubject = self.humanoid
	end

	ClientState.Set("emoting", false)
	if not noFire then
		StartEmote:FireServer("Stop")
	end
end

function EmoteController:Emote(emoteName: string, syncCharacter: Model?)
	if ClientState.Get("emoting") or not ValidateEmoteState(self.character, self.state) then return end
	local data = FindEmote(self.inventory, emoteName)
	if not data and not syncCharacter then return end
	if syncCharacter and not syncCharacter:FindFirstChild("EmoteParticipants") then return end
	if syncCharacter and Settings.GetSnapshot() and Settings.GetSnapshot().AllowSyncing == false then return end

	ClientState.Set("emoting", true)
    if data and data.Song and data.Song.Backend == "Spectral" then
        local generation = self.playbackToken
        self.scope:Spawn(function()
            local ready = require(clientRoot.Controllers.MediaPreparationController).EnsureReady(data.Song)
            if self.destroyed or generation ~= self.playbackToken or not ClientState.Get("emoting") then return end
            if not ready then
                ClientState.Set("emoting", false)
                local status = require(clientRoot.Controllers.MediaPreparationController).GetStatus()
                warn("[EmoteMedia] " .. (status.PreviewError or "Playback was cancelled."))
                return
            end
            StartEmote:FireServer(syncCharacter and "Sync" or "Play", emoteName, syncCharacter)
        end)
        return
    end
	StartEmote:FireServer(syncCharacter and "Sync" or "Play", emoteName, syncCharacter)
end

function EmoteController:IsEmoting(): boolean
	return ClientState.Get("emoting")
end

function EmoteController:Destroy()
	if self.destroyed then return end
	self.destroyed = true

	self:StopEmote(true)

	if self.emoteCamera then
		pcall(function() self.emoteCamera:Destroy() end)
		self.emoteCamera = nil
	end
	if self.emoteCheckConnection then
		self.emoteCheckConnection:Disconnect()
		self.emoteCheckConnection = nil
	end

	-- NOVO: limpa TODOS os sons remotos
	for character in pairs(self.remoteSounds) do
		pcall(function() self:StopRemoteSound(character) end)
	end

	-- NOVO: limpa prompts
	table.clear(self.emotePrompts)

	-- NOVO: restaura volume se ficou mutado
	if self.isMutingOthers then
		SetOtherPlayersVolume(self.otherPlayersVolumeBackup or 1)
		self.isMutingOthers = false
	end

	self.syncCache:Destroy()
	self.lengthCache:Destroy()
	self.preloader:Destroy()
	self.maid:Destroy()
	self.inventorySignal:Destroy()
end
function EmoteController:StopCurrentTrack(...) return self._playback.StopCurrentTrack(...) end
function EmoteController:RunSyncLoop(...) return self._playback.RunSyncLoop(...) end
function EmoteController:PlayEmote(...) return self._playback.PlayEmote(...) end
function EmoteController:RunAfterImageLoop(...) return self._afterImage.RunAfterImageLoop(...) end
function EmoteController:RunRemoteSoundSyncLoop(...) return self._audio.RunRemoteSoundSyncLoop(...) end
function EmoteController:PlayRemoteSound(...) return self._audio.PlayRemoteSound(...) end
function EmoteController:StopRemoteSound(...) return self._audio.StopRemoteSound(...) end
function EmoteController:SyncRemoteSounds(...) return self._audio.SyncRemoteSounds(...) end
local Controller = {}
local instance: any
local SettingsConnection: any
Controller.InventoryChanged = Signal.new()
function Controller.Init(_dependencies: any) end
function Controller.Start()
    if instance then return end
    instance = EmoteController.Build()
    instance.maid:Add(instance.inventorySignal:Connect(function() Controller.InventoryChanged:Fire() end))
    instance.maid:Add(Settings.Changed:Connect(function(key,value)
        if key == "OtherPlayersVolume" then
            if instance.isMutingOthers then instance.otherPlayersVolumeBackup=value else SetOtherPlayersVolume(value) end
        end
    end))
    SetOtherPlayersVolume(Settings.Get("OtherPlayersVolume") or 1)
end
function Controller:GetInventory(): {any}
    return require(ReplicatedStorage.Shared.Utils.TableUtils).Copy(if instance then instance.inventory else {})
end
function Controller:GetCharacter(): Model? return LocalPlayer.Character end
function Controller:GetHumanoid(): Humanoid? return LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") end
function Controller:GetPlayer(): Player return LocalPlayer end
function Controller:Emote(name: string, host: Model?) if instance then instance:Emote(name,host) end end
function Controller:StopEmote(noFire: boolean?) if instance then instance:StopEmote(noFire) end end
function Controller:IsEmoting(): boolean return instance ~= nil and instance:IsEmoting() end
function Controller.Destroy()
    if instance then instance:Destroy(); instance=nil end
    Controller.InventoryChanged:Destroy()
end
return Controller

