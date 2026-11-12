--!strict
-- Implements Look through explicit effect dependencies.
return function(context: any)
local applyLook=context.applyLook
local handlers=context.handlers
local scope=context.scope
return function(_, cue) applyLook(cue.Look or cue, cue.Duration or 1.5) end
end
