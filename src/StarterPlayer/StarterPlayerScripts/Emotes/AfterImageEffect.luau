--!strict
-- Encapsulates AfterImageEffect for a private playback context.
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
function api.RunAfterImageLoop(track: AnimationTrack, config: any, token: number)
	if self.destroyed or self.playbackToken ~= token then return end
	local beatInterval = config.BeatInterval or CONFIG.AfterImageBeatInterval
	local fadeDuration = config.FadeDuration or CONFIG.AfterImageFadeDuration
	local growScale = config.GrowScale or CONFIG.AfterImageGrowScale
	local startTransparency = config.StartTransparency or CONFIG.AfterImageStartTransparency
	local endTransparency = config.EndTransparency or CONFIG.AfterImageEndTransparency

	while not self.destroyed and self.playbackToken == token and track.IsPlaying do
		-- NOVO: pcall no Clone
		local ok, ghost = pcall(function() return self.character:Clone() end)
		if ok and ghost then
			ghost.Name = "AfterImage_" .. self.character.Name
			for _, descendant in ipairs(ghost:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.CanCollide = false
					descendant.CanTouch = false
					descendant.CanQuery = false
					descendant.Anchored = true
					descendant.Massless = true
					descendant.Transparency = startTransparency
				elseif descendant:IsA("Decal") then
					descendant.Transparency = startTransparency
				elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
					descendant:Destroy()
				end
			end

			ghost.Parent = GetVFXFolder()
			local fadeInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

			local ghostHumanoid = ghost:FindFirstChildOfClass("Humanoid")
			if ghostHumanoid then
				pcall(function()
					TweenService:Create(ghost, fadeInfo, { Scale = growScale }):Play()
				end)
			end

			for _, descendant in ipairs(ghost:GetDescendants()) do
				if descendant:IsA("BasePart") or descendant:IsA("Decal") then
					TweenService:Create(descendant, fadeInfo, { Transparency = endTransparency }):Play()
				end
			end

			scope:Delay(fadeDuration, function()
				if ghost.Parent then ghost:Destroy() end
			end)
		end
		task.wait(beatInterval)
	end
end

return api
end
return Module
