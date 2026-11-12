--!strict
-- Registers one media entry without editing the playback systems.
return {
	Version = 1,
	Entries = {
		YippeVideo = {
			Audio = {
				Frames = 9924,
				FPS = 60,
				Voices = 128,
				SegmentFrames = 120,
				Segments = 83,
				Encoding = 3,
				NoiseBands = 12,
				MixGain = 1.18239954,
				BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/352f014ce93cd3683c250256bb73aa96ac34b094/media/yippevideo/v3/audio",
				Preload = false,
			},
			Video = {
				Width = 384,
				Height = 216,
				FPS = 20,
				Frames = 3308,
				Duration = 165.395737,
				SegmentFrames = 40,
				Segments = 83,
				Encoding = 2,
				AudioTrack = "YippeVideo",
				Title = "YippeVideo",
				Preload = false,
				BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/352f014ce93cd3683c250256bb73aa96ac34b094/media/yippevideo/v3/video",
			},
			Emote = {
				Template = "PaniniEvent",
				Order = 16,
				Default = true,
				Exclusive = false,
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
