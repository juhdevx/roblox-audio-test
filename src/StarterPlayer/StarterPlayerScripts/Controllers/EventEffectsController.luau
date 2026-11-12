--!strict
-- Owns emote event sessions and its connections for one client lifetime.
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
local Scope = require(game:GetService("ReplicatedStorage").Shared.Utils.Scope)
local ClientState = require(clientRoot.ClientState)
local Settings = require(clientRoot.Controllers.SettingsController)
local Module = {}
local active: any
function Module.Init(_dependencies: any) end
function Module.Start()
    if active then return end
    local scope = Scope.new(); active = scope
--!strict
-- Coordinates show sessions and registered cue handlers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local remote = ReplicatedStorage.Remotes.Effects.EventShow

local okVfx, GetVFXFolder = pcall(function()
	return require(ReplicatedStorage.Shared.Utils.GetVFXFolder)
end)

local AttachmentController = require(clientRoot.Effects.AttachmentController)

local BIND_NAME = "EmoteEventShow"
local STEPS_PER_BEAT = 2
local MAX_CATCHUP_STEPS = 4
local WATCHDOG_MISSING = 8
local WHITE = Color3.new(1, 1, 1)

local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local SPRING_K, SPRING_C = 110, 18
local ATTACK, DECAY = 0.09, 0.5
local PULSE_FOV, PULSE_DOLLY, PULSE_ROLL, PULSE_SHAKE = 6, 0.9, 0.35, 0.1

local sessions = {}
local sessionCount = 0
local paused = {}
local saved = {}
local handlers = {}
local visualState = {letterbox=nil}
local finish

local function getCamera(): Camera?
	return workspace.CurrentCamera
end

local rig = {
	fov = { x = 0, v = 0 }, roll = { x = 0, v = 0 }, bob = { x = 0, v = 0 },
	shake = 0, shakeRate = 7, rumble = 0, t = 0,
	tilt = 0, tiltTarget = 0, push = 0, pushTarget = 0,
	fovBase = 70, fovTarget = 70, originalFov = 70,
	pulse = 0, pulseT = 999, pulseA = 0,
}

local _vfxHiddenWarned = false
local function vfxHidden()
	local settings = Settings.GetSnapshot()
	return settings and settings.HideEmoteVFX or false
end

local function cameraMotionReduced()
	local settings = Settings.GetSnapshot()
	return settings and settings.ReduceMotion or false
end

local function vfxParent()
	if okVfx and type(GetVFXFolder) == "function" then
		local ok, folder = pcall(GetVFXFolder)
		if ok and folder then return folder end
	end
	return workspace.CurrentCamera
end

local function getScale(character)
	if not character then return 1 end
	local ok, scale = pcall(function() return character:GetScale() end)
	return (ok and type(scale) == "number" and scale > 0) and scale or 1
end

local function getRoot(session)
	local character = session.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function addFx(session, fx) table.insert(session.Fx, fx) end

local lightingApi=require(clientRoot.Effects.EventLighting)({Lighting=Lighting,TweenService=TweenService,WHITE=WHITE,scope=scope})
local applyLook=lightingApi.applyLook
local restoreAll=lightingApi.restoreAll
local getEffect=lightingApi.getEffect
local getAtmosphere=lightingApi.getAtmosphere
local getSky=lightingApi.getSky
local applyProps=lightingApi.applyProps
local cameraApi=require(clientRoot.Effects.EventCamera)({ATTACK=ATTACK,DECAY=DECAY,PULSE_DOLLY=PULSE_DOLLY,PULSE_FOV=PULSE_FOV,PULSE_ROLL=PULSE_ROLL,PULSE_SHAKE=PULSE_SHAKE,SPRING_C=SPRING_C,SPRING_K=SPRING_K,cameraMotionReduced=cameraMotionReduced,getCamera=getCamera,rig=rig,scope=scope})
local springStep=cameraApi.springStep
local kickSpring=cameraApi.kickSpring
local rigKick=cameraApi.rigKick
local beatHit=cameraApi.beatHit
local rigStep=cameraApi.rigStep
local rigReset=cameraApi.rigReset
local primitives=require(clientRoot.Effects.EffectPrimitives)({AttachmentController=AttachmentController,Debris=Debris,FIRE_TEXTURE=FIRE_TEXTURE,SPARK_TEXTURE=SPARK_TEXTURE,TweenService=TweenService,WHITE=WHITE,addFx=addFx,beatHit=beatHit,getScale=getScale,handlers=handlers,rigKick=rigKick,scope=scope,vfxParent=vfxParent,visualState=visualState})
local newPart=primitives.newPart
local anchorPart=primitives.anchorPart
local anchorToRig=primitives.anchorToRig
local newAttachment=primitives.newAttachment
local newBeam=primitives.newBeam
local spawnRing=primitives.spawnRing
local spawnDome=primitives.spawnDome
local emitBurst=primitives.emitBurst
local explodeAt=primitives.explodeAt
local setGhost=primitives.setGhost
local fadeParts=primitives.fadeParts
local clearLetterbox=primitives.clearLetterbox
local function spawnMeteor(session, cue)
	local root = getRoot(session)
	if not root then return end

	local scale = getScale(session.Character)
	local color = cue.Color or Color3.fromRGB(255, 130, 40)
	local radius = cue.Radius or 50
	local duration = cue.Duration or 1.8
	local target = root.Position + (cue.Offset or Vector3.new(radius * 0.6, -3 * scale, 0))

	local ball = newPart(Vector3.one * 6 * scale, color, 0)
	ball.Shape = Enum.PartType.Ball
	ball.Position = target + Vector3.new(-radius * 1.2, radius * 3, -radius * 0.8)

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 3 * scale, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -3 * scale, 0)
	a1.Parent = ball

	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.8
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(color, color:Lerp(Color3.new(0, 0, 0), 0.6))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	trail.Parent = ball

	local fire = Instance.new("ParticleEmitter")
	fire.Texture = FIRE_TEXTURE
	fire.Color = ColorSequence.new(color)
	fire.LightEmission = 0.9
	fire.Rate = 80
	fire.Lifetime = NumberRange.new(0.5, 1)
	fire.Speed = NumberRange.new(0, 3)
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6 * scale), NumberSequenceKeypoint.new(1, 0) })
	fire.Parent = ball

	local tween = TweenService:Create(ball, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = target })
	tween:Play()
	scope:Once(tween.Completed, function()
		ball:Destroy()
		if cue.NoImpact ~= true then explodeAt(session, target, color, radius * 1.4 * scale) end
	end)
end

local EMBER_STYLES={
	Embers = {
		Color = ColorSequence.new(Color3.fromRGB(255, 160, 70), Color3.fromRGB(255, 60, 20)),
		Speed = NumberRange.new(6, 16), Lifetime = NumberRange.new(1.5, 3.5), Accel = Vector3.new(0, 6, 0),
		Rate = 60, Size = 0.5, Spread = 180, Light = 1, Up = 0,
	},
	Stars = {
		Color = ColorSequence.new(Color3.fromRGB(220, 220, 255)),
		Speed = NumberRange.new(2, 8), Lifetime = NumberRange.new(3, 6), Accel = Vector3.new(0, 0, 0),
		Rate = 30, Size = 0.45, Spread = 180, Light = 1, Up = 0,
	},
	Bubbles = {
		Color = ColorSequence.new(Color3.fromRGB(190, 235, 255)),
		Speed = NumberRange.new(2, 6), Lifetime = NumberRange.new(2.5, 5), Accel = Vector3.new(0, 5, 0),
		Rate = 25, Size = 0.7, Spread = 180, Light = 0.4, Up = 0,
	},
	Confetti = {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 200)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 80)),
		}),
		Speed = NumberRange.new(2, 8), Lifetime = NumberRange.new(3, 5), Accel = Vector3.new(0, -14, 0),
		Rate = 100, Size = 0.5, Spread = 70, Light = 0.6, Up = 40,
	},
}
local cueContext={AttachmentController=AttachmentController,ClientState=ClientState,Debris=Debris,EMBER_STYLES=EMBER_STYLES,LocalPlayer=LocalPlayer,SMOKE_TEXTURE=SMOKE_TEXTURE,SPARK_TEXTURE=SPARK_TEXTURE,TweenService=TweenService,WHITE=WHITE,addFx=addFx,anchorPart=anchorPart,applyLook=applyLook,beatHit=beatHit,cameraMotionReduced=cameraMotionReduced,emitBurst=emitBurst,explodeAt=explodeAt,fadeParts=fadeParts,getEffect=getEffect,getRoot=getRoot,getScale=getScale,handlers=handlers,newAttachment=newAttachment,newBeam=newBeam,newPart=newPart,rig=rig,rigKick=rigKick,scope=scope,setGhost=setGhost,spawnDome=spawnDome,spawnMeteor=spawnMeteor,spawnRing=spawnRing,vfxHidden=vfxHidden,vfxParent=vfxParent,visualState=visualState}
for _,module in clientRoot.Effects.CueHandlers:GetChildren() do
    if module:IsA("ModuleScript") then handlers[module.Name]=require(module)(cueContext) end
end
handlers.Lighting=handlers.Look
handlers.SunBeam=handlers.Spotlights
for _, name in ipairs({ "SpawnBoss", "Vignette", "FilmGrain", "FadeOut", "Dust", "MotionBlur", "ColorCycle", "Strobe" }) do
	local warned=false
    handlers[name] = function() if not warned then warned=true; warn("Cue is not implemented: "..name) end end
end

-- ════════════════════════════════════════════════════════════
-- TIMELINE
-- ════════════════════════════════════════════════════════════

local timeline=require(clientRoot.Effects.EventTimeline)({CollectionService=CollectionService,WHITE=WHITE,applyLook=applyLook,beatHit=beatHit,getRoot=getRoot,getScale=getScale,handlers=handlers,kickSpring=kickSpring,rig=rig,rigKick=rigKick,scope=scope,spawnDome=spawnDome,vfxHidden=vfxHidden})
local findShowSound=timeline.findShowSound
local getShowTime=timeline.getShowTime
local sceneAt=timeline.sceneAt
local evalCurve=timeline.evalCurve
local runCue=timeline.runCue
local runCues=timeline.runCues
local catchUp=timeline.catchUp
local enterScene=timeline.enterScene
local fireStep=timeline.fireStep
local debugGui, debugLabel = nil, nil
local taps = {}

local function setDebug(enabled)
	if enabled and not debugGui then
		debugGui = Instance.new("ScreenGui")
		debugGui.Name = "EventShowDebug"
		debugGui.ResetOnSpawn = false
		debugGui.DisplayOrder = 999

		debugLabel = Instance.new("TextLabel")
		debugLabel.BackgroundColor3 = Color3.new(0, 0, 0)
		debugLabel.BackgroundTransparency = 0.4
		debugLabel.TextColor3 = WHITE
		debugLabel.Font = Enum.Font.Code
		debugLabel.TextSize = 14
		debugLabel.TextXAlignment = Enum.TextXAlignment.Left
		debugLabel.TextYAlignment = Enum.TextYAlignment.Top
		debugLabel.Position = UDim2.fromOffset(10, 10)
		debugLabel.Size = UDim2.fromOffset(470, 84)
		debugLabel.Parent = debugGui

		debugGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	elseif not enabled and debugGui then
		debugGui:Destroy()
		debugGui, debugLabel = nil, nil
	end
end

scope:Connect(UserInputService.InputBegan, function(input, processed)
	if processed or not debugGui then return end

	local session = nil
	for _, candidate in pairs(sessions) do
		session = candidate
		break
	end
	if not session then return end

	local sceneName = session.Scene and session.Scene.Name or "-"

	if input.KeyCode == Enum.KeyCode.M then
		print(string.format("[EventShow] Marcador: Time = %.2f   (cena: %s)", session.RawShow, sceneName))
	elseif input.KeyCode == Enum.KeyCode.T then
		local now = session.RawShow
		if #taps > 0 and now - taps[#taps] > 2.5 then table.clear(taps) end
		table.insert(taps, now)

		if #taps >= 4 then
			local first = math.max(1, #taps - 8)
			local period = (taps[#taps] - taps[first]) / (#taps - first)
			local sceneStart = session.Scene and session.Scene.Time or 0
			print(string.format("[EventShow] Bpm = %.1f , Offset = %.3f   (cena: %s, %d toques)", 60 / period, (taps[#taps] - sceneStart) % period, sceneName, #taps))
		end
	end
end)

local function pauseOthers(session)
	local hostCharacter = session.Character
	if not hostCharacter then return end
	for _, sound in ipairs(CollectionService:GetTagged("EmoteSound")) do
		if sound:IsA("Sound") and sound.IsPlaying and not sound:IsDescendantOf(hostCharacter) then
			sound:Pause()
			paused[sound] = true
		end
	end
end

local function resumePaused()
	for sound in pairs(paused) do
		if sound.Parent then pcall(function() sound:Resume() end) end
	end
	table.clear(paused)
end

local function stepSession(session, dt)
	local now = os.clock()

	local character = session.Character
	if not (character and character.Parent) and now - session.LastResolve > 0.25 then
		session.LastResolve = now
		local host = session.HostUserId and Players:GetPlayerByUserId(session.HostUserId)
		session.Character = host and host.Character or nil
		character = session.Character
	end
	if character and character.Parent then session.LastSeen = now end

	if now - session.LastSeen > WATCHDOG_MISSING
		or (session.Exclusive and now - session.Born > 4 and workspace:GetAttribute("EmoteShowActive") ~= true) then
		warn(string.format("[EmoteEventClient] Watchdog finish: LastSeen=%.1fs Born=%.1fs Exclusive=%s ShowActive=%s",
			now - session.LastSeen, now - session.Born, tostring(session.Exclusive), tostring(workspace:GetAttribute("EmoteShowActive"))))
		finish(session.Id)
		return
	end

	if not (session.Sound and session.Sound.Parent) and now - session.LastSearch > 0.1 then
		session.LastSearch = now
		session.Sound = findShowSound(session)
	end

	local raw, fromAudio = getShowTime(session)
	session.RawShow = raw
	local showTime = (raw + session.Lookahead) % session.ShowLength
	local isHost = character ~= nil and character == LocalPlayer.Character

	if session.Exclusive and not isHost then
		if not session.AudioDone and character and now - session.Born > 0.5 then
			session.AudioDone = true
			pauseOthers(session)
		end
		local sound = session.Sound
		if sound and sound.Parent then
			local volume = sound:GetAttribute("Volume")
			if sound.Volume == 0 and type(volume) == "number" and volume > 0 then sound.Volume = volume end
		end
	end

	local previous = session.PrevShow
	if previous == nil then
		session.PrevShow = showTime
		enterScene(session, sceneAt(session, showTime), 0.6)
		catchUp(session, showTime)
	else
		local delta = showTime - previous
		if delta < -session.ShowLength * 0.5 then
			session.CueCursor = 1
			session.SceneIndex = 1
			runCues(session, previous, session.ShowLength)
			runCues(session, -1, showTime)
			session.PrevShow = showTime
		elseif delta < 0 then
			-- oscilação
		elseif delta > 3 then
			session.CueCursor = 1
			session.SceneIndex = 1
			session.PrevShow = showTime
			enterScene(session, sceneAt(session, showTime), 0.6)
			catchUp(session, showTime)
		else
			runCues(session, previous, showTime)
			session.PrevShow = showTime
		end
	end

	local scene = sceneAt(session, showTime)
	if scene ~= session.Scene then enterScene(session, scene, 1.5) end

	if scene and scene.Bpm and scene.Pattern and #scene.Pattern > 0 then
		local relative = showTime - scene.Time - (scene.Offset or 0)
		local index = relative < 0 and -1 or math.floor(relative * scene.Bpm / 60 * STEPS_PER_BEAT)
		local last = session.StepIndex

		if last == nil then
			session.StepIndex = index
		elseif index > last then
			if index - last <= MAX_CATCHUP_STEPS then
				for step = last + 1, index do fireStep(session, scene, step) end
			end
			session.StepIndex = index
		elseif index < last - 2 then
			session.StepIndex = index
		end
	end

	rig.rumble += ((scene and (scene.Rumble or 0) * (scene.Energy or 1) or 0) - rig.rumble) * math.min(1, dt * 2)
	session.energy *= math.exp(-dt * 5)

	if session.Gravity and #session.Gravity > 0 then
		if saved.Gravity == nil then saved.Gravity = workspace.Gravity end
		local value = evalCurve(session.Gravity, showTime)
		if value then workspace.Gravity = value end
	end

	if isHost and session.Zoom then
		if saved.MinZoom == nil then saved.MinZoom = LocalPlayer.CameraMinZoomDistance end
		local scale = getScale(character)
		local wanted = scale > 1.15 and math.min(10 * scale, LocalPlayer.CameraMaxZoomDistance) or saved.MinZoom
		if LocalPlayer.CameraMinZoomDistance ~= wanted then LocalPlayer.CameraMinZoomDistance = wanted end
	end

	local fx = session.Fx
	for i = #fx, 1, -1 do
		local item = fx[i]
		local ok, keep = pcall(item.update, dt)
		if not ok or not keep then
			pcall(item.destroy)
			table.remove(fx, i)
		end
	end

	if debugLabel then
		local sound = session.Sound
		debugLabel.Text = string.format(
			"show %.2f / %d s   cena: %s\nrelógio: %s   áudio: %s\nbatida: %s %s BPM   [M] marcar  [T] bater no ritmo",
			raw, session.ShowLength, scene and scene.Name or "-",
			fromAudio and "ÁUDIO" or "servidor (sem som)",
			sound and sound.Parent and string.format("%.2f/%.2f", sound.TimePosition, sound.TimeLength) or "-",
			scene and scene.Pattern or "-", scene and scene.Bpm or "-"
		)
	end
end

local function onRender(dt)
	for _, session in pairs(sessions) do
		local ok, err = pcall(stepSession, session, dt)
		if not ok then warn("EmoteEventClient: " .. tostring(err)) end
	end
	rigStep(dt)
end

finish = function(id)
	local session = sessions[id]
	if not session then return end

	session.Ended = true
	sessions[id] = nil
	sessionCount -= 1

	for _, item in ipairs(session.Fx) do pcall(item.destroy) end
	table.clear(session.Fx)
	table.clear(session.Hooks)

	if session.Character then
		AttachmentController.CleanupSession(session.Character, session.Id)
	end

	if sessionCount <= 0 then
		sessionCount = 0
		RunService:UnbindFromRenderStep(BIND_NAME)
		restoreAll(session.FadeOut)
		rigReset()
		resumePaused()
		clearLetterbox(0.6)
		setDebug(false)
		table.clear(taps)
		if saved.Gravity then workspace.Gravity = saved.Gravity end
		if saved.MinZoom then LocalPlayer.CameraMinZoomDistance = saved.MinZoom end
		table.clear(saved)
	end
end

local function begin(data)
	if type(data) ~= "table" or sessions[data.Id] then return end

	local camera = getCamera()
	if sessionCount == 0 then
		rig.originalFov = camera and camera.FieldOfView or 70
		rig.fovBase, rig.fovTarget = rig.originalFov, rig.originalFov
	end

	local session = {
		Id = data.Id,
		Character = data.Character,
		HostUserId = data.HostUserId,
		StartTime = data.StartTime or workspace:GetServerTimeNow(),
		ShowLength = data.ShowLength or 560,
		Fit = data.Fit ~= false,
		Lookahead = data.Lookahead or 0.04,
		Scenes = data.Scenes or {},
		Cues = data.Cues or {},
		Gravity = data.Gravity,
		FadeOut = data.FadeOut or 2,
		Exclusive = data.Exclusive == true,
		Zoom = data.Zoom ~= false,
		Fx = {},
		Hooks = {},
		energy = 0,
		beatTick = 0,
		rollSign = 1,
		Born = os.clock(),
		LastSeen = os.clock(),
		LastSearch = 0,
		LastResolve = 0,
		RawShow = 0,
		CueCursor = 1,
		SceneIndex = 1,
	}

	-- ────────────────────────────────────────────────────────
	-- BEAT-SNAP AUTOMÁTICO
	-- Alinha cada cue ao beat mais próximo da cena ativa.
	-- Tolerância: 0.15s (mais que isso não vale a pena alinhar).
	-- ────────────────────────────────────────────────────────
	local function findActiveScene(t: number)
		local active = nil
		for _, scene in ipairs(session.Scenes) do
			if scene.Time <= t then active = scene else break end
		end
		return active
	end

	local function snapToBeat(cueTime: number): number
		local scene = findActiveScene(cueTime)
		if not scene or not scene.Bpm or not scene.Pattern or scene.Bpm <= 0 then
			return cueTime
		end
		local beatDur = 60 / scene.Bpm
		local relative = cueTime - scene.Time
		local nearestBeat = math.floor(relative / beatDur + 0.5) * beatDur
		local snapped = scene.Time + nearestBeat
		if math.abs(snapped - cueTime) < 0.15 then
			return snapped
		end
		return cueTime
	end

	local snappedCues = {}
	for _, cue in ipairs(session.Cues) do
		local copy = table.clone(cue)
		copy.Time = snapToBeat(cue.Time)
		table.insert(snappedCues, copy)
	end
	table.sort(snappedCues, function(a, b) return a.Time < b.Time end)
	session.Cues = snappedCues

	sessions[session.Id] = session
	sessionCount += 1

	if sessionCount == 1 then
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 10, onRender)
	end
	if data.Debug then setDebug(true) end
end

scope:Connect(remote.OnClientEvent, function(action, data)
	if action == "Begin" then
		begin(data)
	elseif action == "End" then
		finish(data)
	end
end)

remote:FireServer("Ready")
scope:Add(function()

for id,session in pairs(sessions) do session.FadeOut=0; finish(id) end
RunService:UnbindFromRenderStep(BIND_NAME)
restoreAll(0); rigReset(); resumePaused()
if visualState.letterbox then visualState.letterbox:Destroy(); visualState.letterbox=nil end
if debugGui then debugGui:Destroy() end

end)
end
function Module.Destroy() if active then active:Destroy(); active=nil end end
return Module
