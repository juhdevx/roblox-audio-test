--!strict
-- Implements Flash through explicit effect dependencies.
return function(context: any)
local TweenService=context.TweenService
local WHITE=context.WHITE
local getEffect=context.getEffect
local handlers=context.handlers
local scope=context.scope
local vfxHidden=context.vfxHidden
return function(_, cue)
	if vfxHidden() then return end
	local intensity = math.clamp(cue.Intensity or 0.5, 0, 1.5)
	local bloom = getEffect("EventFlashBloom", "BloomEffect")
	local grade = getEffect("EventFlash", "ColorCorrectionEffect")
	bloom.Intensity, bloom.Size, bloom.Threshold = intensity * 1.6, 40, 0.6
	grade.Brightness = intensity * 0.08
	grade.TintColor = (cue.Color or WHITE):Lerp(WHITE, 0.5)
	local info = TweenInfo.new(cue.Duration or 0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	scope:Tween(bloom, info, { Intensity = 0, Threshold = 2 }):Play()
	scope:Tween(grade, info, { Brightness = 0, TintColor = WHITE }):Play()
end

end
