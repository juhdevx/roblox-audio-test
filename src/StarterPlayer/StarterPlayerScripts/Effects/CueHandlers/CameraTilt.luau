--!strict
-- Implements CameraTilt through explicit effect dependencies.
return function(context: any)
local cameraMotionReduced=context.cameraMotionReduced
local handlers=context.handlers
local rig=context.rig
local scope=context.scope
return function(_, cue)
	if not cameraMotionReduced() then rig.tiltTarget = cue.Angle or 0 end
end

end
