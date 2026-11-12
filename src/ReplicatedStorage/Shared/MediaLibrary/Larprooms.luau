--!strict
-- Registers one media entry without editing the playback systems.
return {
	Version = 1,
	Entries = {
		Larprooms = {
			Emote = {
				Template = "PaniniEvent",
				Order = 16,
				Default = false,
				Exclusive = true,
				ReplaceExisting = true,
				Song = {
					Backend = "Spectral",
					Track = "YippeVideo",
					Volume = 1,
					PlaybackSpeed = 1,
					Video = "YippeVideo",
				},
				DisableEmoteCamera = true,
			},
		},
	},
}
