--!strict
-- Tunes settings screen transitions and controls.
return {
	openTween = TweenInfo.new(0.65, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
	fadeTween = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	closeTween = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.In),
	switchTween = TweenInfo.new(0.45, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
	sliderTween = TweenInfo.new(0.12, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
	rowEntranceTween = TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
	tabFadeTween = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	hoverTween = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
	clickTween = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),

	rowStagger = 0.04,
	GearIconId = "rbxassetid://7059346373",
	BlurSize = 20,

	AccentColor = Color3.fromRGB(0, 170, 255),
	InactiveColor = Color3.fromRGB(40, 44, 58),
	HoverColorModifier = 25,

	ToggleMinX = 0.15,
	ToggleMaxX = 0.85,

	-- NOVO
	FriendCacheCap = 500,
}
