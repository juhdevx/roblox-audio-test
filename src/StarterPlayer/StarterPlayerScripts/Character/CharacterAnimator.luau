--!strict
-- Owns character animation tracks and preserves Animate child overrides.
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
local Scope = require(game:GetService("ReplicatedStorage").Shared.Utils.Scope)
local ClientState = require(clientRoot.ClientState)
local Settings = require(clientRoot.Controllers.SettingsController)
local Module = {}
function Module.Start(character: Model, animationRoot: Instance)
local scope = Scope.new()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Figure = character
local Humanoid = Figure:WaitForChild("Humanoid",10)
local Animator = Humanoid:WaitForChild("Animator",10)


local DEFAULT_FADE_TIME = 0.25          -- For idle, walk, jump, climb, fall
local EMOTE_FADE_TIME = 0.5            -- Emote entry and exit
local TOOL_FADE_TIME = 0.15            -- Quick but still blended tool anims
local SPEED_SMOOTHING = 0.1            -- Speed interpolation factor

local pose = "Standing"

local FFlagUserAnimateRemoveEmoteChatHook
do
	local success, result = pcall(function()
		return UserSettings():IsUserFeatureEnabled("UserAnimateRemoveEmoteChatHook")
	end)
	FFlagUserAnimateRemoveEmoteChatHook = success and result
end

local function getRigScale()
	return Figure:GetScale()
end

-----------------------------------------------------------
-- Full Animation Data 
-----------------------------------------------------------
local animNames = require(game:GetService("ReplicatedStorage").Shared.Config.CharacterAnimations)
local dances = {"dance1", "dance2", "dance3"}
local emoteNames = { wave = false, point = false, dance1 = true, dance2 = true, dance3 = true, laugh = false, cheer = false }

-----------------------------------------------------------
-- Track Preloading & Management
-----------------------------------------------------------
local animTracks = {}         -- [animName] = table of AnimationTrack objects
local weightedTracks = {}     -- [animName] = { {track, weight}, ... }
local totalWeights = {}       -- [animName] = number


for _, track in ipairs(Animator:GetPlayingAnimationTracks()) do
	track:Stop(0)
	track:Destroy()
end

local function buildTrackPool(name, fileList)
	for _,track in ipairs(animTracks[name] or {}) do track:Stop(0); track:Destroy() end
	animTracks[name] = {}
	weightedTracks[name] = {}
	totalWeights[name] = 0


	local config = animationRoot:FindFirstChild(name)
	if config then
		for _, child in ipairs(config:GetChildren()) do
			if child:IsA("Animation") then
				local weight = 1
				local weightObj = child:FindFirstChild("Weight")
				if weightObj then weight = weightObj.Value end
				local track = Animator:LoadAnimation(child)
				track.Priority = Enum.AnimationPriority.Core
				table.insert(animTracks[name], track)
				table.insert(weightedTracks[name], {track = track, weight = weight})
				totalWeights[name] = totalWeights[name] + weight
			end
		end
	end


	if #animTracks[name] == 0 and fileList then
		for _, entry in ipairs(fileList) do
			local anim = Instance.new("Animation")
			anim.AnimationId = entry.id
			local track = Animator:LoadAnimation(anim)
			anim:Destroy()
			track.Priority = Enum.AnimationPriority.Core
			table.insert(animTracks[name], track)
			table.insert(weightedTracks[name], {track = track, weight = entry.weight})
			totalWeights[name] = totalWeights[name] + entry.weight
		end
	end
end

for name, fileList in pairs(animNames) do
	buildTrackPool(name, fileList)
end

scope:Connect(animationRoot.ChildAdded, function(child)
	if animNames[child.Name] then buildTrackPool(child.Name, animNames[child.Name]) end
end)
scope:Connect(animationRoot.ChildRemoved, function(child)
	if animNames[child.Name] then buildTrackPool(child.Name, animNames[child.Name]) end
end)

-----------------------------------------------------------
-- Weighted Random Track Selection
-----------------------------------------------------------
local function getRandomTrack(name)
	if not weightedTracks[name] or #weightedTracks[name] == 0 then return nil end
	local roll = math.random(1, totalWeights[name])
	for _, entry in ipairs(weightedTracks[name]) do
		if roll <= entry.weight then return entry.track end
		roll = roll - entry.weight
	end
	return weightedTracks[name][1].track
end

-----------------------------------------------------------
-- Main Animation Control (crossfade, no callbacks)
-----------------------------------------------------------
local currentAnimName = nil
local currentAnimTrack = nil
local targetAnimSpeed = 1.0
local currentAnimSpeed = 1.0

local function playAnimation(animName, fadeTime, priority)
	priority = priority or Enum.AnimationPriority.Core
	fadeTime = fadeTime or DEFAULT_FADE_TIME

	if currentAnimName == animName and currentAnimTrack and currentAnimTrack.IsPlaying then
		return
	end

	if currentAnimTrack then
		currentAnimTrack:Stop(fadeTime)
	end

	local newTrack = getRandomTrack(animName)
	if newTrack then
		newTrack.Priority = priority
		newTrack:Play(fadeTime)
		currentAnimTrack = newTrack
		currentAnimName = animName
		targetAnimSpeed = 1.0
		currentAnimSpeed = 1.0
	end
end

local function setAnimationSpeed(speed)
	targetAnimSpeed = speed
end


local function stopCurrentAnimation(fadeOut)
	fadeOut = fadeOut or 0.5
	if currentAnimTrack then
		currentAnimTrack:Stop(fadeOut)
		currentAnimTrack = nil
		currentAnimName = nil
	end
end

-----------------------------------------------------------
-- Tool Animation Control
-----------------------------------------------------------
local toolAnimName = ""
local toolAnimTrack = nil

local function playToolAnimation(animName, fadeTime, priority)
	fadeTime = fadeTime or TOOL_FADE_TIME
	if toolAnimTrack then
		toolAnimTrack:Stop(fadeTime)
	end
	local track = getRandomTrack(animName)
	if track then
		track.Priority = priority or Enum.AnimationPriority.Action
		track:Play(fadeTime)
		toolAnimTrack = track
		toolAnimName = animName
	end
end

local function stopToolAnimations()
	if toolAnimTrack then
		toolAnimTrack:Stop(TOOL_FADE_TIME)
		toolAnimTrack = nil
		toolAnimName = ""
	end
end

-----------------------------------------------------------
-- Emote Handling (BindableFunction + Legacy Chat)
-----------------------------------------------------------
animationRoot:WaitForChild("PlayEmote",10).OnInvoke = function(emote)
	if pose ~= "Standing" then return false end
	if emoteNames[emote] ~= nil then
		stopCurrentAnimation(EMOTE_FADE_TIME)
		local track = getRandomTrack(emote)
		if track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = emoteNames[emote]
			track:Play(EMOTE_FADE_TIME)
			currentAnimTrack = track
			currentAnimName = emote

			if not emoteNames[emote] then
				local conn
				conn = scope:Connect(track.Stopped, function()
					conn:Disconnect()
					if pose == "Standing" and currentAnimName == emote then
						playAnimation("idle", EMOTE_FADE_TIME, Enum.AnimationPriority.Core)
					end
				end)
			end
			return true, track
		end
	end
	return false
end

if not FFlagUserAnimateRemoveEmoteChatHook then
	local player = Players.LocalPlayer
	if player then
		scope:Connect(player.Chatted, function(msg)
			local emote = ""
			if msg == "/e dance" then emote = dances[math.random(1, #dances)]
			elseif string.sub(msg, 1, 3) == "/e " then emote = string.sub(msg, 4)
			elseif string.sub(msg, 1, 7) == "/emote " then emote = string.sub(msg, 8)
			end
			if pose == "Standing" and emoteNames[emote] ~= nil then
				stopCurrentAnimation(EMOTE_FADE_TIME)
				local track = getRandomTrack(emote)
				if track then
					track.Priority = Enum.AnimationPriority.Action
					track.Looped = emoteNames[emote]
					track:Play(EMOTE_FADE_TIME)
					currentAnimTrack = track
					currentAnimName = emote
					if not emoteNames[emote] then
						local conn
						conn = scope:Connect(track.Stopped, function()
							conn:Disconnect()
							if pose == "Standing" and currentAnimName == emote then
								playAnimation("idle", EMOTE_FADE_TIME, Enum.AnimationPriority.Core)
							end
						end)
					end
				end
			end
		end)
	end
end

-----------------------------------------------------------
-- Humanoid State Callbacks
-----------------------------------------------------------
local function onRunning(speed)
	speed = speed / getRigScale()
	if speed > 0.01 then
		playAnimation("walk", DEFAULT_FADE_TIME, Enum.AnimationPriority.Movement)
		setAnimationSpeed(speed / 14.5)
		pose = "Running"
	else

		if emoteNames[currentAnimName] == nil then
			playAnimation("idle", DEFAULT_FADE_TIME, Enum.AnimationPriority.Idle)
		end
		pose = "Standing"
	end
end

local function onDied()
	pose = "Dead"
	stopCurrentAnimation(0.3)
	stopToolAnimations()
end

local function onJumping()
	playAnimation("jump", DEFAULT_FADE_TIME, Enum.AnimationPriority.Movement)
	pose = "Jumping"
end

local function onClimbing(speed)
	speed = speed / getRigScale()
	playAnimation("climb", DEFAULT_FADE_TIME, Enum.AnimationPriority.Movement)
	setAnimationSpeed(speed / 12.0)
	pose = "Climbing"
end

local function onFreeFall()
	playAnimation("fall", 0.5, Enum.AnimationPriority.Movement)
	pose = "FreeFall"
end

local function onSeated()
	playAnimation("sit", 0.8, Enum.AnimationPriority.Core)
	pose = "Seated"
end

local function onGettingUp()
	pose = "GettingUp"
	stopCurrentAnimation(0.5)
end
local function onFallingDown()
	pose = "FallingDown"
	stopCurrentAnimation(0.5)
end
local function onPlatformStanding()
	pose = "PlatformStanding"
	stopCurrentAnimation(0.5)
end
local function onSwimming(speed)
	pose = (speed > 0) and "Running" or "Standing"
end

scope:Connect(Humanoid.Died, onDied)
scope:Connect(Humanoid.Running, onRunning)
scope:Connect(Humanoid.Jumping, onJumping)
scope:Connect(Humanoid.Climbing, onClimbing)
scope:Connect(Humanoid.GettingUp, onGettingUp)
scope:Connect(Humanoid.FreeFalling, onFreeFall)
scope:Connect(Humanoid.FallingDown, onFallingDown)
scope:Connect(Humanoid.Seated, onSeated)
scope:Connect(Humanoid.PlatformStanding, onPlatformStanding)
scope:Connect(Humanoid.Swimming, onSwimming)

-----------------------------------------------------------
-- Tool Animation Logic
-----------------------------------------------------------
local function getTool()
	for _, kid in ipairs(Figure:GetChildren()) do
		if kid:IsA("Tool") then return kid end
	end
	return nil
end

local function getToolAnim(tool)
	for _, c in ipairs(tool:GetChildren()) do
		if c.Name == "toolanim" and c:IsA("StringValue") then return c end
	end
	return nil
end

local toolAnim = "None"
local toolAnimTime = 0

local function animateTool()
	if toolAnim == "None" then
		playToolAnimation("toolnone", TOOL_FADE_TIME, Enum.AnimationPriority.Idle)
	elseif toolAnim == "Slash" then
		playToolAnimation("toolslash", 0, Enum.AnimationPriority.Action)
	elseif toolAnim == "Lunge" then
		playToolAnimation("toollunge", 0, Enum.AnimationPriority.Action)
	end
end

-----------------------------------------------------------
-- Frame Update Loop (Heartbeat)
-----------------------------------------------------------
playAnimation("idle", 0.5, Enum.AnimationPriority.Idle)
pose = "Standing"

local lastTime = nil

scope:Connect(RunService.Heartbeat, function(step)
	local now = os.clock()
	local deltaTime = math.clamp(step,0,0.1)

	if currentAnimTrack and currentAnimSpeed ~= targetAnimSpeed then
		currentAnimSpeed = currentAnimSpeed + (targetAnimSpeed - currentAnimSpeed) * math.min(1, deltaTime / SPEED_SMOOTHING)
		currentAnimTrack:AdjustSpeed(currentAnimSpeed)
	end

	local tool = getTool()
	if tool and tool:FindFirstChild("Handle") then
		local animString = getToolAnim(tool)
		if animString then
			toolAnim = animString.Value
			animString.Parent = nil
			toolAnimTime = now + 0.3
		end
		if now > toolAnimTime then
			toolAnimTime = 0
			toolAnim = "None"
		end
		animateTool()
	else
		stopToolAnimations()
		toolAnim = "None"
		toolAnimTime = 0
	end
end)
scope:Add(function()
    for _,tracks in pairs(animTracks) do for _,track in ipairs(tracks) do track:Stop(0); track:Destroy() end end
    local bindable=animationRoot:FindFirstChild("PlayEmote")
    if bindable then bindable.OnInvoke=nil end
end)
scope:Connect(character.Destroying,function() scope:Destroy() end)
return scope
end
return Module
