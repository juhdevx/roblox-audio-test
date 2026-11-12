--!strict
-- Selects the reversible audio experiment for the existing TestSound emote.
return table.freeze({
	TestSound = table.freeze({
		Enabled = true,
		StandardTrack = "WoahUseIt",
		ExperimentalTrack = "WoahUseItPhaseFit",
	}),
})
