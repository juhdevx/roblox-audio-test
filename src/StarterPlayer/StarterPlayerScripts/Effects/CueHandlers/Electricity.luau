--!strict
-- Implements Electricity through explicit effect dependencies.
return function(context: any)
local AttachmentController=context.AttachmentController
local SPARK_TEXTURE=context.SPARK_TEXTURE
local WHITE=context.WHITE
local addFx=context.addFx
local getScale=context.getScale
local handlers=context.handlers
local scope=context.scope
local vfxHidden=context.vfxHidden
return function(session, cue)
	if vfxHidden() then return end
	local character = session.Character
	if not character then return end

	local scale = getScale(character)
	local leftHand = AttachmentController.GetAttachment(character, "LeftHand", { sessionId = session.Id })
	local rightHand = AttachmentController.GetAttachment(character, "RightHand", { sessionId = session.Id })
	if not leftHand or not rightHand then return end

	local color = cue.Color or Color3.fromRGB(100, 200, 255)

	local beam = Instance.new("Beam")
	beam.Name = "ElectricityBeam"
	beam.Attachment0 = leftHand
	beam.Attachment1 = rightHand
	beam.Color = ColorSequence.new(color, WHITE)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = 0.4 * scale
	beam.Width1 = 0.4 * scale
	beam.Segments = 10
	beam.Width0 = 0.12 * scale; beam.Width1 = beam.Width0
	beam.CurveSize0 = 2 * scale
	beam.CurveSize1 = -2 * scale
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new(0.15)
	beam.Parent = leftHand

	local halo = Instance.new("Beam")
	halo.Attachment0 = leftHand
	halo.Attachment1 = rightHand
	halo.Color = ColorSequence.new(color)
	halo.LightEmission = 1
	halo.LightInfluence = 0
	halo.Width0 = 1.2 * scale
	halo.Width1 = 1.2 * scale
	halo.Segments = 10
	halo.Transparency = NumberSequence.new(0.7)
	halo.FaceCamera = true
	halo.Parent = leftHand

	local sparkA = Instance.new("ParticleEmitter")
	sparkA.Texture = SPARK_TEXTURE
	sparkA.Color = ColorSequence.new(color, WHITE)
	sparkA.LightEmission = 1
	sparkA.Rate = 30
	sparkA.Lifetime = NumberRange.new(0.2, 0.5)
	sparkA.Speed = NumberRange.new(2, 6)
	sparkA.SpreadAngle = Vector2.new(180, 180)
	sparkA.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3 * scale), NumberSequenceKeypoint.new(1, 0) })
	sparkA.Parent = leftHand

	local sparkB = sparkA:Clone()
	sparkB.Parent = rightHand

	local t0 = os.clock()
	local duration = cue.Duration or 5

	addFx(session, {
		update = function()
			local t = os.clock() - t0
			if t > duration or not character.Parent then return false end
			local pulse = math.sin(t * 40) * 0.5 + 0.5
			beam.Segments = 8 + math.floor(pulse * 4)
			beam.Width0 = (0.08 + pulse * 0.08) * scale; beam.Width1 = beam.Width0
			beam.Transparency = NumberSequence.new(0.15 + pulse * 0.2)
			halo.Transparency = NumberSequence.new(0.7 + pulse * 0.2)
			return true
		end,
		destroy = function()
			pcall(function() beam:Destroy() end)
			pcall(function() halo:Destroy() end)
			pcall(function() sparkA:Destroy() end)
			pcall(function() sparkB:Destroy() end)
		end,
	})
end

end
