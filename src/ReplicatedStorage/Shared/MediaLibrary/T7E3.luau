--!strict
-- Registers one media entry without editing the playback systems.
return {
	Version = 1,
	Entries = {
		T7E3 = {
			Emote = {
				Template = "PaniniEvent",
				Order = 0,
				Default = false,
				Exclusive = true,
				ReplaceExisting = false,
				Song = {
					Backend = "Spectral",
					Track = "T7E3",
					Volume = 2.25,
					PlaybackSpeed = 1,
					Video = "T7E3",
				},
				DisableEmoteCamera = true,
			},
		},
	},
}
