--!strict
-- Tunes R6 posture, ground adaptation, and relay cadence.
return {
	enabled = true,
	torsoTurnAmount = math.rad(((16 / 2.5) * 1.5) * 1.5),
	torsoPitchAmount = math.rad((8 / 2.5) * 1.5),
	headYawAmount = math.rad(55),
	headPitchAmount = math.rad(35) * 1.75,
	legSideAmount = math.rad(12),
	bobAmount = 0.04,
	tiltAmount = math.rad(4),
	smoothness = 10,
	rayHeight = 2.5,
	rayLength = 8,
	maxLegRaise = 1.5,
	footSpread = 0.28,
	footForward = 0.1,
	supportTolerance = 0.12,
	maxGroundDiff = 2.5,
	maxFootDistance = 5.5,
	raisedForward = 0.05,
	raisedSide = 0.05,
	sendRate = 20,

	-- Câmera de frente: o giro some entre FadeStart e FadeEnd (ângulo da câmera em relação ao corpo)
	frontFadeStart = math.rad(80),
	frontFadeEnd = math.rad(140),
}
