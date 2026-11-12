--!strict
-- Owns cancellable intro-to-loop playback for viewport rigs.
type Session = {Cancelled: boolean, Connection: RBXScriptConnection?}
type TrackState = {Animation: Animation, Session: Session?, Destroyed: boolean}
local states: {[AnimationTrack]: TrackState} = setmetatable({}, {__mode = "k"}) :: any

local function normalizeId(value: any): string?
	local digits: string? = nil
	if type(value) == "number" then
		if value == value and value > 0 and value < math.huge and value % 1 == 0 then digits = string.format("%.0f", value) end
	elseif type(value) == "string" then
		digits = value:match("^rbxassetid://(%d+)$") or value:match("^(%d+)$")
			or value:match("^https?://www%.roblox%.com/asset/%?id=(%d+)$")
	end
	local number = if digits and #digits <= 20 then tonumber(digits) else nil
	return if digits and number and number > 0 and number < math.huge then `rbxassetid://{digits}` else nil
end

local function destroyTrack(track: AnimationTrack?)
	if not track then return end
	local state = states[track]
	if state and state.Destroyed then return end
	if state then
		state.Destroyed = true
		local session = state.Session
		if session then
			session.Cancelled = true
			if session.Connection then session.Connection:Disconnect(); session.Connection = nil end
		end
	end
	pcall(function() track:Stop(0) end)
	pcall(function() track:Destroy() end)
	if state then state.Animation:Destroy() end
end

local function isValidAnimationId(value: any): boolean
	return normalizeId(value) ~= nil
end

local function loadTrack(model: Model, animationId: any, looped: boolean): AnimationTrack?
	local id = normalizeId(animationId)
	if not id then return nil end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then animator = Instance.new("Animator"); animator.Parent = humanoid end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	if not ok or not track then animation:Destroy(); return nil end
	track.Looped = looped
	track.Priority = Enum.AnimationPriority.Action
	states[track] = {Animation = animation, Destroyed = false}
	return track
end

local function animationSpeed(data: any): number
	local speed = data.AnimSpeed
	return if type(speed) == "number" and speed == speed and speed > 0 and speed < math.huge then speed else 1
end

local function playEmoteLoop(model: Model, data: any): (AnimationTrack?, AnimationTrack?)
	if type(data) ~= "table" then return nil, nil end
	local loop = loadTrack(model, data.Loop or data.Loop1, true)
	if not loop then return nil, nil end
	local session: Session = {Cancelled = false}
	states[loop].Session = session
	local speed = animationSpeed(data)
	if isValidAnimationId(data.Intro) then
		local intro = loadTrack(model, data.Intro, false)
		if intro then
			states[intro].Session = session
			session.Connection = intro.Stopped:Connect(function()
				if session.Connection then session.Connection:Disconnect(); session.Connection = nil end
				if session.Cancelled or not model.Parent then return end
				pcall(function() loop:Play(0, 1, speed) end)
			end)
			local ok = pcall(function() intro:Play(0, 1, speed) end)
			if ok then return loop, intro end
			destroyTrack(intro); destroyTrack(loop)
			return nil, nil
		end
	end
	local ok = pcall(function() loop:Play(0, 1, speed) end)
	if not ok then destroyTrack(loop); return nil, nil end
	return loop, nil
end

return {destroyTrack = destroyTrack, isValidAnimationId = isValidAnimationId,
	loadTrack = loadTrack, playEmoteLoop = playEmoteLoop}
