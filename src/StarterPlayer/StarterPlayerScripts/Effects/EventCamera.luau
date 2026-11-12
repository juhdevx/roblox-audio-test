--!strict
-- Implements EventCamera through explicit effect dependencies.
return function(context: any)
local ATTACK=context.ATTACK
local DECAY=context.DECAY
local PULSE_DOLLY=context.PULSE_DOLLY
local PULSE_FOV=context.PULSE_FOV
local PULSE_ROLL=context.PULSE_ROLL
local PULSE_SHAKE=context.PULSE_SHAKE
local SPRING_C=context.SPRING_C
local SPRING_K=context.SPRING_K
local cameraMotionReduced=context.cameraMotionReduced
local getCamera=context.getCamera
local rig=context.rig
local scope=context.scope
local function springStep(spring, dt)
	spring.v += (-SPRING_K * spring.x - SPRING_C * spring.v) * dt
	spring.x += spring.v * dt
end

local function kickSpring(spring, amount) spring.v += amount * 30 end

local function rigKick(fov, roll, shake, rate)
	if cameraMotionReduced() then return end
	if fov ~= 0 then kickSpring(rig.fov, fov) end
	if roll ~= 0 then kickSpring(rig.roll, roll) end
	if shake > rig.shake then rig.shake = shake end
	rig.shakeRate = rate or 7
end

local function beatHit(strength)
	rig.pulseA = math.max(strength or 1, rig.pulseA * 0.7)
	rig.pulseT = 0
end

local function rigStep(dt)
	local camera = getCamera()
	if not camera then return end

	dt = math.min(dt, 1 / 30)
	local hidden = cameraMotionReduced()
	if hidden then
		rig.fov.x, rig.fov.v, rig.roll.x, rig.roll.v, rig.bob.x, rig.bob.v = 0, 0, 0, 0, 0, 0
		rig.shake, rig.pulseA, rig.pulseT = 0, 0, 999
	end

	rig.pulseT += dt
	local p = 0
	if rig.pulseT < ATTACK + DECAY then
		if rig.pulseT < ATTACK then
			local k = rig.pulseT / ATTACK
			p = rig.pulseA * k * k * (3 - 2 * k)
		else
			local e = 1 - (rig.pulseT - ATTACK) / DECAY
			p = rig.pulseA * e * e * e * e
		end
	end
	rig.pulse = p

	springStep(rig.fov, dt)
	springStep(rig.roll, dt)
	springStep(rig.bob, dt)
	rig.shake *= math.exp(-dt * rig.shakeRate)
	rig.t += dt

	rig.fovBase += (rig.fovTarget - rig.fovBase) * math.min(1, dt * 3)
	rig.tilt += (rig.tiltTarget - rig.tilt) * math.min(1, dt * 2.5)
	rig.push += (rig.pushTarget - rig.push) * math.min(1, dt * 2)

	camera.FieldOfView = rig.fovBase + rig.fov.x + p * PULSE_FOV

	local amplitude = hidden and 0 or (rig.shake + rig.rumble + p * PULSE_SHAKE)
	local n = rig.t * 11
	local x = math.noise(n, 1.7, 0.3) * 2 * amplitude
	local y = math.noise(n, 5.3, 0.3) * 2 * amplitude + rig.bob.x + p * PULSE_DOLLY * 0.3
	local z = rig.push - p * PULSE_DOLLY
	local roll = rig.roll.x + rig.tilt + p * PULSE_ROLL + math.noise(n, 9.1, 0.3) * amplitude * 0.5

	camera.CFrame = camera.CFrame * CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(roll))
end

local function rigReset()
	local camera = getCamera()
	if camera then camera.FieldOfView = rig.originalFov end
	rig.fov.x, rig.fov.v, rig.roll.x, rig.roll.v, rig.bob.x, rig.bob.v = 0, 0, 0, 0, 0, 0
	rig.shake, rig.rumble, rig.pulse, rig.pulseA, rig.pulseT = 0, 0, 0, 0, 999
	rig.tilt, rig.tiltTarget, rig.push, rig.pushTarget = 0, 0, 0, 0
	rig.fovBase, rig.fovTarget = rig.originalFov, rig.originalFov
end


return {springStep=springStep,kickSpring=kickSpring,rigKick=rigKick,beatHit=beatHit,rigStep=rigStep,rigReset=rigReset}
end
