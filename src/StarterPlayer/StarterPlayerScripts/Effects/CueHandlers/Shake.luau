--!strict
-- Implements Shake through explicit effect dependencies.
return function(context: any)
local handlers=context.handlers
local rigKick=context.rigKick
local scope=context.scope
return function(_, cue)
	rigKick(0, 0, cue.Intensity or 0.3, 3 / math.max(cue.Duration or 0.5, 0.1))
end

end
