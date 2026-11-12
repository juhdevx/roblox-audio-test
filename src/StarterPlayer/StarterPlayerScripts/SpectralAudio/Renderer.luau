--!strict
-- Reconstructs tracked partials with pooled oscillators and a dry listener mix.
local SoundService = game:GetService("SoundService")
local Shared = game:GetService("ReplicatedStorage").Shared.SpectralAudio
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local NoiseBank = require(script.Parent.NoiseBank)
local MixBus = require(script.Parent.MixBus)
local PhaseTracking = require(script.Parent.PhaseTracking)
local VoiceSelection = require(script.Parent.VoiceSelection)
type Voice = {Player: AudioPlayer, Left: AudioFader, Right: AudioFader, Playing: boolean, Level: number, Pan: number,
	Schedule: number?, BirthFrame: number?, LastHz: number?, ReadyLost: boolean?}
local Renderer = {}
Renderer.__index = Renderer
local function wire(parent: Instance, source: Instance, target: Instance, sourceName: string?, targetName: string?)
	local item = Instance.new("Wire")
	item.SourceInstance = source; item.TargetInstance = target
	item.SourceName = sourceName or "Output"; item.TargetName = targetName or "Input"; item.Parent = parent
end
local function stopVoice(voice: Voice)
	if voice.Schedule then voice.Player:Cancel(voice.Schedule); voice.Schedule = nil end
	voice.Player.Volume = 0; voice.Player:Stop(); voice.Level = 0; voice.Playing = false
	voice.Pan = 0; voice.BirthFrame = nil; voice.LastHz = nil
end
function Renderer.new(budget: number, mobile: boolean?)
	local folder = Instance.new("Folder"); folder.Name = "SpectralEmoteAudio"; folder.Parent = SoundService
	local mixer = Instance.new("AudioChannelMixer"); mixer.Layout = Enum.AudioChannelLayout.Stereo; mixer.Parent = folder
	local mix = MixBus.new(folder, mixer, Config.Mix)
	local voices: {Voice} = {}
	for _ = 1, budget do
		local player = Instance.new("AudioPlayer")
		player.Asset = `rbxassetid://{Config.SampleAssetId}`; player.Looping = true
		player.Volume = 0; player.Parent = folder
		local left = Instance.new("AudioFader"); left.Volume = 0; left.Parent = folder
		local right = Instance.new("AudioFader"); right.Volume = 0; right.Parent = folder
		local splitter = Instance.new("AudioChannelSplitter"); splitter.Layout = Enum.AudioChannelLayout.Mono; splitter.Parent = folder
		wire(folder, player, splitter); wire(folder, splitter, left, "Center"); wire(folder, splitter, right, "Center")
		wire(folder, left, mixer, nil, "Left"); wire(folder, right, mixer, nil, "Right")
		table.insert(voices, {Player = player, Left = left, Right = right, Playing = false, Level = 0, Pan = 0})
	end
	local noise = NoiseBank.new(folder, mixer, mobile == true)
	return setmetatable({Folder = folder, Voices = voices, Master = mix.Master, Analyzer = mix.Analyzer,
		Mix = mix, Noise = noise, Equalizer = mix.Equalizer, PhaseStarts = 0, LastFrame = -1,
		Active = false, Destroyed = false, PhaseCorrectedFrames = 0, UnavailableVoiceFrames = 0, RecoveredVoices = 0,
		LastMs = 0, MaxMs = 0, Rendered = 0, AverageMs = 0,
		VoiceLimit = budget, SlowSeconds = 0, StableSeconds = 0,
		Selection = VoiceSelection.new(Config.Selection), SelectionSwitches = 0, SelectionScans = 0}, Renderer)
end
export type Pool = typeof(Renderer.new(0))
function Renderer.IsReady(self: Pool): boolean
	if self.Destroyed then return false end
	for _, voice in self.Voices do if not voice.Player.IsReady then return false end end
	return true
end
function Renderer.Mute(self: Pool)
	if self.Destroyed then return end
	self.Mix:Mute()
	self.LastFrame = -1
	self.Selection:Reset()
	if not self.Active then return end
	self.Noise:Mute()
	for _, voice in self.Voices do
		stopVoice(voice); voice.Pan = 0; voice.BirthFrame = nil
	end
	self.Active = false
end
function Renderer.Render(self: Pool, first: buffer, firstFrame: number, second: buffer,
	secondFrame: number, fraction: number, count: number, gain: number, spatialPan: number, dt: number,
	mixGain: number?, playbackRate: number?)
	if self.Destroyed then return end
	local start = os.clock()
	local absoluteFrame = buffer.readu32(first, 24) + firstFrame
	if absoluteFrame < self.LastFrame then self:Mute() end
	self.LastFrame = absoluteFrame
	self.Active = true
	local sourceVoices = buffer.readu16(first, 16)
	local hybrid = buffer.readu32(first, 40) == 3
	self.Mix:Update(gain, mixGain or 1, hybrid, dt)
	local startLead = if hybrid then Config.PhaseStartLead else 0
	local mixerStart = if hybrid then SoundService:GetMixerTime() + startLead else nil
	local fps = buffer.readu16(first, 18)
	local rate = PhaseTracking.SanitizeRate(playbackRate, Config.PlaybackRateMin, Config.PlaybackRateMax)
	local activeCount = math.clamp(math.floor(math.min(count, self.VoiceLimit, #self.Voices)), 0, sourceVoices)
	if hybrid then
		if self.Selection:Update(first, firstFrame, second, secondFrame, fraction, sourceVoices,
			activeCount, fps, absoluteFrame, rate) then
			for _, voice in self.Voices do stopVoice(voice) end
		end
		self.SelectionSwitches = self.Selection.Swaps; self.SelectionScans = self.Selection.Scans
	elseif self.Selection.SourceCount > 0 then
		self.Selection:Reset()
		for _, voice in self.Voices do stopVoice(voice) end
	end
	local corrected = false
	local panAlpha = 1 - math.exp(-dt / Config.PanSeconds)
	for index, voice in self.Voices do
		-- An engine unload must clear our playback state so the ready asset can start again.
		if not voice.Player.IsReady then
			self.UnavailableVoiceFrames += 1
			if voice.Playing then
				voice.ReadyLost = true
				stopVoice(voice)
			end
			voice.BirthFrame = nil
			voice.LastHz = nil
			continue
		elseif voice.ReadyLost then
			voice.ReadyLost = nil
			self.RecoveredVoices += 1
		end
		if index > activeCount then
			if voice.Playing then stopVoice(voice) end
			continue
		end
		local slot, gate, restart = index - 1, 1, false
		if hybrid then
			if self.Selection.Adaptive then slot, gate, restart = self.Selection:Get(index, fraction) end
		else slot = math.floor((index - 1) * sourceVoices / math.max(1, count)) end
		if restart then stopVoice(voice) end
		local hz0, amp0, pan0, phase0 = Format.Read(first, firstFrame, slot, sourceVoices)
		local hz1, amp1, pan1, phase1 = Format.Read(second, secondFrame, slot, sourceVoices)
		if hybrid and amp0 == 0 and amp1 == 0 then
			if voice.Playing then stopVoice(voice) end
			voice.BirthFrame = nil; continue
		end
		if hybrid and amp0 == 0 and amp1 > 0 then
			local born = buffer.readu32(second, 24) + secondFrame
			if voice.BirthFrame ~= born and voice.Playing then stopVoice(voice) end
			voice.BirthFrame = born
		end
		local amplitude = amp0 + (amp1 - amp0) * fraction
		local hz = if hz0 > 0 and hz1 > 0 then hz0 * (hz1 / hz0) ^ fraction else math.max(hz0, hz1)
		local phaseCorrection = 0
		if hybrid then
			hz, phaseCorrection = PhaseTracking.InterpolateHz(hz0, hz1, phase0, phase1, fps, fraction,
				amp0, amp1, pan0, pan1, Config.PhaseSlopeEnabled, Config.MaxPhaseCorrectionRatio, Config.PitchStepRatio)
			if math.abs(phaseCorrection) > 0.001 then corrected = true end
		end
		-- Unrelated partials must cross silence rather than sweep through audible pitches.
		local discontinuous = hz0 > 0 and hz1 > 0
			and math.max(hz0, hz1) / math.min(hz0, hz1) > Config.PitchStepRatio and math.abs(hz1 - hz0) > 18
		if discontinuous then
			phaseCorrection = 0
			if fraction < 0.5 then hz = hz0; amplitude = amp0 * (1 - fraction * 2)
			else hz = hz1; amplitude = amp1 * (fraction * 2 - 1) end
		end
		local physicalHz = hz * rate
		local audible = physicalHz >= Config.OutputMinHz and physicalHz <= Config.OutputMaxHz
		if not audible then amplitude = 0 end
		local pan = math.clamp(pan0 + (pan1 - pan0) * fraction + spatialPan, -1, 1)
		local attack = if hybrid then Config.HybridAttackSeconds else Config.AttackSeconds
		local release = if hybrid then Config.HybridReleaseSeconds else Config.ReleaseSeconds
		local smoothing = if amplitude > voice.Level then attack else release
		local alpha = 1 - math.exp(-dt / smoothing)
		voice.Level += (amplitude - voice.Level) * alpha
		voice.Pan += (pan - voice.Pan) * panAlpha
		if voice.Level < 0.00001 then
			voice.Player.Volume = 0
			if hybrid and voice.Playing then stopVoice(voice) end
			continue
		end
		-- Fade an existing partial at its last valid pitch instead of piling out-of-range tones at the carrier limit.
		if not audible then
			if not voice.Playing then continue end
			physicalHz = voice.LastHz or Config.BaseFrequency
		end
		voice.LastHz = physicalHz
		voice.Player.PlaybackSpeed = physicalHz / Config.BaseFrequency
		voice.Player.Volume = math.clamp(voice.Level * Config.SampleNormalization * gate, 0, 4)
		local angle = (voice.Pan + 1) * math.pi / 4
		voice.Left.Volume = math.cos(angle); voice.Right.Volume = math.sin(angle)
		if not voice.Playing and voice.Player.IsReady and gate > 0 then
			local cycles = (index * 0.61803398875) % 1
			if hybrid then
				if discontinuous then
					cycles = if fraction < 0.5 then phase0 + hz0 * fraction / fps
						else phase1 - hz1 * (1 - fraction) / fps
				else
					cycles = PhaseTracking.BirthCycles(hz0, hz1, phase0, phase1, fps, fraction, amp0, amp1, phaseCorrection)
				end
				cycles = (cycles + physicalHz * startLead - Config.SamplePhaseCycles) % 1
				self.PhaseStarts += 1
			end
			voice.Player.TimePosition = cycles / Config.BaseFrequency
			if mixerStart then voice.Schedule = voice.Player:Play(mixerStart) else voice.Player:Play() end
			voice.Playing = true
		end
	end
	self.Noise:Render(first, firstFrame, second, secondFrame, fraction, sourceVoices, spatialPan, dt, rate)
	if corrected then self.PhaseCorrectedFrames += 1 end
	self.Rendered += 1
	self.LastMs = (os.clock() - start) * 1000; self.MaxMs = math.max(self.MaxMs, self.LastMs)
	self.AverageMs += (self.LastMs - self.AverageMs) * (1 - math.exp(-dt))
	if self.AverageMs > Config.FrameBudgetMs then
		self.SlowSeconds += dt; self.StableSeconds = 0
		if self.SlowSeconds > 2 then self.VoiceLimit = math.max(32, self.VoiceLimit - 8); self.SlowSeconds = 0 end
	else
		self.SlowSeconds = 0
		if self.AverageMs < Config.FrameBudgetMs * 0.5 then self.StableSeconds += dt else self.StableSeconds = 0 end
		if self.StableSeconds > 10 then self.VoiceLimit = math.min(#self.Voices, self.VoiceLimit + 8); self.StableSeconds = 0 end
	end
end
function Renderer.Destroy(self: Pool)
	if self.Destroyed then return end
	self:Mute(); self.Selection:Destroy(); self.Noise:Destroy(); self.Mix:Destroy(); self.Folder:Destroy(); table.clear(self.Voices)
	self.Destroyed = true
end
return Renderer


