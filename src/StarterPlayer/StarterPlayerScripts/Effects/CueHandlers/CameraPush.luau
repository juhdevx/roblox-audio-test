--!strict
-- Implements CameraPush through explicit effect dependencies.
return function(context: any)
local cameraMotionReduced=context.cameraMotionReduced
local handlers=context.handlers
local rig=context.rig
local scope=context.scope
return function(_, cue)
	if cameraMotionReduced() then return end
	local strength = cue.Strength or 2
	rig.pushTarget = (cue.Direction == "Out") and strength or -strength
	scope:Delay(cue.Duration or 2, function() rig.pushTarget = 0 end)
end

end
