--!strict
-- Implements Embers through explicit effect dependencies.
return function(context: any)
local Debris=context.Debris
local EMBER_STYLES=context.EMBER_STYLES
local SPARK_TEXTURE=context.SPARK_TEXTURE
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

	local style = EMBER_STYLES[cue.Style or "Embers"] or EMBER_STYLES.Embers
	local scale = getScale(session.Character)

	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, style.Up * scale, 0)
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK_TEXTURE
	emitter.Color = style.Color
	emitter.LightEmission = style.Light
	emitter.Speed = style.Speed
	emitter.Lifetime = style.Lifetime
	emitter.Acceleration = style.Accel
	emitter.SpreadAngle = Vector2.new(style.Spread, style.Spread)
	emitter.Rate = style.Rate * (cue.Density or 1)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, style.Size * scale), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = attachment

	local t0 = os.clock()
	local duration = cue.Duration or 20
	addFx(session, {
		update = function() return root.Parent ~= nil and os.clock() - t0 < duration end,
		destroy = function()
			emitter.Enabled = false
			Debris:AddItem(attachment, 6)
		end,
	})
end

end
