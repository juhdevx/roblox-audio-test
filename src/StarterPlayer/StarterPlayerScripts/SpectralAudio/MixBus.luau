--!strict
-- Balances track loudness before gentle peak control and listener volume.
local Config = require(game:GetService("ReplicatedStorage").Shared.SpectralAudio.Config)
local Listener = require(script.Parent.Parent.Emotes.SoundVolume)

export type Settings = {
	FadeSeconds: number,
	MaxNormalization: number,
	CompressorThresholdDb: number,
	CompressorRatio: number,
	CompressorAttackSeconds: number,
	CompressorReleaseSeconds: number,
	CompressorMakeupDb: number,
	PeakThresholdDb: number,
	PeakAttackSeconds: number,
	PeakReleaseSeconds: number,
}

local MixBus = {}
MixBus.__index = MixBus

local function wire(parent: Instance, source: Instance, target: Instance)
	local connection = Instance.new("Wire")
	connection.SourceInstance = source
	connection.TargetInstance = target
	connection.Parent = parent
end

local function finite(value: number, fallback: number): number
	return if value == value and math.abs(value) < math.huge then value else fallback
end

-- Input is a stereo stream; this bus deliberately has no emitter, echo or reverb.
function MixBus.new(parent: Instance, input: Instance, settings: Settings)
	local folder = Instance.new("Folder")
	folder.Name = "DirectMix"
	folder.Parent = parent
	local normalization = Instance.new("AudioFader")
	normalization.Name = "TrackNormalization"
	normalization.Volume = 1
	normalization.Parent = folder
	local equalizer = Instance.new("AudioEqualizer")
	equalizer.Name = "Tone"
	equalizer.LowGain = 0
	equalizer.MidGain = 0
	equalizer.HighGain = Config.HighShelfDb
	equalizer.Parent = folder
	local compressor = Instance.new("AudioCompressor")
	compressor.Name = "GentleDynamics"
	compressor.Threshold = math.clamp(settings.CompressorThresholdDb, -60, 0)
	compressor.Ratio = math.clamp(settings.CompressorRatio, 1, 50)
	compressor.Attack = math.clamp(settings.CompressorAttackSeconds, 0.0001, 0.5)
	compressor.Release = math.clamp(settings.CompressorReleaseSeconds, 0.01, 5)
	compressor.MakeupGain = math.clamp(settings.CompressorMakeupDb, -30, 30)
	compressor.Parent = folder
	local peakGuard = Instance.new("AudioCompressor")
	peakGuard.Name = "PeakGuard"
	peakGuard.Threshold = math.clamp(settings.PeakThresholdDb, -60, 0)
	peakGuard.Ratio = 50
	peakGuard.Attack = math.clamp(settings.PeakAttackSeconds, 0.0001, 0.5)
	peakGuard.Release = math.clamp(settings.PeakReleaseSeconds, 0.01, 5)
	peakGuard.MakeupGain = 0
	peakGuard.Parent = folder
	local master = Instance.new("AudioFader")
	master.Name = "ListenerVolume"
	master.Volume = 0
	master.Parent = folder
	local analyzer = Instance.new("AudioAnalyzer")
	analyzer.Name = "OutputMeter"
	analyzer.Parent = folder
	local output = Instance.new("AudioDeviceOutput")
	output.Parent = folder
	wire(folder, input, normalization)
	wire(folder, normalization, equalizer)
	wire(folder, equalizer, compressor)
	wire(folder, compressor, peakGuard)
	wire(folder, peakGuard, master)
	wire(folder, master, output)
	wire(folder, master, analyzer)
	return setmetatable({
		Folder = folder,
		Normalization = normalization,
		Equalizer = equalizer,
		Compressor = compressor,
		PeakGuard = peakGuard,
		Master = master,
		Analyzer = analyzer,
		FadeSeconds = math.max(settings.FadeSeconds, 0.001),
		MaxNormalization = math.clamp(settings.MaxNormalization, 1, 10),
		NormalizationGain = 1,
		OutputGain = 0,
		Bypassed = false,
		Destroyed = false,
	}, MixBus)
end
export type Bus = typeof(MixBus.new(Instance.new("Folder"), Instance.new("AudioChannelMixer"), {} :: Settings))

-- A fixed track gain preserves quiet passages; listener attenuation stays after dynamics.
function MixBus.Update(self: Bus, gain: number, normalization: number, hybrid: boolean, dt: number)
	if self.Destroyed then return end
	local elapsed = math.clamp(finite(dt, 0), 0, 0.25)
	local alpha = 1 - math.exp(-elapsed / self.FadeSeconds)
	local target = math.clamp(finite(gain, 0) * Config.MasterVolume * Listener.GetMediaVolume(), 0, 1)
	local trim = if self.Bypassed then 1 else math.clamp(finite(normalization, 1), 0.5, self.MaxNormalization)
	self.OutputGain += (target - self.OutputGain) * alpha
	self.NormalizationGain += (trim - self.NormalizationGain) * alpha
	self.Master.Volume = self.OutputGain
	self.Normalization.Volume = self.NormalizationGain
	local dialogue = Listener.ClearDialogue()
	local toneAlpha = 1 - math.exp(-elapsed / 0.08)
	local low = if dialogue then -4 else 0
	local mid = if dialogue then 2 else 0
	local high = (if hybrid then Config.HybridHighShelfDb else Config.HighShelfDb) - (if dialogue then 1 else 0)
	self.Equalizer.LowGain += (low - self.Equalizer.LowGain) * toneAlpha
	self.Equalizer.MidGain += (mid - self.Equalizer.MidGain) * toneAlpha
	self.Equalizer.HighGain += (high - self.Equalizer.HighGain) * toneAlpha
end

-- Allows a same-position comparison without rebuilding the oscillator graph.
function MixBus.SetBypass(self: Bus, enabled: boolean)
	if self.Destroyed then return end
	self.Bypassed = enabled
	self.Equalizer.Bypass = enabled
	self.Compressor.Bypass = enabled
	self.PeakGuard.Bypass = enabled
	if enabled then
		self.NormalizationGain = 1
		self.Normalization.Volume = 1
	end
end

function MixBus.Mute(self: Bus)
	if self.Destroyed then return end
	self.OutputGain = 0
	self.NormalizationGain = 1
	self.Master.Volume = 0
	self.Normalization.Volume = 1
end

function MixBus.Destroy(self: Bus)
	if self.Destroyed then return end
	self:Mute()
	self.Destroyed = true
	self.Folder:Destroy()
end

return MixBus

