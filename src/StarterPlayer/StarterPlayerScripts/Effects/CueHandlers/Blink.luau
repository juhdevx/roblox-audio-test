--!strict
-- Implements Blink through explicit effect dependencies.
return function(context: any)
local Debris=context.Debris
local SPARK_TEXTURE=context.SPARK_TEXTURE
local TweenService=context.TweenService
local WHITE=context.WHITE
local beatHit=context.beatHit
local emitBurst=context.emitBurst
local getRoot=context.getRoot
local getScale=context.getScale
local handlers=context.handlers
local scope=context.scope
local spawnDome=context.spawnDome
local vfxHidden=context.vfxHidden
local vfxParent=context.vfxParent
return function(session, cue)
	if vfxHidden() then return end
	local character, root = session.Character, getRoot(session)
	if not root then return end

	local color = cue.Color or Color3.fromRGB(255, 130, 40)
	local duration = cue.Duration or 0.7
	local scale = getScale(character)

	local highlight = Instance.new("Highlight")
	highlight.Adornee = character
	highlight.FillColor = color
	highlight.OutlineColor = WHITE
	highlight.FillTransparency = 0.15
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = vfxParent()
	scope:Tween(highlight, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		FillTransparency = 1, OutlineTransparency = 1,
	}):Play()
	Debris:AddItem(highlight, duration + 0.2)

	local feet = root.Position - Vector3.new(0, 3 * scale, 0)
	spawnDome(feet, color, 14 * scale, duration)
	emitBurst(root, color, cue.Particles or 40, 20, 0.8, 0.7 * scale, SPARK_TEXTURE)
	beatHit(0.8)
end

end
