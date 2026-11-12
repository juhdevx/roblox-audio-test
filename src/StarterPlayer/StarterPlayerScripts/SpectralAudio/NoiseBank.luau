--!strict
-- Reconstructs stereo residual energy with a reusable bank of calibrated filtered noise.
local Shared = game:GetService("ReplicatedStorage").Shared.SpectralAudio
local Config = require(Shared.Config)
local Format = require(Shared.Format)

type Channel = {Player: AudioPlayer, Filter: AudioFilter, Level: number, Playing: boolean, Offset: number}
type Band = {Index: number, Frequency: number, Rms: number, Audible: boolean, Left: Channel, Right: Channel}
local GOLDEN_RATIO = 0.61803398875
local NOISE_SECONDS = 5
local NoiseBank = {}
NoiseBank.__index = NoiseBank

local function wire(parent: Instance, source: Instance, target: Instance, sourceName: string?, targetName: string?)
	local connection = Instance.new("Wire")
	connection.SourceInstance = source
	connection.TargetInstance = target
	connection.SourceName = sourceName or "Output"
	connection.TargetName = targetName or "Input"
	connection.Parent = parent
end

local function createChannel(folder: Folder, mixer: Instance, side: string, index: number,
	frequency: number, q: number): Channel
	local player = Instance.new("AudioPlayer")
	player.Name = `{side}{index}`
	player.Asset = `rbxassetid://{Config.NoiseSampleAssetId}`
	player.Looping = true
	player.Volume = 0
	player.Parent = folder
	local splitter = Instance.new("AudioChannelSplitter")
	splitter.Layout = Enum.AudioChannelLayout.Mono
	splitter.Parent = folder
	local bandpass = Instance.new("AudioFilter")
	bandpass.FilterType = Enum.AudioFilterType.Bandpass
	bandpass.Frequency = frequency
	bandpass.Q = q
	bandpass.Parent = folder
	local lowpass = Instance.new("AudioFilter")
	lowpass.FilterType = Enum.AudioFilterType.Lowpass12dB
	lowpass.Frequency = Config.NoiseLowpassHz
	lowpass.Q = math.sqrt(2) / 2
	lowpass.Parent = folder
	wire(folder, player, splitter)
	wire(folder, splitter, bandpass, "Center")
	wire(folder, bandpass, lowpass)
	wire(folder, lowpass, mixer, nil, side)
	local seed = index * 2 + (if side == "Right" then 1 else 0)
	return {Player = player, Filter = bandpass, Level = 0, Playing = false, Offset = (seed * GOLDEN_RATIO % 1) * NOISE_SECONDS}
end

local function calibratedRms(frequency: number): number
	local settings = Config.NoiseBands
	if frequency <= settings[1].Frequency then
		return settings[1].Rms * math.sqrt(frequency / settings[1].Frequency)
	end
	for index = 2, #settings do
		local left, right = settings[index - 1], settings[index]
		if frequency <= right.Frequency then
			local fraction = math.log(frequency / left.Frequency) / math.log(right.Frequency / left.Frequency)
			return left.Rms * (right.Rms / left.Rms) ^ fraction
		end
	end
	return settings[#settings].Rms
end

-- Builds the fixed routing graph once; mobile uses alternate source bands without boosting them.
function NoiseBank.new(parent: Instance, mixer: Instance, mobile: boolean)
	local folder = Instance.new("Folder")
	folder.Name = "ResidualNoise"
	folder.Parent = parent
	local bands: {Band} = {}
	for index, settings in Config.NoiseBands do
		if mobile and (index % 2 ~= 0 or #bands >= Config.MobileNoiseBands) then continue end
		table.insert(bands, {
			Index = index - 1,
			Frequency = settings.Frequency,
			Rms = settings.Rms,
			Audible = true,
			Left = createChannel(folder, mixer, "Left", index, settings.Frequency, settings.Q),
			Right = createChannel(folder, mixer, "Right", index, settings.Frequency, settings.Q),
		})
	end
	return setmetatable({Folder = folder, Bands = bands, Rate = 1, Destroyed = false}, NoiseBank)
end
export type Pool = typeof(NoiseBank.new(Instance.new("Folder"), Instance.new("AudioChannelMixer"), false))

function NoiseBank.IsReady(self: Pool): boolean
	if self.Destroyed then return false end
	for _, band in self.Bands do
		if not band.Left.Player.IsReady or not band.Right.Player.IsReady then return false end
	end
	return true
end

local function muteChannel(channel: Channel)
	channel.Player.Volume = 0
	if channel.Playing then channel.Player:Stop() end
	channel.Level = 0
	channel.Playing = false
end

function NoiseBank.Mute(self: Pool)
	if self.Destroyed then return end
	for _, band in self.Bands do
		muteChannel(band.Left)
		muteChannel(band.Right)
	end
end

local function renderChannel(channel: Channel, target: number, rms: number, dt: number)
	if not channel.Player.IsReady then
		channel.Player.Volume = 0
		channel.Level = 0
		channel.Playing = false
		return
	end
	local smoothing = if target > channel.Level then Config.NoiseAttackSeconds else Config.NoiseReleaseSeconds
	local alpha = 1 - math.exp(-dt / math.max(smoothing, 0.001))
	channel.Level += (target - channel.Level) * alpha
	channel.Player.Volume = math.clamp(channel.Level * Config.NoiseMix / math.max(rms, 0.000001), 0, 4)
	if not channel.Playing and channel.Level > 0.000001 then
		channel.Player.TimePosition = math.min(channel.Offset, math.max(0, channel.Player.TimeLength - 0.001))
		channel.Player:Play()
		channel.Playing = true
	end
end

function NoiseBank.Render(self: Pool, first: buffer, firstFrame: number, second: buffer,
	secondFrame: number, fraction: number, sourceVoices: number, spatialPan: number, dt: number, playbackRate: number?)
	if self.Destroyed then return end
	if buffer.readu32(first, 44) == 0 then self:Mute(); return end
	local rate = playbackRate or 1
	if rate ~= rate or math.abs(rate) == math.huge or rate <= 0 then rate = 1 end
	rate = math.clamp(rate, Config.PlaybackRateMin, Config.PlaybackRateMax)
	if rate ~= self.Rate then
		self.Rate = rate
		for _, band in self.Bands do
			local frequency = band.Frequency * rate
			band.Audible = frequency >= 20 and frequency <= Config.NoiseLowpassHz
			local filtered = math.clamp(frequency, 20, Config.NoiseLowpassHz)
			band.Left.Filter.Frequency = filtered; band.Right.Filter.Frequency = filtered
			-- The white source stays at native speed; use the measured filter response at the shifted center.
			band.Rms = calibratedRms(filtered)
		end
	end
	local blend = math.clamp(fraction, 0, 1)
	local pan = math.clamp(spatialPan, -1, 1)
	local leftBalance = math.sqrt(1 - math.max(pan, 0))
	local rightBalance = math.sqrt(1 + math.min(pan, 0))
	local secondVoices = buffer.readu16(second, 16)
	local elapsed = math.clamp(dt, 0, 0.25)
	for _, band in self.Bands do
		local left0, right0 = Format.ReadNoise(first, firstFrame, band.Index, sourceVoices)
		local left1, right1 = Format.ReadNoise(second, secondFrame, band.Index, secondVoices)
		local weight = if band.Audible then 1 else 0
		renderChannel(band.Left, (left0 + (left1 - left0) * blend) * leftBalance * weight, band.Rms, elapsed)
		renderChannel(band.Right, (right0 + (right1 - right0) * blend) * rightBalance * weight, band.Rms, elapsed)
	end
end

function NoiseBank.Destroy(self: Pool)
	if self.Destroyed then return end
	self:Mute()
	self.Destroyed = true
	self.Folder:Destroy()
	table.clear(self.Bands)
end

return NoiseBank

