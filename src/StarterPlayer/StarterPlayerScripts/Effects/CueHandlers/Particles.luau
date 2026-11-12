--!strict
-- Implements Particles through explicit effect dependencies.
return function(context: any)
local SPARK_TEXTURE=context.SPARK_TEXTURE
local WHITE=context.WHITE
local emitBurst=context.emitBurst
local getRoot=context.getRoot
local getScale=context.getScale
local handlers=context.handlers
local scope=context.scope
local vfxHidden=context.vfxHidden
return function(session, cue)
	if vfxHidden() then return end
	local root = getRoot(session)
	if not root then return end
	emitBurst(root, cue.Color or WHITE, cue.Count or 50, cue.Speed or 10, cue.Lifetime or 2, (cue.Size or 0.6) * getScale(session.Character), SPARK_TEXTURE)
end

end
