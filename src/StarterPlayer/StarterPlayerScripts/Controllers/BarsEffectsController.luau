--!strict
-- Owns BarsEffectsController and its connections for one client lifetime.
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
-- Owns BarsEffectsController visual sessions.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local TAG = "EmoteBarsMeter"
local BIND_NAME = "EmoteBarsMeterUpdate"
local WHITE = Color3.new(1, 1, 1)
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local FADE_IN, FADE_OUT = 0.5, 0.35
local MAX_FRAME_JUMP = 30
local FADE_PROPS = { "TextTransparency", "TextStrokeTransparency", "ImageTransparency", "BackgroundTransparency" }

local meters = {}
local bound = false


local camSpring = { x = 0, v = 0 }
local cachedCamera: Camera? = nil
local cachedBaseFov = 70

local function getCamera(): Camera?
	local cam = workspace.CurrentCamera
	if cam ~= cachedCamera then
		cachedCamera = cam
		if cam then cachedBaseFov = cam.FieldOfView end
	end
	return cam
end


local currentCharacter: Model? = LocalPlayer.Character

local function refreshLocalCharacter()
	local char = LocalPlayer.Character
	if char ~= currentCharacter then
		currentCharacter = char

		for _, meter in pairs(meters) do
			meter.isLocalPlayer = (meter.model.Parent == currentCharacter)
		end
	end
end

scope:Connect(LocalPlayer.CharacterAdded, function(char)
	currentCharacter = char
	task.wait()
	for _, meter in pairs(meters) do
		meter.isLocalPlayer = (meter.model.Parent == currentCharacter)
	end
end)

local function digitsOf(id)
	return tostring(id or ""):match("%d+")
end

local function findTrack(character, digits)
	if not character or not digits then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return nil end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local animation = track.Animation
		if animation and digitsOf(animation.AnimationId) == digits then return track end
	end
	return nil
end

local function stepSpring(spring, target, dt, stiffness, damping)
	local stepSize = 1 / 120
	while dt > 0 do
		local h = math.min(dt, stepSize)
		spring.v += ((target - spring.x) * stiffness - spring.v * damping) * h
		spring.x += spring.v * h
		dt -= h
	end
end

local function buildBar(model, spec, defaultBar, defaultFill, sparkColor)
	local barName = spec.Bar or defaultBar
	local fillName = spec.Fill or defaultFill

	local bar = model:WaitForChild(barName, 5)
	if not bar then return nil end

	local part = bar:FindFirstChild(fillName)
	if not part then
		if bar:IsA("BasePart") then part = bar else part = bar:WaitForChild(fillName, 5) end
	end

	if not part or not part:IsA("BasePart") then return nil end

	local joint = part:WaitForChild("BarJoint", 5)
	if not joint then return nil end

	local size = part.Size
	local axis = spec.Axis
	if axis ~= "X" and axis ~= "Y" and axis ~= "Z" then
		axis = (size.X >= size.Y and size.X >= size.Z) and "X" or ((size.Y >= size.Z) and "Y" or "Z")
	end

	local unit = math.max(math.min(size.X, size.Y, size.Z), 0.2)

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK_TEXTURE
	emitter.Color = ColorSequence.new(sparkColor or part.Color)
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(unit * 3, unit * 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 2
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, unit * 1.2), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = attachment

	return {
		part = part, joint = joint, baseSize = size, baseC0 = joint.C0, baseColor = part.Color,
		axis = axis, axisVector = Vector3.FromAxis(Enum.Axis[axis]), baseLength = size[axis],
		sign = (spec.From == "Max") and -1 or 1, attachment = attachment, emitter = emitter,
		spring = { x = 0, v = 0 }, pop = { x = 0, v = 0 }, flash = 0,
	}
end

local function applyFill(bar, level, pop, flash, minFill)
	local length = bar.baseLength * math.clamp(level, minFill, 1.3)
	local thickness = 1 + pop
	local size = bar.baseSize

	local x, y, z = size.X * thickness, size.Y * thickness, size.Z * thickness
	if bar.axis == "X" then x = length elseif bar.axis == "Y" then y = length else z = length end

	bar.part.Size = Vector3.new(math.max(x, 0.05), math.max(y, 0.05), math.max(z, 0.05))

	local shift = (length - bar.baseLength) * 0.5 * bar.sign
	bar.joint.C0 = bar.baseC0 * CFrame.new(bar.axisVector * shift)

	bar.part.Color = bar.baseColor:Lerp(WHITE, math.clamp(flash, 0, 1) * 0.6)
	bar.attachment.Position = bar.axisVector * (bar.sign * length * 0.5)
end

local function countHits(cfg, from, to)
	local cycleFrames = cfg.TotalFrames / cfg.Cycles
	local count = 0

	local function between(a, b)
		for cycle = 0, cfg.Cycles - 1 do
			for _, hit in ipairs(cfg.Hits) do
				local absolute = hit + cycle * cycleFrames
				if absolute > a and absolute <= b then count += 1 end
			end
		end
	end

	if to >= from then
		between(from, to)
	else
		between(from, cfg.TotalFrames)
		between(-1, to)
	end
	return count
end

local function levelAt(cfg, frame)
	local cycleFrames = cfg.TotalFrames / cfg.Cycles
	local inCycle = frame % cycleFrames
	local total = #cfg.Hits
	if total == 0 then return 0 end

	local passed = 0
	for _, hit in ipairs(cfg.Hits) do
		if inCycle >= hit then passed += 1 end
	end

	local level = passed / total
	local reset = cfg.Reset
	if reset and inCycle >= reset.Frame then
		local k = math.clamp((inCycle - reset.Frame) / math.max(reset.Frames, 1), 0, 1)
		level *= 1 - (k * k * (3 - 2 * k))
	end
	return level
end

local function currentFrame(meter)
	local cfg = meter.cfg
	local track = meter.track
	local speed = cfg.Speed or 1
	local fps = cfg.Fps or 30
	local offset = cfg.TimeOffset or 0

	if track and track.IsPlaying and track.Length > 0 then
		local progress = track.TimePosition / track.Length
		local frame = (progress * cfg.TotalFrames) + offset
		return frame % cfg.TotalFrames
	end

	local elapsed = workspace:GetServerTimeNow() - meter.startTime
	local frame = (elapsed * fps * speed) + offset
	return frame % cfg.TotalFrames
end

local function applyFade(meter)
	local hidden = 1 - meter.appear
	for _, part in ipairs(meter.parts) do
		part.LocalTransparencyModifier = hidden
	end
	for _, entry in ipairs(meter.guis) do
		for prop, original in pairs(entry.props) do
			entry.object[prop] = original + (1 - original) * hidden
		end
	end
end

local function onHit(meter)
	local bounce = meter.bounce
	meter.anger.spring.v += bounce.Kick
	meter.calm.spring.v -= bounce.Kick
	meter.anger.pop.v += bounce.Pop
	meter.calm.pop.v += bounce.Pop * 0.6
	meter.anger.flash, meter.calm.flash = 1, 0.7


	pcall(function() meter.anger.emitter:Emit(14) end)
	pcall(function() meter.calm.emitter:Emit(8) end)

	if meter.isLocalPlayer then
		local camKick = bounce.CamKick or 4.5
		local soundMult = 1.0

		local character = LocalPlayer.Character
		if character then
			local sound = character:FindFirstChildOfClass("Sound", true)
			if sound and sound.IsPlaying and sound.PlaybackLoudness > 0 then
				soundMult = math.clamp(sound.PlaybackLoudness / 140, 0.8, 1.6)
			end
		end

		camSpring.v += camKick * soundMult
	end
end

local function updateMeter(meter, dt)
	local model = meter.model
	local cfg = meter.cfg
	local bounce = meter.bounce
	local now = os.clock()
	dt = math.min(dt, 1 / 20)

	if not (meter.track and meter.track.IsPlaying) and now - meter.lastSearch > 0.25 then
		meter.lastSearch = now
		meter.track = findTrack(model.Parent, meter.animationDigits)
	end

	local frame = currentFrame(meter)
	local previous = meter.prevFrame
	local hits = 0

	if previous == nil then
		meter.prevFrame = frame
	else
		local delta = frame - previous
		if delta >= 0 then
			if delta <= MAX_FRAME_JUMP then
				hits = countHits(cfg, previous, frame)
			end
			meter.prevFrame = frame
		elseif previous - frame > cfg.TotalFrames * 0.5 then
			hits = countHits(cfg, previous, frame)
			meter.prevFrame = frame
		end
	end

	if hits > 0 then
		onHit(meter)
	end

	local level = levelAt(cfg, frame)

	stepSpring(meter.anger.spring, level, dt, bounce.Stiffness, bounce.Damping)
	stepSpring(meter.calm.spring, 1 - level, dt, bounce.Stiffness * 0.9, bounce.Damping)
	stepSpring(meter.anger.pop, 0, dt, 260, 12)
	stepSpring(meter.calm.pop, 0, dt, 260, 12)

	meter.anger.flash *= math.exp(-dt * 8)
	meter.calm.flash *= math.exp(-dt * 8)

	applyFill(meter.anger, meter.anger.spring.x, meter.anger.pop.x, meter.anger.flash, cfg.MinFill)
	applyFill(meter.calm, meter.calm.spring.x, meter.calm.pop.x, meter.calm.flash, cfg.MinFill)

	local closing = model:GetAttribute("Closing") == true
	local target = closing and 0 or 1
	local speed = closing and (1 / FADE_OUT) or (1 / FADE_IN)
	local appear = meter.appear
	if appear ~= target then
		appear = appear + math.clamp(target - appear, -speed * dt, speed * dt)
		meter.appear = appear
		applyFade(meter)
	end
end

local function onRender(dt)

	if next(meters) == nil then
		if bound then
			bound = false
			RunService:UnbindFromRenderStep(BIND_NAME)
		end
		return
	end

	refreshLocalCharacter()

	local hasLocalActiveMeter = false

	for _, meter in pairs(meters) do
		if meter.ready and meter.model.Parent then
			local ok, err = pcall(updateMeter, meter, dt)
			if not ok then warn("BarsMeterClient: " .. tostring(err)) end
			if meter.isLocalPlayer then hasLocalActiveMeter = true end
		end
	end


	local Camera = getCamera()
	if Camera then
		if hasLocalActiveMeter or math.abs(camSpring.x) > 0.01 or math.abs(camSpring.v) > 0.01 then
			stepSpring(camSpring, 0, dt, 240, 14)
			Camera.FieldOfView = cachedBaseFov - camSpring.x
		else
			camSpring.x, camSpring.v = 0, 0
			Camera.FieldOfView = cachedBaseFov
		end
	end
end

local function bind()
	if bound then return end
	bound = true
	local cam = getCamera()
	if cam then cachedBaseFov = cam.FieldOfView end
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, onRender)
end

local function unbindIfEmpty()
	if next(meters) == nil and bound then
		bound = false
		RunService:UnbindFromRenderStep(BIND_NAME)
		local cam = getCamera()
		if cam then cam.FieldOfView = cachedBaseFov end
	end
end

local function setupMeter(model)
	if meters[model] then return end

	local raw = model:GetAttribute("Config")
	local ok, cfg = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(cfg) ~= "table" then return end

	local bounce = cfg.Bounce or {}
	local meter = {
		model = model,
		cfg = cfg,
		bounce = {
			Stiffness = bounce.Stiffness or 230,
			Damping = bounce.Damping or 10,
			Kick = bounce.Kick or 2.2,
			Pop = bounce.Pop or 5,
			CamKick = bounce.CamKick or 4.5,
		},
		startTime = model:GetAttribute("StartTime") or workspace:GetServerTimeNow(),
		animationDigits = digitsOf(cfg.AnimationId),
		isLocalPlayer = (model.Parent == LocalPlayer.Character),
		appear = 0,
		lastSearch = 0,
		parts = {},
		guis = {},
		ready = false,
	}
	meters[model] = meter

	scope:Spawn(function()
		local anger = buildBar(model, cfg.Anger or {}, "Anger", "FillA", Color3.fromRGB(255, 130, 60))
		local calm = buildBar(model, cfg.Calm or {}, "Calm", "FillC", Color3.fromRGB(110, 190, 255))

		if not anger or not calm or not model.Parent then
			meters[model] = nil
			unbindIfEmpty()
			return
		end

		meter.anger, meter.calm = anger, calm

		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(meter.parts, descendant)
			elseif descendant:IsA("GuiObject") then
				local props = {}
				for _, prop in ipairs(FADE_PROPS) do
					local readable, value = pcall(function() return descendant[prop] end)
					if readable and type(value) == "number" then props[prop] = value end
				end
				table.insert(meter.guis, { object = descendant, props = props })
			end
		end

		applyFade(meter)
		meter.ready = true
		bind()
	end)
end

for _, model in ipairs(CollectionService:GetTagged(TAG)) do setupMeter(model) end
scope:Connect(CollectionService:GetInstanceAddedSignal(TAG), setupMeter)
scope:Connect(CollectionService:GetInstanceRemovedSignal(TAG), function(model)
	meters[model] = nil
	unbindIfEmpty()
end)
scope:Add(function()
RunService:UnbindFromRenderStep(BIND_NAME)
if cachedCamera then cachedCamera.FieldOfView=cachedBaseFov end
table.clear(meters)
end)
end
function Module.Destroy() if active then active:Destroy(); active=nil end end
return Module
