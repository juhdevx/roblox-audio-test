--!strict
-- Encapsulates AnimationPlayback for a private playback context.
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
function api.StopCurrentTrack()
	if self.currentTrack then
		self.currentTrack:Stop(0.1)
		if self.currentTrack.Animation then self.currentTrack.Animation:Destroy() end
		self.currentTrack = nil
	end
	if self.currentIntroTrack then
		self.currentIntroTrack:Stop(0.1)
		if self.currentIntroTrack.Animation then self.currentIntroTrack.Animation:Destroy() end
		self.currentIntroTrack = nil
	end
	if self.currentSound then
		self.currentSound:Stop()
		self.currentSound:Destroy()
		self.currentSound = nil
	end
	self.emoteNamePlaying = nil
end

function api.RunSyncLoop(track, sound, data, cacheKey, token, startDelay, animSpeed)
	if self.destroyed or self.playbackToken ~= token then return end
	if sound and not sound.IsLoaded then
		pcall(function() sound.Loaded:Wait() end)
	end

	local songSpeed = (data.Song and data.Song.PlaybackSpeed) or (sound and sound.PlaybackSpeed) or 1
	local baseStart = (data.Song and data.Song.StartTime) or 0


	local INNER_TICK = 0.25

	while not self.destroyed and self.playbackToken == token do

		if not track or not track.Parent and not track.IsPlaying then

			if self.emoteNamePlaying == data.Name or self.currentTrack == track then
				pcall(function() track:Play(0, 1, animSpeed) end)
			end
		end

		local elapsed = self.syncCache:GetElapsed(cacheKey)
		if elapsed then
			local introLen = self.currentIntroTrack and self.currentIntroTrack.Length or 0
			local animLength = track.Length
			local soundTimeLength = sound and sound.TimeLength or 0


			if animLength > 0 then
				local inIntro = (introLen > 0 and elapsed < introLen / animSpeed)

				if inIntro then
					if self.currentIntroTrack and not self.currentIntroTrack.IsPlaying then
						pcall(function() self.currentIntroTrack:Play(0, 1, animSpeed) end)
					end
				else

					if self.currentIntroTrack and self.currentIntroTrack.IsPlaying then
						pcall(function() self.currentIntroTrack:Stop(0) end)
					end


					if not track.IsPlaying then
						pcall(function() track:Play(0, 1, animSpeed) end)
					end


					local expectedAnim = ((elapsed - (introLen / animSpeed)) * animSpeed) % animLength
					local currentPos = track.TimePosition
					local drift = math.abs(currentPos - expectedAnim)

					if drift > animLength * 0.5 then
						drift = animLength - drift
					end

					if drift > 0.15 then
						pcall(function() track.TimePosition = expectedAnim end)
					end
				end
			end

			if sound and sound.Parent then
				local lStart = data.Song and data.Song.LoopStartTime
				local lEnd = data.Song and data.Song.LoopEndTime
				local currentEnd = (lEnd and lEnd > 0) and lEnd or soundTimeLength

				if startDelay > 0 and animLength > 0 then
					local loopRealTime = animLength / animSpeed
					local loopElapsed = elapsed % loopRealTime
					if loopElapsed < startDelay then
						if sound.IsPlaying then sound:Pause() end
						sound.TimePosition = 0
					else
						if not sound.IsPlaying then
							sound.TimePosition = ((loopElapsed - startDelay) * songSpeed) % math.max(soundTimeLength, 0.001)
							sound:Play()
						else
							local expectedSound = ((loopElapsed - startDelay) * songSpeed)
							if soundTimeLength > 0 then expectedSound = expectedSound % soundTimeLength end
							local driftSound = math.abs(sound.TimePosition - expectedSound)
							if driftSound > soundTimeLength * 0.5 then
								driftSound = soundTimeLength - driftSound
							end
							if driftSound > 0.2 then
								pcall(function() sound.TimePosition = expectedSound end)
							end
						end
					end
				else
					if not sound.IsPlaying then sound:Play() end
					local expectedSound = baseStart + (elapsed * songSpeed)
					if lStart and currentEnd > lStart then
						if expectedSound >= currentEnd then
							expectedSound = lStart + ((expectedSound - currentEnd) % (currentEnd - lStart))
						end
						if math.abs(sound.TimePosition - expectedSound) > 0.2 then
							pcall(function() sound.TimePosition = expectedSound end)
						end
					elseif soundTimeLength > 0 then
						expectedSound = expectedSound % soundTimeLength
						local driftSound = math.abs(sound.TimePosition - expectedSound)
						if driftSound > soundTimeLength * 0.5 then
							driftSound = soundTimeLength - driftSound
						end
						if driftSound > 0.2 then
							pcall(function() sound.TimePosition = expectedSound end)
						end
					end
				end
			end
		end

		task.wait(INNER_TICK)
	end
end

function api.PlayEmote(emoteName: string, overrideData: any, startTime: number?, cacheKey: any, token: number, shouldSync: boolean)
	if self.emoteNamePlaying == emoteName then return end
	self:StopCurrentTrack()
	local data = overrideData or context.FindEmote(self.inventory, emoteName)
	if not data then return end
	if not self.humanoid or not self.humanoid.Parent then return end

	local silenced = workspace:GetAttribute("EmoteShowActive") == true
		and not self.character:GetAttribute("EmoteShowHost")

	if not silenced and not self.isMutingOthers then
		self.isMutingOthers = true
		self.otherPlayersVolumeBackup = type(SetOtherPlayersVolume) == "table"
			and SetOtherPlayersVolume.Get()
			or 1
		SetOtherPlayersVolume(0)
	end

	local resolvedStartTime = startTime or workspace:GetServerTimeNow()
	local sound: Sound? = nil
	local startDelay = 0
	local animSpeed = data.AnimSpeed or 1

	if data.Song then
		startDelay = data.Song.StartDelay or 0
	elseif CONFIG.SoundFolder then
		local soundFolder = CONFIG.SoundFolder:FindFirstChild(emoteName)
		if soundFolder then
			local template = soundFolder:FindFirstChildWhichIsA("Sound")
			if template then startDelay = template:GetAttribute("StartDelay") or 0 end
		end
	end
	if silenced then startDelay = 0 end

	shouldSync = shouldSync or (startDelay > 0)
	if shouldSync then self.syncCache:Set(cacheKey, data, resolvedStartTime) end

	if data.DisableEnvironmentCollision then
		if not self.anchorWasSet then
			self.rootPart.Anchored = true
			self.anchorWasSet = true
		end
	end

	-- Intro
	local introTrack: AnimationTrack? = nil
	if data.Intro then
		local introAnim = Instance.new("Animation")
		introAnim.AnimationId = data.Intro
		introTrack = self.humanoid.Animator:LoadAnimation(introAnim)
		introTrack.Looped = false
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = data.Loop
	local track = self.humanoid.Animator:LoadAnimation(anim)
	track.Looped = true

	self.currentTrack = track
	self.currentIntroTrack = introTrack
	self.emoteNamePlaying = emoteName
	ClientState.Set("emoting", true)
	local isVFXHidden = Settings.GetSnapshot() and (Settings.GetSnapshot().HideEmoteVFX or Settings.GetSnapshot().ReduceMotion)

	if introTrack then
		introTrack:Play(0, 1, animSpeed)
		scope:Connect(introTrack.Stopped, function()
			if self.currentIntroTrack == introTrack and self.emoteNamePlaying == emoteName then
				track:Play(0, 1, animSpeed)
				if data.AfterImage and not isVFXHidden then
					scope:Spawn(function() self:RunAfterImageLoop(track, data.AfterImage, token) end)
				end
			end
		end)
	else
		track:Play(0, 1, animSpeed)
		if data.AfterImage and not isVFXHidden then
			scope:Spawn(function() self:RunAfterImageLoop(track, data.AfterImage, token) end)
		end
	end

	sound = self._audio.PlayLocal(data, resolvedStartTime, token, shouldSync, startDelay, silenced)

	if shouldSync then
		scope:Spawn(function()
			local elapsed = math.max(workspace:GetServerTimeNow() - resolvedStartTime, 0)
			if elapsed > 0.2 then
				local introLen = 0
				if introTrack then
					while introTrack.Length <= 0 and self.playbackToken == token do task.wait(0.05) end
					introLen = introTrack.Length
				end
				local loopLen = 0
				if track then
					while track.Length <= 0 and self.playbackToken == token do task.wait(0.05) end
					loopLen = track.Length
				end

				if self.playbackToken == token then
					if introTrack and introLen > 0 and elapsed < (introLen / animSpeed) then
						pcall(function() introTrack.TimePosition = elapsed * animSpeed end)
					elseif loopLen > 0 then
						pcall(function()
							if introTrack then introTrack:Stop(0) end
							if not track.IsPlaying then track:Play(0, 1, animSpeed) end
							track.TimePosition = ((elapsed - (introLen / animSpeed)) * animSpeed) % loopLen
						end)
					end
				end
			end
		end)
		scope:Spawn(function()
			task.wait(CONFIG.SyncInitialCorrectionDelay)
			self:RunSyncLoop(track, sound, data, cacheKey, token, startDelay, animSpeed)
		end)
	end
	return track
end

return api
end
return Module
