--!strict
-- Declares server effects for Anger.
return {
    Name = "Anger",
	{
		Type = "BarsMeter",
		Action = "Start",

		Params = {
			Model = "Bars",
			AttachTo = "HumanoidRootPart",
			Offset = CFrame.new(0, 0, 0),
			Orientation = Vector3.new(0, 0, 0),

			AnimationId = "rbxassetid://90557253038800",
			TotalFrames = 224, 
			Cycles = 2, 
			Fps = 30,
			Speed = 1.2,
			TimeOffset = 0,

			Hits = { 4, 17, 30, 43, 56, 69, 84 },


			Reset = { Frame = 93, Frames = 3 },

			Anger = { Bar = "Anger", Fill = "FillA", From = "Min" },
			Calm = { Bar = "Calm", Fill = "FillC", From = "Min" },

			Bounce = {
				Stiffness = 250,
				Damping = 12,
				Kick = 2.2,
				Pop = 5,
				CamKick = 7.5, 
			},
			MinFill = 0.03,
		},
	},
}
