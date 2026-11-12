--!strict
-- Implements EventTimeline through explicit effect dependencies.
return function(context: any)
local CollectionService=context.CollectionService
local WHITE=context.WHITE
local applyLook=context.applyLook
local beatHit=context.beatHit
local getRoot=context.getRoot
local getScale=context.getScale
local handlers=context.handlers
local kickSpring=context.kickSpring
local rig=context.rig
local rigKick=context.rigKick
local scope=context.scope
local spawnDome=context.spawnDome
local vfxHidden=context.vfxHidden
local function findShowSound(session)
	local root = getRoot(session)
	if not root then return nil end
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Sound") and CollectionService:HasTag(child, "EmoteSound") then return child end
	end
	return nil
end

local function getShowTime(session)
	local sound = session.Sound
	if sound and sound.Parent and sound.IsPlaying and sound.TimeLength > 0 then
		local position = sound.TimePosition
		if session.Fit then return position / sound.TimeLength * session.ShowLength, true end
		return position % session.ShowLength, true
	end
	return (workspace:GetServerTimeNow() - session.StartTime) % session.ShowLength, false
end

local function sceneAt(session, showTime)
	local scenes = session.Scenes
	local idx = session.SceneIndex or 1

	while idx < #scenes and scenes[idx + 1].Time <= showTime do
		idx += 1
	end
	while idx > 1 and scenes[idx].Time > showTime do
		idx -= 1
	end

	session.SceneIndex = idx
	return scenes[idx]
end

local function evalCurve(curve, t)
	local count = #curve
	if count == 0 then return nil end
	if t <= curve[1].Time then return curve[1].Value end
	for i = 2, count do
		local a, b = curve[i - 1], curve[i]
		if t <= b.Time then
			return a.Value + (b.Value - a.Value) * ((t - a.Time) / math.max(b.Time - a.Time, 0.001))
		end
	end
	return curve[count].Value
end

local function runCue(session, cue)
	local handler = handlers[cue.Action]
	if not handler then return end
	local ok, err = pcall(handler, session, cue)
	if not ok then warn("EmoteEventClient: erro em '" .. tostring(cue.Action) .. "' - " .. tostring(err)) end
end

local function runCues(session, from, to)
	local cues = session.Cues
	local cursor = session.CueCursor or 1

	while cursor <= #cues and cues[cursor].Time <= from do
		cursor += 1
	end

	while cursor <= #cues and cues[cursor].Time <= to do
		runCue(session, cues[cursor])
		cursor += 1
	end

	session.CueCursor = cursor
end

local PERSISTENT = {
	Lasers = true, Equalizer = true, Embers = true, Spotlights = true, SunBeam = true,
	Bounce = true, Smoke = true, PlayerRGB = true, Electricity = true, EnergyOrbit = true,
}
local LAST_OF = { Aura = true, Letterbox = true, CameraFOV = true, CameraTilt = true }

local function catchUp(session, showTime)
	local latest = {}
	for _, cue in ipairs(session.Cues) do
		if cue.Time <= showTime then
			if LAST_OF[cue.Action] then
				latest[cue.Action] = cue
			elseif cue.Duration and (PERSISTENT[cue.Action] or (cue.Action == "SpawnPart" and (cue.Kind == "Stars" or cue.Kind == "Planets")))
				and showTime < cue.Time + cue.Duration then
				local copy = table.clone(cue)
				copy.Duration = cue.Time + cue.Duration - showTime
				runCue(session, copy)
			end
		end
	end
	for _, cue in pairs(latest) do runCue(session, cue) end
end

local function enterScene(session, scene, fade)
	session.Scene = scene
	session.StepIndex = nil
	if scene then applyLook(scene.Look, scene.Fade or fade or 1.5) end
end

local function fireStep(session, scene, index)
	if index < 0 then return end
	local pattern = scene.Pattern
	local length = #pattern
	local position = index % length
	local char = pattern:sub(position + 1, position + 1)
	if scene.AccentBars and position == 0 and math.floor(index / length) % scene.AccentBars == 0 then char = "X" end
	if char == "." then return end

	local e = scene.Energy or 1
	local bob = scene.CamBob or 1
	local sign = session.rollSign
	session.beatTick += 1

	if char == "K" then
		beatHit(0.6 * e)
		rigKick(3 * e, 1 * e * sign, 0.04 * e, 9)
		kickSpring(rig.bob, 0.4 * e * bob)
		session.energy = 1
		session.rollSign = -sign
	elseif char == "S" then
		beatHit(0.3 * e)
		rigKick(-1.8 * e, -0.7 * e * sign, 0.03 * e, 10)
		kickSpring(rig.bob, 0.15 * e * bob)
		session.energy = math.max(session.energy, 0.6)
	elseif char == "h" then
		beatHit(0.12 * e)
		rigKick(0.8 * e, 0, 0.012 * e, 12)
	elseif char == "X" then
		beatHit(1.2 * e)
		rigKick(8 * e, 2 * e * sign, 0.2 * e, 6)
		kickSpring(rig.bob, 0.9 * e * bob)
		session.energy = 1
		session.rollSign = -sign

		local root = getRoot(session)
		if root and not vfxHidden() then
			local scale = getScale(session.Character)
			spawnDome(root.Position - Vector3.new(0, 3 * scale, 0), scene.Accent or WHITE, 18 * scale, 0.6)
			handlers.Flash(session, { Color = scene.Accent or WHITE, Intensity = 0.3, Duration = 0.32 })
		end
	end

	for _, hook in ipairs(session.Hooks) do pcall(hook, char) end
end


return {findShowSound=findShowSound,getShowTime=getShowTime,sceneAt=sceneAt,evalCurve=evalCurve,runCue=runCue,runCues=runCues,catchUp=catchUp,enterScene=enterScene,fireStep=fireStep}
end
