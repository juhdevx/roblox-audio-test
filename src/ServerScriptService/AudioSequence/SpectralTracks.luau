--!strict
-- Registers hosted spectral tracks; adding music changes this data and its emote definition.
local tracks = {
	YippeVideo = {
		Frames = 9924, FPS = 60, Voices = 96, SegmentFrames = 120, Segments = 83,
		Encoding = 3, NoiseBands = 12, MixGain = 1.19130709, Preload = false,
		BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/89491c92e318a89381f171dd184cf41488965d15/media/yippevideo/v1/audio",
	},
	WoahUseIt = {
		MixGain = 1.08497145,
		Frames = 6902, FPS = 60, Voices = 128, Encoding = 3, NoiseBands = 12, SegmentFrames = 120, Segments = 58,
		Preload = true,
		BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/f1b98fe061ed17206c9ae14999fe79909ee1e414/spectral/v4/source-fit",
	},
	WoahUseItPhaseFit = {
		MixGain = 1.09949041,
		Frames = 6902, FPS = 60, Voices = 128, Encoding = 3, NoiseBands = 12, SegmentFrames = 120, Segments = 58,
		Preload = true,
		BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/8a19a0de008f91644cdd14c60aa03c26b08a7d30/spectral/v5/phase-pan-fit",
	},
	
	Drake___You_Broke_My_Heart__Audio_ = {
		MixGain = 1.17841877,
		Frames = 13847, FPS = 60, Voices = 96, Encoding = 3, NoiseBands = 12, SegmentFrames = 120, Segments = 116,
		Preload = true,
		BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/d489b0336865d07a506fa9534b4ba36220d76783/spectral/v3"
	},
	
	["Check_from_Tel_Aviv___DaveDaHow"] = {
		Frames = 10544, FPS = 60, Voices = 96, SegmentFrames = 120, Segments = 88, Encoding = 3, NoiseBands = 12,
		MixGain = 1.20545308,
		BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/main/spectral/v3"
	},
	
	["maybe"] = {
		Frames = 10960, FPS = 60, Voices = 96, SegmentFrames = 120, Segments = 92, Encoding = 3, NoiseBands = 12,
		MixGain = 1.29226783,
		BaseUrl = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/main/spectral/v3"
	},
}


local Library = require(game:GetService("ReplicatedStorage").Shared.Utils.MediaLibrary)
return Library.MergeTracks(tracks, game:GetService("ServerStorage"):FindFirstChild("MediaLibrary"), "Audio")
