--!strict
-- Registers external video metadata; new clips only add one track and one emote entry.
local tracks = {
	YippeVideo = {
		Title = "Yippe Video", AudioTrack = "YippeVideo", Preload = true,
		Width = 256, Height = 144, FPS = 15, Frames = 2481, Duration = 165.395737,
		SegmentFrames = 30, Segments = 83, Encoding = 1,
		BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/9cf5b8a77791c62de7dc441e8d7d89568901527a/media/yippevideo/v2/video",
	},
}


local Library = require(game:GetService("ReplicatedStorage").Shared.Utils.MediaLibrary)
return Library.MergeTracks(tracks, game:GetService("ServerStorage"):FindFirstChild("MediaLibrary"), "Video")
