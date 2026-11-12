--!strict
-- Registers one media entry without editing the playback systems.
return {
	Version = 1,
	Entries = {
		T7E3 = {
			Audio = {
				Frames = 85409,
				FPS = 60,
				Voices = 128,
				SegmentFrames = 120,
				Segments = 712,
				Encoding = 3,
				NoiseBands = 12,
				MixGain = 1.15144934,
				BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/a4a2913aee9d7bc9db647271bb7620b1783a086b/media/Miraculous/T7/Ep3/audio",
				Preload = false,
			},
			Video = {
				Width = 422,
				Height = 237,
				FPS = 24,
				Frames = 34164,
				Duration = 1423.4761,
				SegmentFrames = 48,
				Segments = 712,
				Encoding = 2,
				AudioTrack = "T7E3",
				Title = "T7E3",
				Preload = false,
				BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/a4a2913aee9d7bc9db647271bb7620b1783a086b/media/Miraculous/T7/Ep3/video",
			},
			Emote = {
				Template = "PaniniEvent",
				Order = 0,
				Default = false,
				Exclusive = true,
				ReplaceExisting = false,
				Song = {
					Backend = "Spectral",
					Track = "T7E3",
					Volume = 6,
					PlaybackSpeed = 1,
					Video = "T7E3",
				},
				DisableEmoteCamera = true,
			},
		},
	},
}
