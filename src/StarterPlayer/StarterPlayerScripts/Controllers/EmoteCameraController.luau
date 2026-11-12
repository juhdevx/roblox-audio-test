--!strict
-- Encapsulates EmoteCameraController for a private playback context.
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
function api.BindCamera(data: any, token: number)
CurrentCamera = workspace.CurrentCamera
	if data and data.DisableEmoteCamera then
		if self.emoteCamera then self.emoteCamera:Destroy() self.emoteCamera = nil end
		if self.emoteCheckConnection then self.emoteCheckConnection:Disconnect() self.emoteCheckConnection = nil end
		if self.humanoid then CurrentCamera.CameraSubject = self.humanoid end
	else
		if self.emoteCamera then self.emoteCamera:Destroy() end
		if self.emoteCheckConnection then self.emoteCheckConnection:Disconnect() end

		self.emoteCamera = context.CreateCamera(self.character)
		local frameCounter = 0
		self.emoteCheckConnection = scope:Connect(RunService.PreRender, function(deltaTime)
			if self.playbackToken ~= token then return end
			frameCounter += 1
			-- NOVO: checa estado só a cada N frames (perf)
			if frameCounter % CONFIG.ValidateEveryNFrames == 0 then
				if not context.ValidateEmoteState(self.character, self.state) then
					self:StopEmote()
					return
				end
			end

			if self.syncTarget and Settings.GetSnapshot() and Settings.GetSnapshot().AllowSyncing == false then
				self.syncTarget = nil
				context.SetSyncingWith(self.character, nil)
				self.currentSyncKey = nil
			end

			local syncFree = data and data.SyncMode == "Free"
			local canMove = (data and data.Traversal)
				or self.character:GetAttribute("Traversal")
				or syncFree
			if not canMove then
				local moveDir = self.humanoid:GetAttribute("direction") or self.humanoid.MoveDirection
				if moveDir.Magnitude > 0.2 then
					self:StopEmote()
					return
				end
			end
			if self.syncTarget then
				if not context.Exists(self.syncTarget)
					or not self.syncTarget:FindFirstChild("EmoteParticipants")
				then
					self:StopEmote()
					return
				end
			end

			local isIntroPlaying = (self.currentIntroTrack and self.currentIntroTrack.IsPlaying)
			local isLoopPlaying = not isIntroPlaying
			local useEmoteCamera = true
			if data and data.Follow then
				if data.Follow == "Intro" and isLoopPlaying then useEmoteCamera = false
				elseif data.Follow == "Loop" and isIntroPlaying then useEmoteCamera = false end
			end

			if not useEmoteCamera then
				if CurrentCamera.CameraSubject ~= self.humanoid then
					CurrentCamera.CameraSubject = self.humanoid
				end
				return
			end

			if not self.emoteCamera then return end
			local torso = self.character:FindFirstChild("Torso")
			local head = self.character:FindFirstChild("Head")
			if not torso or not head then return end

			local targetPos = (torso.CFrame * (ClientState.Get("shiftlock")
				and CFrame.new(0, 1.75, 0)
				or CFrame.new(0, 2, 0))).Position
			local targetCFrame = CFrame.lookAt(targetPos, head.Position)

			if CurrentCamera.CameraSubject ~= self.emoteCamera then
				CurrentCamera.CameraSubject = self.emoteCamera
				self.emoteCamera.CFrame = targetCFrame
			else
				local intensity = Settings.GetSnapshot() and Settings.GetSnapshot().EmoteCameraIntensity or 5
				local speed = 2 + ((intensity - 1) * 2)
				local reduceMotion = Settings.GetSnapshot() and Settings.GetSnapshot().ReduceMotion
				local easingStyle = reduceMotion and Enum.EasingStyle.Quad or Enum.EasingStyle.Back
				local alpha = 1 - math.exp(-speed * deltaTime)
				self.emoteCamera.CFrame = self.emoteCamera.CFrame:Lerp(
					targetCFrame,
					TweenService:GetValue(alpha, easingStyle, Enum.EasingDirection.Out)
				)
			end
		end)
	end
end

return api
end
return Module
