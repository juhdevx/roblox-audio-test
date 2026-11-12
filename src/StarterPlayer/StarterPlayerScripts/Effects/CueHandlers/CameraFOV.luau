--!strict
-- Implements CameraFOV through explicit effect dependencies.
return function(context: any)
local cameraMotionReduced=context.cameraMotionReduced
local handlers=context.handlers
local rig=context.rig
local scope=context.scope
return function(_, cue)
	if cue.Value and not cameraMotionReduced() then rig.fovTarget = cue.Value end
end

end
