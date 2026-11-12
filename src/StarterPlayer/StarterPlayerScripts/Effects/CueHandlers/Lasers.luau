--!strict
-- Implements Lasers through explicit effect dependencies.
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
	local count = cue.Count or 8
	local length = cue.Length or 160
	local c1 = cue.Color or Color3.fromRGB(255, 60, 200)
	local c2 = cue.Color2 or c1
	local mode = cue.Mode or "Fan"
	local duration = cue.Duration or 20
	local speed = cue.Speed or 0.5

	local rigPart = anchorPart(root.Position)
	local lasers = {}
	for i = 1, count do
		local a0, a1 = newAttachment(rigPart), newAttachment(rigPart)
		local color = (i % 2 == 0) and c2 or c1
		lasers[i] = {
			a0 = a0, a1 = a1,
			core = newBeam(rigPart, a0, a1, color, 0.45 * scale, 0.12 * scale, 0.2),
			halo = newBeam(rigPart, a0, a1, color, 2.4 * scale, 0.6 * scale, 0.9),
		}
	end

	local t0 = os.clock()
	addFx(session, {
		update = function()
			local t = os.clock() - t0
			if t > duration + 1 or not root.Parent then return false end

			local visible = math.clamp(t / 0.6, 0, 1) * math.clamp((duration + 1 - t) / 1, 0, 1)
			local origin = root.Position + Vector3.new(0, 2 * scale, 0)
			rigPart.Position = origin

			for i, laser in ipairs(lasers) do
				local phase = (i / count) * math.pi * 2
				local direction = (mode == "Cross" and i % 2 == 0) and -1 or 1
				local angle = phase + t * speed * direction
				local elevation = mode == "Fan" and (0.25 + 0.25 * math.sin(t * 1.3 + phase)) or (0.6 + 0.3 * math.sin(t * 0.9 + phase))
				local dir = Vector3.new(math.cos(angle) * math.cos(elevation), math.sin(elevation), math.sin(angle) * math.cos(elevation))

				laser.a0.WorldPosition = origin
				laser.a1.WorldPosition = origin + dir * length

				local alpha = visible * (0.55 + 0.45 * session.energy)
				laser.core.Transparency = NumberSequence.new(1 - 0.85 * alpha)
				laser.halo.Transparency = NumberSequence.new(1 - 0.14 * alpha)
			end
			return true
		end,
		destroy = function() rigPart:Destroy() end,
	})
end

end
