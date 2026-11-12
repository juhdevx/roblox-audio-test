--!strict
-- Implements Equalizer through explicit effect dependencies.
return function(context: any)
local addFx=context.addFx
local anchorPart=context.anchorPart
local getRoot=context.getRoot
local getScale=context.getScale
local handlers=context.handlers
local newAttachment=context.newAttachment
local newBeam=context.newBeam
local scope=context.scope
local vfxHidden=context.vfxHidden
return function(session, cue)
	if vfxHidden() then return end
	local root = getRoot(session)
	if not root then return end

	local scale = getScale(session.Character)
	local count = cue.Bars or 28
	local radius = (cue.Radius or 28) * scale
	local c1 = cue.Color or Color3.fromRGB(80, 200, 255)
	local c2 = cue.Color2 or c1
	local duration = cue.Duration or 30

	local rigPart = anchorPart(root.Position)
	local bars, heights, targets = {}, {}, {}
	for i = 1, count do
		local a0, a1 = newAttachment(rigPart), newAttachment(rigPart)
		local color = c1:Lerp(c2, i / count)
		bars[i] = {
			a0 = a0, a1 = a1,
			core = newBeam(rigPart, a0, a1, color, 1.3 * scale, 0.5 * scale, 0.3),
			halo = newBeam(rigPart, a0, a1, color, 3.6 * scale, 1.6 * scale, 0.9),
		}
		heights[i], targets[i] = 1, 1
	end

	local t0 = os.clock()
	local lastTick = -1
	addFx(session, {
		update = function(dt)
			local t = os.clock() - t0
			if t > duration + 1 or not root.Parent then return false end

			if session.beatTick ~= lastTick then
				lastTick = session.beatTick
				for i = 1, count do targets[i] = (2 + math.random() * (8 + 12 * session.energy)) * scale end
			end

			local visible = math.clamp(t / 0.6, 0, 1) * math.clamp((duration + 1 - t) / 1, 0, 1)
			local center = root.Position
			local floorY = center.Y - 3 * scale
			rigPart.Position = center

			for i, bar in ipairs(bars) do
				heights[i] += (targets[i] - heights[i]) * math.min(1, dt * 10)
				local angle = (i / count) * math.pi * 2
				local x, z = center.X + math.cos(angle) * radius, center.Z + math.sin(angle) * radius
				bar.a0.WorldPosition = Vector3.new(x, floorY, z)
				bar.a1.WorldPosition = Vector3.new(x, floorY + math.max(heights[i], 0.3), z)
				bar.core.Transparency = NumberSequence.new(1 - 0.75 * visible)
				bar.halo.Transparency = NumberSequence.new(1 - 0.12 * visible)
			end
			return true
		end,
		destroy = function() rigPart:Destroy() end,
	})
end

end
