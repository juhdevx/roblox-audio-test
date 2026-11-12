--!strict
-- Implements Smoke through explicit effect dependencies.
return function(context: any)
local Debris=context.Debris
local SMOKE_TEXTURE=context.SMOKE_TEXTURE
local addFx=context.addFx
local getRoot=context.getRoot
local getScale=context.getScale
local handlers=context.handlers
local scope=context.scope
local vfxHidden=context.vfxHidden
return function(session, cue)
	if vfxHidden() then return end
	local root = getRoot(session)
	if not root then return end

	local color = cue.Color or Color3.fromRGB(80, 80, 80)
	local duration = cue.Duration or 8
	local scale = getScale(session.Character)

	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, -2 * scale, 0)
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE_TEXTURE
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.15
	emitter.Rate = 22 * (cue.Density or 1)
	emitter.Lifetime = NumberRange.new(2.5, 4.5)
	emitter.Speed = NumberRange.new(2, 6)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3 * scale), NumberSequenceKeypoint.new(1, 10 * scale),
	})
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = attachment

	local t0 = os.clock()
	addFx(session, {
		update = function() return root.Parent ~= nil and os.clock() - t0 < duration end,
		destroy = function()
			emitter.Enabled = false
			Debris:AddItem(attachment, 8)
		end,
	})
end

end
