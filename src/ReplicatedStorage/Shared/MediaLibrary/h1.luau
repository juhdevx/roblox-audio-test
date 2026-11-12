--!strict
-- Registers one media entry without editing the playback systems.
return {
	Version = 1,
	Entries = {
		h1 = {
			Emote = {
				Template = "PaniniEvent",
				Order = 0,
				Default = false,
				Exclusive = true,
				ReplaceExisting = false,
				Song = {
					Backend = "Spectral",
					Track = "h1",
					Volume = 1,
					PlaybackSpeed = 1,
					Video = "h1",
				},
				DisableEmoteCamera = true,
			},
		},
	},
}
