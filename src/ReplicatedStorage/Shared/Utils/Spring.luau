--!strict
-- Provides the existing Spring behavior.
local Types = {
	number = true,
	Vector2 = true,
	Vector3 = true,
	Color3 = true
}

local Spring = {}
Spring.__index = Spring

local function lerp(a, b, t)
	if typeof(a) == "number" then
		return a + (b - a) * t
	else
		return a:Lerp(b, t)
	end
end

local function add(a, b)
	if typeof(a) == "number" then
		return a + b
	else
		return a + b
	end
end

local function mul(a, b)
	if typeof(a) == "number" then
		return a * b
	else
		return a * b
	end
end

local function zero(a)
	if typeof(a) == "number" then return 0 end
	if typeof(a) == "Vector2" then return Vector2.new() end
	if typeof(a) == "Vector3" then return Vector3.new() end
	if typeof(a) == "Color3" then return Color3.new() end
	return 0
end

function Spring.new(initial)
	local v = initial or 0
	local v0 = zero(v)
	return setmetatable({
		_damper = 1,
		_speed = 1,
		_time0 = tick(),
		_position0 = v,
		_velocity0 = v0,
		_target = v
	}, Spring)
end

function Spring:Impulse(velocity)
	self._velocity0 = add(self._velocity0, velocity)
end

function Spring:TimeSkip(delta)
	local now = tick()
	local pos, vel = self:_positionVelocity(now + delta)
	self._position0 = pos
	self._velocity0 = vel
	self._time0 = now
end

function Spring:__index(key)
	if Spring[key] then return Spring[key] end
	if key == "Value" or key == "Position" or key == "p" then
		local pos, _ = self:_positionVelocity(tick())
		return pos
	end
	if key == "Velocity" or key == "v" then
		local _, vel = self:_positionVelocity(tick())
		return vel
	end
	if key == "Target" or key == "t" then return self._target end
	if key == "Damper" or key == "d" then return self._damper end
	if key == "Speed" or key == "s" then return self._speed end
	error(string.format("%q is not a valid member of Spring", tostring(key)), 2)
end

function Spring:__newindex(key, value)
	local now = tick()
	if key == "Value" or key == "Position" or key == "p" then
		local _, vel = self:_positionVelocity(now)
		self._position0 = value
		self._velocity0 = vel
	elseif key == "Velocity" or key == "v" then
		local pos, _ = self:_positionVelocity(now)
		self._position0 = pos
		self._velocity0 = value
	elseif key == "Target" or key == "t" then
		local pos, vel = self:_positionVelocity(now)
		self._position0 = pos
		self._velocity0 = vel
		self._target = value
	elseif key == "Damper" or key == "d" then
		local pos, vel = self:_positionVelocity(now)
		self._position0 = pos
		self._velocity0 = vel
		self._damper = math.clamp(value, 0, 1)
	elseif key == "Speed" or key == "s" then
		local pos, vel = self:_positionVelocity(now)
		self._position0 = pos
		self._velocity0 = vel
		self._speed = math.max(value, 0)
	else
		error(string.format("%q is not a valid member of Spring", tostring(key)), 2)
	end
	self._time0 = now
end

function Spring:_positionVelocity(t)
	local p0 = self._position0
	local v0 = self._velocity0
	local target = self._target
	local d = self._damper
	local s = self._speed
	local t0 = self._time0

	local elapsed = s * (t - t0)
	local d2 = d * d

	local pos, vel

	if d2 < 1 then
		local w = math.sqrt(1 - d2)
		local expTerm = math.exp(-d * elapsed) / w
		local cosTerm = math.cos(w * elapsed)
		local sinTerm = math.sin(w * elapsed)

		local c1 = w * cosTerm + d * sinTerm
		local c2 = sinTerm

		pos = mul(p0, c1) + mul(target, 1 - c1) + mul(v0, c2 / s)
		vel = mul(target - p0, s * c2) + mul(v0, w * cosTerm - d * sinTerm)
	elseif d2 == 1 then
		local expTerm = math.exp(-d * elapsed)
		local linear = elapsed

		local c1 = expTerm * (1 + linear)
		local c2 = expTerm * linear

		pos = mul(p0, c1) + mul(target, 1 - c1) + mul(v0, c2 / s)
		vel = mul(target - p0, s * c2) + mul(v0, expTerm * (1 - linear))
	else
		local z = math.sqrt(d2 - 1)
		local exp1 = math.exp((-d + z) * elapsed) / (2 * z)
		local exp2 = math.exp((-d - z) * elapsed) / (2 * z)

		local c1 = exp1 + exp2
		local c2 = exp1 - exp2

		pos = mul(p0, z * c1 + d * c2) + mul(target, 1 - (z * c1 + d * c2)) + mul(v0, c2 / s)
		vel = mul(target - p0, s * c2) + mul(v0, z * c1 - d * c2)
	end

	return pos, vel
end

return Spring
