--!strict
-- Implements Letterbox through explicit effect dependencies.
return function(context: any)
local LocalPlayer=context.LocalPlayer
local TweenService=context.TweenService
local handlers=context.handlers
local scope=context.scope
local visualState=context.visualState
return function(_, cue)
	local amount = math.clamp(cue.Amount or 0, 0, 0.45)
	local duration = cue.Duration or 1

	if not visualState.letterbox then
		local gui = Instance.new("ScreenGui")
		gui.Name = "EmoteLetterbox"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 90

		local top = Instance.new("Frame")
		top.Name = "Top"
		top.BackgroundColor3 = Color3.new(0, 0, 0)
		top.BorderSizePixel = 0
		top.Size = UDim2.fromScale(1, 0)
		top.Parent = gui

		local bottom = top:Clone()
		bottom.Name = "Bottom"
		bottom.AnchorPoint = Vector2.new(0, 1)
		bottom.Position = UDim2.fromScale(0, 1)
		bottom.Parent = gui

		gui.Parent = LocalPlayer:WaitForChild("PlayerGui",10)
		visualState.letterbox = gui
	end

	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for _, name in ipairs({ "Top", "Bottom" }) do
		scope:Tween(visualState.letterbox[name], info, { Size = UDim2.fromScale(1, amount) }):Play()
	end
end

end
