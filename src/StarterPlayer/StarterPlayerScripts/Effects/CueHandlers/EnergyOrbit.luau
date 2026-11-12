--!strict
-- Implements EnergyOrbit through explicit effect dependencies.
return function(context: any)
local AttachmentController=context.AttachmentController
local WHITE=context.WHITE
local addFx=context.addFx
local getScale=context.getScale
local handlers=context.handlers
local newPart=context.newPart
local rig=context.rig
local scope=context.scope
local vfxHidden=context.vfxHidden
return function(session, cue)
	if vfxHidden() then return end
	local character = session.Character
	if not character then return end

	local scale = getScale(character)
	local count = cue.Count or 3
	local radius = (cue.Radius or 6) * scale
	local color = cue.Color or Color3.fromRGB(150, 100, 220)
	local speed = cue.Speed or 1.5
	local duration = cue.Duration or 20

	local attachment = AttachmentController.GetAttachment(character, "Chest", { sessionId = session.Id })
	if not attachment then return end

	local rings = {}
	for i = 1, count do
		local part = newPart(Vector3.new(0.15 * scale, radius * 0.5, radius * 0.5), color, 0.2)
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.Neon
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Parent = attachment

		rings[i] = {
			part = part,
			phase = (i / count) * math.pi * 2,
			tilt = math.random() * math.pi,
		}
	end

	local t0 = os.clock()
	addFx(session, {
		update = function()
			local t = os.clock() - t0
			if t > duration or not character.Parent then return false end

			local pulse = math.min(rig.pulse, 1)
			for _, ring in ipairs(rings) do
				local p = ring.part
				if p.Parent then
					local angle = t * speed + ring.phase
					local tilt = ring.tilt + t * 0.5
					local offset = CFrame.new(0, 0, 0)
						* CFrame.Angles(tilt, 0, 0)
						* CFrame.new(0, 0, radius)
					p.CFrame = attachment.WorldCFrame * offset * CFrame.Angles(0, 0, math.rad(90 + angle * 20))
					local sizeMul = 0.5 + pulse * 0.1
					p.Size = Vector3.new(0.15 * scale, radius * sizeMul, radius * sizeMul)
					p.Color = color:Lerp(WHITE, pulse * 0.4)
				end
			end
			return true
		end,
		destroy = function()
			for _, ring in ipairs(rings) do
				if ring.part.Parent then ring.part:Destroy() end
			end
		end,
	})
end

end
