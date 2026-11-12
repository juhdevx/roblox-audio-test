--!strict
-- Implements Pulse through explicit effect dependencies.
return function(context: any)
local beatHit=context.beatHit
local handlers=context.handlers
local rigKick=context.rigKick
local scope=context.scope
return function(_, cue)
	rigKick(cue.FOV or 6, 0, 0, 7)
	beatHit(1)
end

end
