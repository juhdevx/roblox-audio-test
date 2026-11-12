--!strict
-- Implements Chromatic through explicit effect dependencies.
return function(context: any)
local TweenService=context.TweenService
local getEffect=context.getEffect
local handlers=context.handlers
local scope=context.scope
local vfxHidden=context.vfxHidden
return function(_, cue)
	if vfxHidden() then return end
	local grade = getEffect("EventChroma", "ColorCorrectionEffect")
	grade.Saturation = math.min((cue.Intensity or 0.3) * 0.6, 0.4)
	scope:Tween(grade, TweenInfo.new(cue.Duration or 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Saturation = 0 }):Play()
end

end
