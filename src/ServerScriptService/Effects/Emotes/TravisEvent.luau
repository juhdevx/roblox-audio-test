--!strict
-- Declares server effects for TravisEvent.
--[[
	================================================================
	SHOW CONFIG — ASTROWORLD / TRAVIS SCOTT
	================================================================
	v4 — mudanças desta versão:
	  ✅ Cores mais vibrantes em SICKO, FIRE, CORE, RIFT
	  ✅ Novos cues: Electricity e EnergyOrbit
	  ✅ Auras mais intensas nos picos

	Pattern de bateria:
	  K = kick   S = snare   h = hat   X = acento   . = silêncio
	================================================================
--]]

local function T(minutes, seconds) return minutes * 60 + (seconds or 0) end
local function Rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local WHITE    = Rgb(255, 255, 255)
local OFFWHITE = Rgb(240, 235, 225)
local WARM     = Rgb(255, 200, 140)
local AMBER    = Rgb(255, 160, 70)
local VIOLET   = Rgb(150, 100, 220)
local PURPLE   = Rgb(170, 70, 220)
local ORANGE   = Rgb(240, 120, 60)
local RED      = Rgb(200, 60, 40)
local CYAN     = Rgb(90, 200, 220)
local PINK     = Rgb(220, 80, 170)
local BLUE     = Rgb(80, 130, 210)
local GOLD     = Rgb(240, 200, 110)
local DARKRED  = Rgb(100, 20, 20)
local MAGENTA  = Rgb(200, 0, 160)

local function MakeLook(o)
	return {
		Lighting = {
			ClockTime            = o.Clock or 14,
			Brightness           = o.Brightness or 1.5,
			Ambient              = o.Ambient or Rgb(70, 70, 70),
			OutdoorAmbient       = o.Outdoor or o.Ambient or Rgb(70, 70, 70),
			ColorShift_Top       = o.Tint or WHITE,
			ExposureCompensation = o.Exposure or 0,
			FogColor             = o.Fog or o.Ambient or Rgb(70, 70, 70),
			FogEnd               = o.FogEnd or 2000,
		},
		Atmosphere = {
			Density = o.Density or 0.3,
			Color   = o.Tint or WHITE,
			Decay   = o.Decay or o.Ambient or Rgb(100, 100, 100),
			Haze    = o.Haze or 1,
			Glare   = o.Glare or 0.4,
		},
		ColorCorrection = {
			TintColor  = o.Grade or WHITE,
			Saturation = o.Saturation or 0.1,
			Contrast   = o.Contrast or 0.15,
			Brightness = o.Bright or 0,
		},
		Bloom   = { Intensity = o.Bloom or 0.9, Size = 24, Threshold = o.Threshold or 1.0 },
		Blur    = o.Blur and { Size = o.Blur } or nil,
		SunRays = o.SunRays and { Intensity = o.SunRays, Spread = 1 } or nil,
		Sky     = o.Sky,
	}
end

local LOOKS = {
	DARK = MakeLook({
		Clock = 22, Brightness = 0.6, Ambient = Rgb(30, 28, 40), Tint = Rgb(45, 40, 60),
		Fog = Rgb(15, 12, 25), FogEnd = 300, Density = 0.5,
		Grade = Rgb(150, 140, 160), Bloom = 0.5, Saturation = -0.15, Contrast = 0.2,
	}),

	-- ✅ Vibrante
	SICKO = MakeLook({
		Clock = 21, Brightness = 1.2, Ambient = Rgb(105, 45, 140), Tint = Rgb(190, 85, 225),
		Fog = Rgb(55, 20, 80), FogEnd = 900, Density = 0.35,
		Grade = Rgb(245, 215, 255), Bloom = 1.5, Saturation = 0.4, Contrast = 0.32, SunRays = 0.28,
	}),

	EQUAL = MakeLook({
		Clock = 22, Brightness = 1.1, Ambient = Rgb(40, 60, 120), Tint = Rgb(90, 160, 220),
		Fog = Rgb(30, 50, 100), FogEnd = 1000, Density = 0.3,
		Grade = Rgb(200, 220, 240), Bloom = 1.0, Saturation = 0.2, Contrast = 0.2,
	}),

	-- ✅ Mais quente e intenso
	FIRE = MakeLook({
		Clock = 17.5, Brightness = 1.5, Ambient = Rgb(190, 85, 55), Tint = Rgb(255, 140, 75),
		Fog = Rgb(150, 55, 35), FogEnd = 500, Density = 0.5, Haze = 2.6,
		Grade = Rgb(255, 215, 185), Bloom = 1.7, Saturation = 0.38, Contrast = 0.32, SunRays = 0.62,
	}),

	STAR = MakeLook({
		Clock = 3, Brightness = 1.0, Ambient = Rgb(35, 55, 95), Tint = Rgb(70, 130, 190),
		Fog = Rgb(20, 30, 55), FogEnd = 700,
		Grade = Rgb(190, 210, 235), Bloom = 0.9, Saturation = 0.15, Contrast = 0.25, SunRays = 0.35,
	}),

	NEON = MakeLook({
		Clock = 22, Brightness = 0.8, Ambient = Rgb(40, 25, 60), Outdoor = Rgb(25, 18, 40),
		Tint = Rgb(200, 100, 200), Fog = Rgb(15, 8, 25), FogEnd = 400,
		Grade = Rgb(230, 210, 240), Bloom = 1.3, Threshold = 0.75, Saturation = 0.3, Contrast = 0.3,
	}),

	OCEAN = MakeLook({
		Clock = 12, Brightness = 1.2, Ambient = Rgb(40, 100, 140), Tint = Rgb(70, 160, 200),
		Fog = Rgb(20, 70, 110), FogEnd = 180, Density = 0.55, Haze = 2.5,
		Grade = Rgb(180, 215, 235), Bloom = 0.9, Blur = 4, Saturation = 0.2,
	}),

	DEEP = MakeLook({
		Clock = 12, Brightness = 0.9, Ambient = Rgb(25, 60, 100), Tint = Rgb(50, 120, 180),
		Fog = Rgb(10, 35, 70), FogEnd = 100, Density = 0.65, Haze = 3,
		Grade = Rgb(160, 200, 230), Bloom = 0.9, Blur = 6, Saturation = 0.15,
	}),

	GRID = MakeLook({
		Clock = 23, Brightness = 1.1, Ambient = Rgb(70, 40, 110), Tint = Rgb(180, 90, 200),
		Fog = Rgb(35, 20, 60), FogEnd = 500,
		Grade = Rgb(230, 200, 240), Bloom = 1.2, Saturation = 0.25, Contrast = 0.3,
	}),

	SKY = MakeLook({
		Clock = 17.5, Brightness = 2.0, Ambient = Rgb(180, 150, 140), Outdoor = Rgb(160, 140, 150),
		Tint = Rgb(230, 170, 120), Fog = Rgb(240, 200, 180), FogEnd = 5000, Density = 0.15,
		Grade = Rgb(245, 235, 220), Bloom = 1.0, Saturation = 0.2, SunRays = 0.7,
	}),

	SPACE = MakeLook({
		Clock = 2, Brightness = 0.9, Ambient = Rgb(50, 50, 95), Tint = Rgb(110, 100, 200),
		Fog = Rgb(10, 8, 25), FogEnd = 4000, Density = 0.2,
		Grade = Rgb(210, 205, 235), Bloom = 1.1, Saturation = 0.15, Contrast = 0.25, SunRays = 0.2,
	}),

	-- ✅ Mais elétrico
	CORE = MakeLook({
		Clock = 21, Brightness = 1.6, Ambient = Rgb(160, 65, 215), Tint = Rgb(230, 115, 255),
		Fog = Rgb(85, 30, 120), FogEnd = 1500,
		Grade = Rgb(255, 225, 255), Bloom = 2.0, Saturation = 0.45, Contrast = 0.38,
	}),

	-- ✅ Mais brilhante
	RIFT = MakeLook({
		Clock = 12, Brightness = 2.4, Ambient = Rgb(220, 220, 235), Tint = Rgb(250, 245, 255),
		Fog = Rgb(240, 240, 250), FogEnd = 3000, Density = 0.3, Haze = 0.85, Glare = 1.3,
		Grade = Rgb(255, 255, 255), Bloom = 1.8, Threshold = 0.8, Saturation = -0.05, Contrast = 0.25,
	}),
}

local function Scene(time, name, look, bpm, pattern, energy, extra)
	local scene = {
		Time    = time,
		Name    = name,
		Look    = look,
		Bpm     = bpm,
		Pattern = pattern,
		Energy  = energy or 1,
		Fade    = 2.2,
		CamBob  = 1,
	}
	for key, value in pairs(extra or {}) do scene[key] = value end
	return scene
end

local function C(time, action, props)
	local cue = { Time = time, Action = action }
	for key, value in pairs(props or {}) do cue[key] = value end
	return cue
end

return {
    Name = "TravisEvent",
	{
		Type   = "EventShow",
		Action = "Start",
		Params = {
			Scope          = "All",
			NearRadius     = 300,
			ExclusiveAudio = true,

			ShowLength     = 560,
			Fit            = true,
			Lookahead      = 0.05,
			Debug          = false,

			BaseScale      = 3.6,
			Grow           = { Time = T(0, 3), Duration = 1.5 },
			CameraZoom     = true,

			FadeOut        = 3.0,

			Scenes = {
				Scene(T(0, 0),  "TRAVIS AJOELHADO (ABERTURA)",     LOOKS.DARK,  72,  "K...S...", 0.3,  { Rumble = 0.02,  Fade = 3.0, Accent = VIOLET }),
				Scene(T(0, 3),  "SICKO MODE - IMPACTO",            LOOKS.SICKO, 155, "K.h.S.h.", 1.0,  { Rumble = 0.025, AccentBars = 4, Fade = 1.2, Accent = VIOLET }),
				Scene(T(0, 50), "SICKO MODE - EQUALIZADOR",        LOOKS.EQUAL, 155, "K.hhS.h.", 1.2,  { Rumble = 0.02,  AccentBars = 4, Accent = CYAN,  CamBob = 2 }),
				Scene(T(1, 40), "CEU VERMELHO / PARQUE EM CHAMAS", LOOKS.FIRE,  155, "K.h.S.hh", 1.4,  { Rumble = 0.04,  AccentBars = 2, Accent = ORANGE }),
				Scene(T(2, 15), "STARGAZING (T-3500)",             LOOKS.STAR,  74,  "K.h.S.h.", 0.95, { Rumble = 0.02,  AccentBars = 4, Fade = 2.5, Accent = BLUE }),
				Scene(T(3, 45), "GOOSEBUMPS (NEON)",               LOOKS.NEON,  130, "K.hhS.h.", 1.5,  { Rumble = 0.035, AccentBars = 4, Fade = 1.8, Accent = PINK }),
				Scene(T(4, 25), "INUNDACAO",                       LOOKS.OCEAN, 130, "K...S...", 1.05, { Rumble = 0.03,  Fade = 2.5, Accent = CYAN }),
				Scene(T(4, 57), "HIGHEST IN THE ROOM (SUBMERSO)",  LOOKS.DEEP,  78,  "K...S...", 0.75, { Rumble = 0.015, AccentBars = 4, Fade = 3.0, Accent = CYAN }),
				Scene(T(6, 6),  "SICKO MODE - GRADE",              LOOKS.GRID,  155, "K.h.S.hh", 1.4,  { Rumble = 0.035, AccentBars = 4, Fade = 1.8, Accent = PINK, CamBob = 2 }),
				Scene(T(7, 5),  "THE SCOTTS - CEU",                LOOKS.SKY,   80,  "K.h.S.h.", 1.05, { Rumble = 0.015, AccentBars = 4, Fade = 2.5, Accent = ORANGE }),
				Scene(T(8, 7),  "ASTROWORLD / ESPACO",             LOOKS.SPACE, 80,  "K.h.S.h.", 1.15, { Rumble = 0.02,  AccentBars = 4, Fade = 2.5, Accent = VIOLET }),
				Scene(T(8, 30), "NUCLEO EXPLODE",                  LOOKS.CORE,  80,  "K.hhS.hh", 1.6,  { Rumble = 0.055, AccentBars = 2, Fade = 1.5, Accent = PURPLE }),
				Scene(T(8, 42), "RIFT",                            LOOKS.RIFT,  74,  "K...S...", 0.7,  { Rumble = 0.025, Fade = 1.2, Accent = WHITE }),
			},

			Gravity = {
				{ Time = T(0, 0),  Value = 220   },
				{ Time = T(0, 50), Value = 196.2 },
				{ Time = T(0, 55), Value = 60    },
				{ Time = T(1, 40), Value = 196.2 },
				{ Time = T(4, 30), Value = 40    },
				{ Time = T(6, 0),  Value = 196.2 },
				{ Time = T(7, 10), Value = 30    },
				{ Time = T(8, 50), Value = 196.2 },
			},

			Cues = {

				-- ── ABERTURA (0:00) ─────────────────────
				C(T(0, 0),   "Letterbox",   { Amount = 0.12, Duration = 1.5 }),
				C(T(0, 0),   "CameraFOV",   { Value = 58 }),
				C(T(0, 0),   "Aura",        { Color = VIOLET, Base = 1.2, Peak = 3 }),
				C(T(0, 0),   "Spotlights",  { Color = VIOLET, Count = 3, Duration = 3 }),
				C(T(0, 0),   "Embers",      { Style = "Stars", Duration = 3 }),
				C(T(0, 1.5), "SpawnPart",   { Kind = "Meteor", Color = PURPLE, Radius = 50, Duration = 1.5 }),

				-- ── IMPACTO (0:03) ──────────────────────
				C(T(0, 3), "Letterbox",  { Amount = 0, Duration = 0.5 }),
				C(T(0, 3), "CameraFOV",  { Value = 72 }),
				C(T(0, 3), "Aura",       { Color = PURPLE, Base = 2.5, Peak = 8 }),
				C(T(0, 3), "Smoke",      { Color = Rgb(70, 50, 85), Density = 1.2, Duration = 8 }),
				C(T(0, 4), "Lasers",     { Mode = "Fan", Count = 8, Color = PURPLE, Color2 = VIOLET, Duration = 44, Speed = 0.5 }),
				C(T(0, 4), "Spotlights", { Color = VIOLET, Count = 5, Duration = 44 }),
				C(T(0, 4), "Embers",     { Style = "Embers", Duration = 44, Density = 0.7 }),
				C(T(0, 5), "EnergyOrbit", { Count = 3, Radius = 5, Color = VIOLET, Duration = 40 }),

				-- ── EQUALIZADOR (0:50) ──────────────────
				C(T(0, 50), "Equalizer",  { Color = CYAN, Color2 = BLUE, Duration = 48, Radius = 30, Bars = 30 }),
				C(T(0, 50), "Bounce",     { Duration = 48, Height = 4, AccentHeight = 9 }),
				C(T(0, 50), "Aura",       { Color = CYAN, Base = 2.5, Peak = 7 }),
				C(T(0, 50), "CameraFOV",  { Value = 78 }),
				C(T(0, 50), "Teleport",   { Color = CYAN }),
				C(T(0, 51), "Lasers",     { Mode = "Cross", Count = 6, Color = CYAN, Color2 = BLUE, Duration = 46, Speed = 0.45 }),
				C(T(0, 55), "Electricity", { Color = CYAN, Duration = 20 }),
				C(T(1, 5),  "Teleport",   { Color = CYAN }),
				C(T(1, 20), "Teleport",   { Color = CYAN }),

				C(T(1, 38), "SpawnPart",  { Kind = "Explosion", Color = WARM, Radius = 100 }),

				-- ── CEU VERMELHO (1:40) ─────────────────
				C(T(1, 40), "Aura",        { Color = RED, Base = 2.5, Peak = 9 }),
				C(T(1, 40), "Embers",      { Style = "Embers", Duration = 35, Density = 1.6 }),
				C(T(1, 40), "Smoke",       { Color = Rgb(60, 40, 35), Density = 1.4, Duration = 32 }),
				C(T(1, 40), "Spotlights",  { Color = ORANGE, Count = 6, Duration = 33 }),
				C(T(1, 40), "SpawnPart",   { Kind = "Shockwave", Color = ORANGE, Radius = 80, Duration = 1.4 }),
				C(T(1, 40), "CameraTilt",  { Angle = -4 }),
				C(T(1, 40), "Letterbox",   { Amount = 0.10, Duration = 1.5 }),
				C(T(1, 55), "Glitch",      { Tint = DARKRED }),
				C(T(2, 5),  "Glitch",      { Tint = DARKRED }),
				C(T(2, 12), "CameraTilt",  { Angle = 0 }),

				-- ── STARGAZING (2:15) ───────────────────
				C(T(2, 15), "Lightning",   {}),
				C(T(2, 15), "Glitch",      { Tint = CYAN, Duration = 0.4 }),
				C(T(2, 15), "Aura",        { Color = BLUE, Base = 2.5, Peak = 9 }),
				C(T(2, 15), "CameraFOV",   { Value = 62 }),
				C(T(2, 15), "Letterbox",   { Amount = 0.14, Duration = 1 }),
				C(T(2, 16), "Lasers",      { Mode = "Fan", Count = 8, Color = CYAN, Color2 = BLUE, Duration = 85, Speed = 0.6 }),
				C(T(2, 16), "Spotlights",  { Color = BLUE, Count = 5, Duration = 85 }),
				C(T(2, 20), "SpawnPart",   { Kind = "Planets", Radius = 120, Duration = 80 }),
				C(T(2, 25), "Embers",      { Style = "Stars", Duration = 85, Density = 0.9 }),
				C(T(2, 30), "EnergyOrbit", { Count = 4, Radius = 7, Color = CYAN, Duration = 60 }),
				C(T(2, 55), "Teleport",    { Color = BLUE, Hold = 0.5 }),
				C(T(3, 25), "Glitch",      { Tint = CYAN }),
				C(T(3, 35), "Flash",       { Color = CYAN, Intensity = 0.6, Duration = 0.5 }),
				C(T(3, 35), "CameraFOV",   { Value = 80 }),

				-- ── GOOSEBUMPS (3:45) ───────────────────
				C(T(3, 44), "Letterbox",  { Amount = 0.16, Duration = 0.8 }),
				C(T(3, 45), "Flash",      { Color = PINK, Intensity = 0.9, Duration = 0.6 }),
				C(T(3, 45), "Aura",       { Color = Rgb(255, 60, 200), Base = 4, Peak = 14 }),
				C(T(3, 45), "CameraFOV",  { Value = 76 }),
				C(T(3, 45), "Lasers",     { Mode = "Fan", Count = 12, Color = PINK, Color2 = CYAN, Duration = 38, Speed = 0.7 }),
				C(T(3, 46), "Lasers",     { Mode = "Cross", Count = 8, Color = CYAN, Color2 = PINK, Duration = 37, Speed = 0.5 }),
				C(T(3, 46), "Spotlights", { Color = PINK, Count = 6, Duration = 37 }),
				C(T(3, 46), "PlayerRGB",  { Mode = "Beat", Colors = { PINK, CYAN, OFFWHITE, MAGENTA }, Duration = 37 }),
				C(T(3, 47), "Embers",     { Style = "Stars", Duration = 36 }),
				C(T(3, 47), "Electricity", { Color = PINK, Duration = 6 }),
				C(T(3, 50), "EnergyOrbit", { Count = 3, Radius = 6, Color = PINK, Duration = 15 }),
				C(T(4, 0),  "SpawnPart",  { Kind = "Shockwave", Color = PINK, Radius = 80, Duration = 1.4 }),
				C(T(4, 15), "Glitch",     { Tint = CYAN }),
				C(T(4, 20), "Flash",      { Color = OFFWHITE, Intensity = 0.8, Duration = 0.5 }),
				C(T(4, 20), "Glitch",     { Tint = WHITE }),

				-- ── INUNDACAO (4:25) ────────────────────
				C(T(4, 25), "Shake",      { Intensity = 0.8, Duration = 2.5 }),
				C(T(4, 25), "Aura",       { Color = CYAN, Base = 2.5, Peak = 8 }),
				C(T(4, 25), "CameraFOV",  { Value = 58 }),
				C(T(4, 25), "Letterbox",  { Amount = 0.16, Duration = 1 }),
				C(T(4, 25), "Embers",     { Style = "Bubbles", Duration = 30, Density = 1.2 }),
				C(T(4, 25), "Spotlights", { Color = CYAN, Count = 6, Duration = 30 }),
				C(T(4, 26), "SpawnPart",  { Kind = "Meteor", Color = AMBER, Radius = 65, Duration = 1.8 }),
				C(T(4, 31), "SpawnPart",  { Kind = "Meteor", Color = AMBER, Radius = 55, Duration = 1.8 }),
				C(T(4, 36), "SpawnPart",  { Kind = "Meteor", Color = CYAN,  Radius = 60, Duration = 1.8 }),
				C(T(4, 41), "SpawnPart",  { Kind = "Meteor", Color = CYAN,  Radius = 50, Duration = 1.8 }),
				C(T(4, 46), "SpawnPart",  { Kind = "Meteor", Color = BLUE,  Radius = 60, Duration = 1.8 }),
				C(T(4, 51), "SpawnPart",  { Kind = "Meteor", Color = BLUE,  Radius = 50, Duration = 1.8 }),

				-- ── HIGHEST IN THE ROOM (4:57) ──────────
				C(T(4, 57), "CameraFOV",  { Value = 52 }),
				C(T(4, 57), "Aura",       { Color = CYAN, Base = 2, Peak = 6 }),
				C(T(4, 57), "Embers",     { Style = "Bubbles", Duration = 68, Density = 1.4 }),
				C(T(4, 57), "Spotlights", { Color = CYAN, Count = 6, Duration = 66 }),
				C(T(4, 57), "Lasers",     { Mode = "Cross", Count = 5, Color = CYAN, Color2 = BLUE, Duration = 66, Speed = 0.18 }),
				C(T(5, 20), "Glitch",     { Tint = CYAN }),
				C(T(5, 40), "Glitch",     { Tint = BLUE }),

				-- ── SICKO MODE NA GRADE (6:06) ──────────
				C(T(6, 6),  "Flash",      { Color = PINK, Intensity = 0.9, Duration = 0.5 }),
				C(T(6, 6),  "Aura",       { Color = PINK, Base = 3, Peak = 11 }),
				C(T(6, 6),  "CameraFOV",  { Value = 72 }),
				C(T(6, 6),  "Equalizer",  { Color = PINK, Color2 = CYAN, Duration = 58, Radius = 34, Bars = 36 }),
				C(T(6, 6),  "Bounce",     { Duration = 58, Height = 4, AccentHeight = 10 }),
				C(T(6, 7),  "Lasers",     { Mode = "Cross", Count = 10, Color = PINK, Color2 = CYAN, Duration = 57, Speed = 0.6 }),
				C(T(6, 7),  "Spotlights", { Color = PINK, Count = 6, Duration = 57 }),
				C(T(6, 8),  "Electricity", { Color = PINK, Duration = 30 }),
				C(T(6, 25), "Glitch",     { Tint = PINK }),
				C(T(6, 40), "Glitch",     { Tint = CYAN }),

				-- ── A ILHA VIRA (6:55) ──────────────────
				C(T(6, 55), "Shake",      { Intensity = 1.6, Duration = 3 }),
				C(T(6, 55), "Flash",      { Color = OFFWHITE, Intensity = 1, Duration = 0.8 }),
				C(T(6, 55), "Glitch",     { Tint = WHITE, Duration = 0.5 }),
				C(T(6, 55), "CameraRoll", { Speed = 120 }),
				C(T(6, 55), "CameraFOV",  { Value = 44 }),
				C(T(6, 57), "Pulse",      { FOV = 14 }),

				-- ── THE SCOTTS (7:05) ───────────────────
				C(T(7, 5),  "CameraRoll", { Speed = 0 }),
				C(T(7, 5),  "Aura",       { Color = ORANGE, Base = 2, Peak = 8 }),
				C(T(7, 5),  "CameraFOV",  { Value = 82 }),
				C(T(7, 5),  "CameraTilt", { Angle = 4 }),
				C(T(7, 5),  "Letterbox",  { Amount = 0.14, Duration = 2 }),
				C(T(7, 5),  "SpawnPart",  { Kind = "Stars", Color = WHITE, Radius = 140, Duration = 62 }),
				C(T(7, 5),  "Embers",     { Style = "Stars", Duration = 62 }),
				C(T(7, 5),  "Spotlights", { Color = AMBER, Count = 8, Duration = 60 }),
				C(T(7, 5),  "Lasers",     { Mode = "Fan", Count = 6, Color = AMBER, Color2 = GOLD, Duration = 60, Speed = 0.35 }),
				C(T(7, 20), "Particles",  { Color = OFFWHITE, Count = 60, Speed = 40, Lifetime = 1.5, Size = 0.32 }),
				C(T(7, 40), "Particles",  { Color = AMBER, Count = 80, Speed = 38, Lifetime = 1.6, Size = 0.32 }),

				-- ── ASTROWORLD (8:07) ───────────────────
				C(T(8, 7),  "Aura",       { Color = VIOLET, Base = 2.5, Peak = 9 }),
				C(T(8, 7),  "CameraFOV",  { Value = 88 }),
				C(T(8, 7),  "CameraTilt", { Angle = 0 }),
				C(T(8, 7),  "SpawnPart",  { Kind = "Planets", Radius = 160, Duration = 23 }),
				C(T(8, 7),  "Embers",     { Style = "Stars", Duration = 23 }),
				C(T(8, 15), "Lasers",     { Mode = "Cross", Count = 6, Color = VIOLET, Color2 = BLUE, Duration = 14, Speed = 0.5 }),
				C(T(8, 18), "SpawnPart",  { Kind = "Meteor", Color = PURPLE, Radius = 75, Duration = 2 }),

				-- ── NUCLEO EXPLODE (8:30) ───────────────
				C(T(8, 30), "Shake",      { Intensity = 0.6, Duration = 10 }),
				C(T(8, 30), "Aura",       { Color = Rgb(200, 80, 255), Base = 5, Peak = 18 }),
				C(T(8, 30), "CameraFOV",  { Value = 46 }),
				C(T(8, 30), "Lasers",     { Mode = "Fan", Count = 10, Color = PURPLE, Color2 = OFFWHITE, Duration = 14, Speed = 1.1 }),
				C(T(8, 30), "Spotlights", { Color = PURPLE, Count = 8, Duration = 10 }),
				C(T(8, 31), "Electricity", { Color = PURPLE, Duration = 8 }),
				C(T(8, 32), "EnergyOrbit", { Count = 5, Radius = 9, Color = PURPLE, Duration = 10 }),
				C(T(8, 33), "Glitch",     { Tint = PURPLE }),
				C(T(8, 36), "Glitch",     { Tint = WHITE }),

				-- ── EXPLOSÃO FINAL (8:40) ───────────────
				C(T(8, 40), "SpawnPart",  { Kind = "Explosion", Color = WARM, Radius = 180 }),
				C(T(8, 40), "Shake",      { Intensity = 2, Duration = 3 }),
				C(T(8, 40), "Glitch",     { Tint = WHITE, Duration = 0.5 }),
				C(T(8, 40), "CameraFOV",  { Value = 90 }),
				C(T(8, 40), "Smoke",      { Color = Rgb(80, 60, 90), Density = 1.4, Duration = 8 }),

				-- ── RIFT (8:42) ─────────────────────────
				C(T(8, 42),   "Teleport",   { Color = WHITE, Hold = 0.6 }),
				C(T(8, 43),   "Glitch",     { Tint = WHITE, Duration = 0.15 }),
				C(T(8, 43.5), "Glitch",     { Tint = PURPLE, Duration = 0.15 }),
				C(T(8, 44),   "Pulse",      { FOV = 16 }),
				C(T(8, 44.5), "Aura",       { Color = Rgb(255, 255, 255), Base = 6, Peak = 16 }),
				C(T(8, 45),   "Lasers",     { Mode = "Fan", Count = 12, Color = OFFWHITE, Color2 = VIOLET, Duration = 20, Speed = 1.4 }),
				C(T(8, 45),   "Spotlights", { Color = OFFWHITE, Count = 10, Duration = 20 }),
				C(T(8, 45),   "Particles",  { Color = OFFWHITE, Count = 200, Speed = 80, Lifetime = 1.2, Size = 0.45 }),
				C(T(8, 48),   "Pulse",      { FOV = 18 }),

				-- ── ENCERRAMENTO (8:50+) ────────────────
				C(T(8, 50), "Teleport",   { Color = WHITE, Hold = 0.6 }),
				C(T(8, 50), "Flash",      { Color = OFFWHITE, Intensity = 0.8, Duration = 0.6 }),
				C(T(8, 50), "CameraFOV",  { Value = 70 }),
				C(T(8, 51), "Embers",     { Style = "Stars", Duration = 25 }),
				C(T(8, 52), "Aura",       { Color = OFFWHITE, Base = 3.5, Peak = 10 }),
				C(T(9, 3),  "Letterbox",  { Amount = 0.2, Duration = 1.5 }),
				C(T(9, 10), "Flash",      { Color = OFFWHITE, Intensity = 0.9, Duration = 1.6 }),
				C(T(9, 10), "Letterbox",  { Amount = 0.3, Duration = 2 }),
				C(T(9, 15), "CameraFOV",  { Value = 55 }),
			},
		},
	},
}
