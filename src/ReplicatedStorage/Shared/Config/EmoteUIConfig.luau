--!strict
-- Tunes emote screen transitions and layout.
return {
	openTween = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	fadeTween = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	closeTween = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	hoverInTween = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	hoverOutTween = TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
	editButtonTween = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	editLabelTween = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	slotEntranceTween = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	slotExitTween = TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
	itemEntranceTween = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	previewZoomTween = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	breatheTween = TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	pulseTween = TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),

	slotStagger = 0.045,
	itemStagger = 0.03,

	wheelOpenSize = UDim2.fromScale(0.43, 0.43),
	wheelClosedSize = UDim2.fromScale(0.16, 0.16),
	wheelOpenPosition = UDim2.fromScale(0.5, 0.5),
	wheelClosedPosition = UDim2.fromScale(0.5, 0.55),

	shadowOpenAlpha = 0.4,
	shadowBreatheAlpha = 0.24,
	shadowClosedAlpha = 1,
	imageOpenAlpha = 0.15,
	imageClosedAlpha = 1,
	blurSize = 18,

	dropdownOpenSize = UDim2.fromScale(0.36, 0.68),
	dropdownClosedSize = UDim2.fromScale(0.1, 0.25),
	previewOpenPosition = UDim2.fromScale(1.225, 0.5),
	previewClosedPosition = UDim2.fromScale(0.5, 0.5),

	editButtonHome = UDim2.fromScale(0.5, 0.5),
	editButtonActive = UDim2.new(0.5, 0, 0.57, 0),
	editLabelHome = UDim2.fromScale(-0.235, -0.35),
	editLabelActive = UDim2.new(-0.235, 0, -2.25, 0),

	slotHoverSize = UDim2.fromScale(0.36, 0.36),
	slotRestSize = UDim2.fromScale(0.33, 0.33),
	slotHiddenSize = UDim2.fromScale(0, 0),

	slotHoverRotation = 5,
	slotRestRotation = 0,
	slotSpinAngle = 60,

	previewZoomStart = 0.8,
	previewZoomEnd = 1,
}
