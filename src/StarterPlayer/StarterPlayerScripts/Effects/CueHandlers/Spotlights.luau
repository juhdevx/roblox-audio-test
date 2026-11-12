--!strict
-- Implements Spotlights through explicit effect dependencies.
return function(context: any)
local WHITE=context.WHITE
local addFx=context.addFx
local anchorPart=context.anchorPart
local getRoot=context.getRoot
local getScale=context.getScale
local handlers=context.handlers
local newAttachment=context.newAttachment
local newBeam=context.newBeam
local rig=context.rig
local scope=context.scope
local vfxHidden=context.vfxHidden
return function(session, cue)
	if vfxHidden() then return end
	local root = getRoot(session)
	if not root then return end

	local scale = getScale(session.Character)
	local count = cue.Count or 5
	local color = cue.Color or WHITE
	local duration = cue.Duration or 10

	local rigPart = anchorPart(root.Position)
	local cones = {}
	for i = 1, count do
		local a0, a1 = newAttachment(rigPart), newAttachment(rigPart)
		cones[i] = {
			a0 = a0, a1 = a1,
			core = newBeam(rigPart, a0, a1, color, 0.5 * scale, 6 * scale, 0.9),
			halo = newBeam(rigPart, a0, a1, color, 1.5 * scale, 14 * scale, 0.96),
		}
	end

	local t0 = os.clock()
	addFx(session, {
		update = function()
			local t = os.clock() - t0
			if t > duration + 1 or not root.Parent then return false end

			local visible = math.clamp(t / 0.8, 0, 1) * math.clamp((duration + 1 - t) / 1, 0, 1)
			local center = root.Position
			rigPart.Position = center

			for i, cone in ipairs(cones) do
				local angle = t * 0.2 + (i / count) * math.pi * 2
				cone.a0.WorldPosition = center + Vector3.new(math.cos(angle) * 36 * scale, 80 * scale, math.sin(angle) * 36 * scale)
				cone.a1.WorldPosition = center + Vector3.new(math.cos(angle) * 6 * scale, -3 * scale, math.sin(angle) * 6 * scale)

				local alpha = visible * (0.55 + 0.35 * math.min(rig.pulse, 1))
				cone.core.Transparency = NumberSequence.new(1 - 0.35 * alpha)
				cone.halo.Transparency = NumberSequence.new(1 - 0.12 * alpha)
			end
			return true
		end,
		destroy = function() rigPart:Destroy() end,
	})
end
end
