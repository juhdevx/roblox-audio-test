--!strict
return {
	{
		Id = "Audio",
		Name = "Audio & Music",
		Settings = {
			{
				Id = "MediaVolume",
				Type = "Slider",
				Name = "Media Volume",
				Min = 0,
				Max = 1,
				Step = 0.05,
				Default = 1,
			},
			{
				Id = "MediaClearDialogue",
				Type = "Toggle",
				Name = "Clearer Dialogue",
				Default = false,
			},
			{
				Id = "OtherPlayersVolume",
				Type = "Slider",
				Name = "Others Emote Volume",
				Min = 0,
				Max = 1,
				Step = 0.05,
				Default = 1,
			},
		},
	},
	{
		Id = "Visuals",
		Name = "Camera & Display",
		Settings = {
			{
				Id = "VideoScreenScale",
				Type = "Slider",
				Name = "Video Screen Size",
				Min = 0.75,
				Max = 1.5,
				Step = 0.05,
				Default = 1,
			},
			{
				Id = "EmoteCameraIntensity",
				Type = "Slider",
				Name = "Camera Tracking Speed",
				Min = 1,
				Max = 10,
				Step = 1,
				Default = 5,
			},
			{
				Id = "ReduceMotion",
				Type = "Toggle",
				Name = "Reduce Camera Bounce",
				Default = false,
			},
			{
				Id = "HideEmoteVFX",
				Type = "Toggle",
				Name = "Hide Emote Trails & VFX",
				Default = false,
			},
		},
	},
	{
		Id = "Social",
		Name = "Social & Interaction",
		Settings = {
			--[[{
				Id = "AllowSyncing",
				Type = "Toggle",
				Name = "Allow Emote Syncing",
				Default = true,
			},]]
			{
				Id = "DummyFriend",
				Type = "FriendPicker",
				Name = "VFX Target Avatar",
				Default = nil,
			},
		},
	},
}
