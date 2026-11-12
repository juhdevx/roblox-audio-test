--!strict
-- Implements Lightning through explicit effect dependencies.
return function(context: any)
local WHITE=context.WHITE
local addFx=context.addFx
local anchorPart=context.anchorPart
local beatHit=context.beatHit
local getRoot=context.getRoot
local getScale=context.getScale
local handlers=context.handlers
local newAttachment=context.newAttachment
local newBeam=context.newBeam
local rigKick=context.rigKick
local scope=context.scope
local vfxHidden=context.vfxHidden
return function(session, cue)
	if vfxHidden() then return end
	local root = getRoot(session)
	if not root then return end

	local scale = getScale(session.Character)
	local color = cue.Color or Color3.fromRGB(190, 220, 255)
	local target = root.Position
	local top = target + Vector3.new(math.random(-14, 14), 150, math.random(-14, 14))

	local points = {}
	for i = 0, 7 do
		local p = top:Lerp(target, i / 7)
		if i > 0 and i < 7 then p += Vector3.new(math.random(-9, 9), 0, math.random(-9, 9)) end
		points[i + 1] = p
	end

	local rigPart = anchorPart(target)
	local beams = {}
	for i = 1, 7 do
		local a0, a1 = newAttachment(rigPart, points[i]), newAttachment(rigPart, points[i + 1])
		table.insert(beams, newBeam(rigPart, a0, a1, WHITE, 1.1 * scale, 1.1 * scale, 0))
		table.insert(beams, newBeam(rigPart, a0, a1, color, 6 * scale, 6 * scale, 0.7))
	end

	local t0 = os.clock()
	addFx(session, {
		update = function()
			local t = os.clock() - t0
			if t > 0.45 then return false end
			local fade = 1 - t / 0.45
			for i, beam in ipairs(beams) do
				beam.Transparency = NumberSequence.new(1 - fade * ((i % 2 == 1) and 1 or 0.3))
			end
			return true
		end,
		destroy = function() rigPart:Destroy() end,
	})

	handlers.Flash(session, { Color = color, Intensity = 1, Duration = 0.6 })
	rigKick(10, 3, 0.8, 5)
	beatHit(1.4)
end

end
