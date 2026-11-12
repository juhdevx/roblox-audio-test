--!strict
-- Encapsulates EmoteAudioController for a private playback context.
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
local Scope = require(game:GetService("ReplicatedStorage").Shared.Utils.Scope)
local ClientState = require(clientRoot.ClientState)
local Settings = require(clientRoot.Controllers.SettingsController)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local CONFIG = require(ReplicatedStorage.Shared.Config.PlaybackConfig)
local GetVFXFolder = require(ReplicatedStorage.Shared.Utils.GetVFXFolder)
local SetOtherPlayersVolume = require(clientRoot.Emotes.SoundVolume)

local Module = {}
function Module.new(context: any)
local self = context.State
local scope = context.Scope
local CurrentCamera = workspace.CurrentCamera
local api = {}
function api.RunRemoteSoundSyncLoop(sound: Sound, cacheKey: any, baseStart: number, songSpeed: number, songData: any)
	if not sound.IsLoaded then pcall(function() sound.Loaded:Wait() end) end
	local lStart = songData and songData.LoopStartTime
	local lEnd = songData and songData.LoopEndTime

	while not self.destroyed and sound.Parent and self.remoteSounds[cacheKey] == sound do
		local elapsed = self.syncCache:GetElapsed(cacheKey)
		if elapsed then
			local expectedSound = baseStart + (elapsed * songSpeed)
			local drift
			local currentEnd = (lEnd and lEnd > 0) and lEnd or sound.TimeLength

			if lStart and currentEnd > lStart then
				if expectedSound >= currentEnd then
					expectedSound = lStart + ((expectedSound - currentEnd) % (currentEnd - lStart))
				end
				drift = math.abs(sound.TimePosition - expectedSound)
			elseif sound.TimeLength > 0 then
				expectedSound = expectedSound % sound.TimeLength
				drift = context.CircularDrift(sound.TimePosition, expectedSound, sound.TimeLength)
			else
				drift = math.abs(sound.TimePosition - expectedSound)
			end

			if drift > CONFIG.SyncDriftThreshold then
				pcall(function() sound.TimePosition = expectedSound end)
			end
		end
		task.wait(CONFIG.SyncCorrectionInterval)
	end
end

function api.PlayRemoteSound(character: Model, songData: any, startTime: number?)
	if typeof(character) ~= "Instance" or character == self.character then return end
	if type(songData) ~= "table" or songData.Backend == "Spectral" then return end
	if workspace:GetAttribute("EmoteShowActive") == true
		and not character:GetAttribute("EmoteShowHost")
	then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	self:StopRemoteSound(character)

	local template = nil
	if songData.Template then
		local soundFolder = CONFIG.SoundFolder:FindFirstChild(songData.Template)
		template = soundFolder and soundFolder:FindFirstChildWhichIsA("Sound")
	end

	local sound: Sound
	if template then
		sound = template:Clone()
		sound.Looped = true
		sound:SetAttribute("Volume", sound.Volume)
	else
		sound = Instance.new("Sound")
		sound.SoundId = songData.SoundId
		sound:SetAttribute("Volume", songData.Volume)
		sound.Volume = songData.Volume
		sound.Looped = true
		sound.PlaybackSpeed = songData.PlaybackSpeed
	end
	sound.Parent = rootPart
	sound:AddTag("EmoteSound")

	local resolvedStartTime = startTime or workspace:GetServerTimeNow()
	self.syncCache:Set(character, { Song = songData }, resolvedStartTime)

	local baseStart = songData.StartTime or 0
	local songSpeed = songData.PlaybackSpeed or 1
	local elapsedGuess = math.max(workspace:GetServerTimeNow() - resolvedStartTime, 0) * songSpeed
	sound:Play()

	local lStart = songData.LoopStartTime
	local lEnd = songData.LoopEndTime
	local expectedSound = baseStart + elapsedGuess
	if lStart and (lEnd and lEnd > 0) and expectedSound >= lEnd then
		expectedSound = lStart + ((expectedSound - lEnd) % (lEnd - lStart))
	end
	pcall(function() sound.TimePosition = expectedSound end)
	self.remoteSounds[character] = sound
	self.remoteStart[character] = resolvedStartTime
	self.remoteBorn[character] = os.clock()

	if songData.LoopStartTime then
		scope:Spawn(function()
			local hasReachedLoop = false
			while sound and sound.Parent and self.remoteSounds[character] == sound do
				local currentEnd = (songData.LoopEndTime and songData.LoopEndTime > 0)
					and songData.LoopEndTime or sound.TimeLength
				if currentEnd > songData.LoopStartTime then
					if sound.TimePosition >= songData.LoopStartTime then hasReachedLoop = true end
					if sound.TimePosition >= currentEnd - 0.05 then
						sound.TimePosition = songData.LoopStartTime
					elseif hasReachedLoop and sound.Looped and sound.TimePosition < songData.LoopStartTime - 0.2 then
						sound.TimePosition = songData.LoopStartTime
					end
				end
				task.wait(0.05)
			end
		end)
	end
	scope:Spawn(function()
		self:RunRemoteSoundSyncLoop(sound, character, baseStart, songSpeed, songData)
	end)
end

function api.StopRemoteSound(character: Model)
	local sound = self.remoteSounds[character]
	if sound then
		pcall(function() sound:Stop() end)
		pcall(function() sound:Destroy() end)
		self.remoteSounds[character] = nil
	end
	self.remoteStart[character] = nil
	self.remoteBorn[character] = nil
	self.syncCache:Clear(character)
end

function api.SyncRemoteSounds()
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		local character = otherPlayer.Character
		if otherPlayer ~= LocalPlayer and character and character.Parent then
			local raw = character:GetAttribute("EmoteSound")
			if type(raw) == "string" then
				local ok, state = pcall(function() return HttpService:JSONDecode(raw) end)
				if ok and type(state) == "table"
					and type(state.Song) == "table"
                    and state.Song.Backend ~= "Spectral"
					and type(state.StartTime) == "number"
				then
					local knownStart = self.remoteStart[character]
					if not self.remoteSounds[character]
						or not knownStart
						or math.abs(knownStart - state.StartTime) > 0.05
					then
						self:PlayRemoteSound(character, state.Song, state.StartTime)
					end
				end
			end
		end
	end

	-- NOVO: pcall no StopRemoteSound
	for character in pairs(self.remoteSounds) do
		local gone = not character.Parent
		local stopped = not character:GetAttribute("EmoteSound")
		if gone or stopped then
			pcall(function() self:StopRemoteSound(character) end)
		end
	end
end

function api.PlayLocal(data: any, startTime: number, token: number, shouldSync: boolean, startDelay: number, silenced: boolean): Sound?
    if silenced then return nil end
    local SongResolver = require(ReplicatedStorage.Shared.Utils.SongResolver)
    local Clock = require(ReplicatedStorage.Shared.Utils.PlaybackClock)
    local song = SongResolver.Resolve(data, CONFIG.SoundFolder)
    if not song or song.Backend == "Spectral" then return nil end
    local templateFolder = song.Template and CONFIG.SoundFolder:FindFirstChild(song.Template)
    local template = templateFolder and templateFolder:FindFirstChildWhichIsA("Sound")
    local sound = if template then template:Clone() else Instance.new("Sound")
    sound.SoundId = song.SoundId or sound.SoundId
    sound.Volume = song.Volume or 1; sound:SetAttribute("Volume", sound.Volume)
    sound.PlaybackSpeed = song.PlaybackSpeed or 1; sound.Looped = true
    sound.Parent = self.rootPart; sound:AddTag("EmoteSound")
    self.currentSound = sound
    if shouldSync and startDelay > 0 then sound.TimePosition = 0
    else
        sound.TimePosition = if shouldSync then Clock.Position(math.max(workspace:GetServerTimeNow()-startTime,0),song,sound.TimeLength) else song.StartTime or 0
        sound:Play()
    end
    if song.LoopStartTime then
        scope:Spawn(function()
            local reached = false
            while not self.destroyed and sound.Parent and self.playbackToken == token do
                local first = song.LoopStartTime
                local last = if song.LoopEndTime and song.LoopEndTime > 0 then song.LoopEndTime else sound.TimeLength
                if last > first then
                    if sound.TimePosition >= first then reached = true end
                    if sound.TimePosition >= last-0.05 or (reached and sound.TimePosition < first-0.2) then sound.TimePosition=first end
                end
                task.wait(0.05)
            end
        end)
    end
    return sound
end

return api
end
return Module

