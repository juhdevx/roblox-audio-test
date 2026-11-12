--!strict
-- Declares server effects for Bang Bang Bang.
return {
    Name = "Bang Bang Bang",
	{
		Type = "DummySpawner",
		Action = "Start",
		Params = {
			DummyName = "EffectDummy",
			AnimationId = "rbxassetid://87657315869825",
			Offset = CFrame.new(0, 0, 0),
			Delay = 0,
			Duration = 14.27,
			Looped = false
		}
	},
	{
		Type = "AttachHands",
		Action = "Start",
		Params = {}
	},
	{
		Type = "LyricText",
		Action = "Start",
		Params = {
			Scope = "All",

			Bpm = 120,
			Offset = 0,

			LoopStartTime = 14.27,
			LoopEndTime = 28.87,

			Color = Color3.fromRGB(255, 255, 255),
			GlowColor = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.GothamBlack,

			LetterSize = 0.5,
			Distance = 2.5,
			Height = 3.5,

			LetterDelay = 0.055,
			FallDelay = 0.05,
			Hold = 1.2,
			GlowThickness = 3,

			Lines = {
				{ Time = 0.00, Text = "MY RIVAL, MY IDOL" },
				{ Time = 02.11, Text = "YOU GOT ME SUICIDAL" },
				{ Time = 4.00, Text = "MY LOVE, YOUR RAGE" },
				{ Time = 5.67, Text = "OUR DYING CLAIM TO FAME" },

				{ Time = 7.43, Text = "OUR BATTLE LEGENDARY" },
				{ Time = 9.28, Text = "OUR FICKLE FRATERNIZING" },
				{ Time = 11.16, Text = "A WAR INSIDE MY HEART" },
				{ Time = 12.87, Text = "UNTIL [?] DO US PART" },

				{ Time = 14.44, Text = "BANG, BANG, BANG, BANG, BANG",
					Effect = {
						RevealTime = 0.45,
						LetterDelay = 0.085
				} },
				{ Time = 16.80, Text = "TILL I TAKE YOU" },
				{ Time = 18.06, Text = "DOWN, DOWN, DOWN, DOWN" ,
					Effect = {
						RevealTime = 0.45,
						LetterDelay = 0.085
					} },
				{ Time = 19.99, Text = "I WANT YOU IN THE GROUND" },

				{ Time = 21.74, Text = "BANG, BANG, BANG, BANG, BANG",
					Effect = {
					RevealTime = 0.45,
					LetterDelay = 0.085
				} },

				{ 
					Time = 23.95, 
					Text = "TILL I TAKE YOU",
					Effect = {
						RevealTime = 0.45,
						LetterDelay = 0.055
					}
				},

				{ 
					Time = 25.30, 
					Text = "DOWN, DOWN, DOWN, DOWN",
					Effect = {
						RevealTime = 0.55,
						LetterDelay = 0.085
					}
				},

				{ 
					Time = 26.90, 
					Text = "I WANT YOU IN THE GROUND",
					Effect = {
						RevealTime = 0.65,
						LetterDelay = 0.065,
						Hold = 1.2
					}
				},
			},
		}
	}
}
