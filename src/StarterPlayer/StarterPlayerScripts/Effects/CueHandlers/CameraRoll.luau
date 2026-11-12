--!strict
-- Implements CameraRoll through explicit effect dependencies.
return function(context: any)
local handlers=context.handlers
local rigKick=context.rigKick
local scope=context.scope
return function(_, cue)
	rigKick(0, math.clamp((cue.Speed or 60) / 30, -6, 6), 0, 7)
end

end
