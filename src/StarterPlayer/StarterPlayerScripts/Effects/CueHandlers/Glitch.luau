--!strict
-- Implements Glitch through explicit effect dependencies.
return function(context: any)
local TweenService=context.TweenService
local WHITE=context.WHITE
local getEffect=context.getEffect
local handlers=context.handlers
local rigKick=context.rigKick
local scope=context.scope
local vfxHidden=context.vfxHidden
return function(_, cue)
	if vfxHidden() then return end
	local grade = getEffect("EventGlitch", "ColorCorrectionEffect")
	local tint = cue.Tint or WHITE
	scope:Spawn(function()
		for i = 1, 3 do
			grade.TintColor = (i % 2 == 1) and tint or tint:Lerp(WHITE, 0.5)
			grade.Contrast = 0.25
			grade.Saturation = (i % 2 == 1) and 0.5 or -0.3
			task.wait(0.04)
		end
		scope:Tween(grade, TweenInfo.new(cue.Duration or 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TintColor = WHITE, Contrast = 0, Saturation = 0,
		}):Play()
	end)
	rigKick(2, 1.5, 0.15, 9)
end

end
