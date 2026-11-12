--!strict
-- Registers one media entry without editing the playback systems.
return {
	Version = 1,
	Entries = {
		h1 = {
			Audio = {
				Frames = 44882,
				FPS = 60,
				Voices = 128,
				SegmentFrames = 120,
				Segments = 375,
				Encoding = 3,
				NoiseBands = 12,
				MixGain = 1.18989878,
				BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/main/media/Secret/h1/audio",
				Preload = false,
			},
			Video = {
				Width = 334,
				Height = 188,
				FPS = 24,
				Frames = 17953,
				Duration = 748.033333,
				SegmentFrames = 48,
				Segments = 375,
				Encoding = 2,
				AudioTrack = "h1",
				Title = "h1",
				Preload = false,
				BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/main/media/Secret/h1/video",
			},
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
