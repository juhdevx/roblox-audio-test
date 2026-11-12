--!strict
-- Pools sample players with scheduled note starts, ADSR and equal-power stereo pan.
local SoundService = game:GetService("SoundService")
local Shared = game:GetService("ReplicatedStorage").Shared.AudioSequence
local Config = require(Shared.Config)
local SampleBank = require(Shared.SampleBank)
export type IAudioBackend = {
	Schedule: (any, buffer, number, number, number) -> boolean,
	Step: (any, number) -> (),
	StopAll: (any) -> (),
	SetMix: (any, number?, number?, number?) -> (),
	Destroy: (any) -> (),
}
type Voice = {
	Player: AudioPlayer, Left: AudioFader, Right: AudioFader, Instrument: number,
	RootNote: number, Gain: number, Active: boolean, Action: number?,
	Start: number, Duration: number, Attack: number, Decay: number, Sustain: number,
	Release: number, Velocity: number, Pan: number, Pitch: number, Level: number,
}
local Backend = {}
Backend.__index = Backend
local function wire(parent: Instance, source: Instance, target: Instance, sourceName: string?, targetName: string?)
	local item = Instance.new("Wire")
	item.SourceInstance = source; item.TargetInstance = target
	item.SourceName = sourceName or "Output"; item.TargetName = targetName or "Input"
	item.Parent = parent
end
local function stop(voice: Voice)
	if voice.Action then voice.Player:Cancel(voice.Action); voice.Action = nil end
	voice.Player:Stop(); voice.Left.Volume = 0; voice.Right.Volume = 0
	voice.Active = false; voice.Level = 0
end
local function heldLevel(voice: Voice, age: number): number
	if age < 0 then return 0 end
	if voice.Attack > 0 and age < voice.Attack then return age / voice.Attack end
	if voice.Decay > 0 and age < voice.Attack + voice.Decay then
		return 1 + (voice.Sustain - 1) * (age - voice.Attack) / voice.Decay
	end
	return voice.Sustain
end
function Backend.new(bank: {[number]: SampleBank.Sample}?)
	local total = 0
	for instrument, sample in bank or SampleBank do
		assert(instrument % 1 == 0 and instrument >= 0 and instrument <= 255, "Invalid instrument ID")
		assert(sample.AssetId > 0 and sample.AssetId % 1 == 0, "Sample asset ID must be configured")
		assert(sample.RootNote >= 0 and sample.RootNote <= 127, "Invalid sample root note")
		assert(sample.Voices >= 1 and sample.Voices % 1 == 0, "Invalid sample voice count")
		assert(sample.Volume >= 0 and sample.Volume <= 1, "Invalid sample volume")
		total += sample.Voices
		assert(total <= Config.MaxVoices, "SampleBank exceeds voice budget")
	end
	local folder = Instance.new("Folder")
	folder.Name = "AudioSequenceOutput"; folder.Parent = SoundService
	local output = Instance.new("AudioDeviceOutput"); output.Parent = folder
	local mixer = Instance.new("AudioChannelMixer")
	mixer.Layout = Enum.AudioChannelLayout.Stereo; mixer.Parent = folder
	wire(folder, mixer, output)
	local voices: {Voice} = {}
	local ids = {}
	for instrument in bank or SampleBank do table.insert(ids, instrument) end
	table.sort(ids)
	for _, instrument in ids do
		local sample = (bank or SampleBank)[instrument]
		for _ = 1, sample.Voices do
			local player = Instance.new("AudioPlayer")
			player.Asset = `rbxassetid://{sample.AssetId}`
			player.Looping = sample.Loop; player.Volume = 0; player.Parent = folder
			local splitter = Instance.new("AudioChannelSplitter")
			splitter.Layout = Enum.AudioChannelLayout.Mono; splitter.Parent = folder
			local left = Instance.new("AudioFader"); left.Volume = 0; left.Parent = folder
			local right = Instance.new("AudioFader"); right.Volume = 0; right.Parent = folder
			wire(folder, player, splitter)
			wire(folder, splitter, left, "Center")
			wire(folder, splitter, right, "Center")
			wire(folder, left, mixer, nil, "Left")
			wire(folder, right, mixer, nil, "Right")
			table.insert(voices, {
				Player = player, Left = left, Right = right, Instrument = instrument,
				RootNote = sample.RootNote, Gain = sample.Volume, Active = false, Action = nil,
				Start = 0, Duration = 0, Attack = 0, Decay = 0, Sustain = 0, Release = 0,
				Velocity = 0, Pan = 0, Pitch = 1, Level = 0,
			})
		end
	end
	return setmetatable({Folder = folder, Voices = voices, Volume = 1, Pitch = 1, Pan = 0,
		Scheduled = 0, Stolen = 0, Unavailable = 0, Alive = true}, Backend)
end
export type Pool = typeof(Backend.new())
function Backend.Schedule(self: Pool, events: buffer, index: number, at: number, duration: number): boolean
	if not self.Alive then return false end
	local offset = index * 40
	local instrument = buffer.readu16(events, offset + 10)
	local selected: Voice? = nil
	for _, voice in self.Voices do
		if voice.Instrument == instrument and voice.Player.IsReady then
			if not voice.Active then selected = voice; break end
			if not selected or voice.Level < selected.Level
				or (voice.Level == selected.Level and voice.Start < selected.Start) then selected = voice end
		end
	end
	if not selected then self.Unavailable += 1; return false end
	local voice = selected
	if voice.Active then self.Stolen += 1 end
	stop(voice)
	voice.Start = at; voice.Duration = duration
	voice.Attack = buffer.readf32(events, offset + 12)
	voice.Decay = buffer.readf32(events, offset + 16)
	voice.Sustain = buffer.readf32(events, offset + 20)
	voice.Release = buffer.readf32(events, offset + 24)
	voice.Pan = buffer.readf32(events, offset + 28)
	voice.Velocity = buffer.readu8(events, offset + 9) / 127
	voice.Pitch = 2 ^ ((buffer.readu8(events, offset + 8) - voice.RootNote) / 12)
	voice.Player.PlaybackSpeed = math.clamp(voice.Pitch * self.Pitch, 0.05, 20)
	voice.Player.TimePosition = 0; voice.Player.Volume = 1
	voice.Active = true
	voice.Action = voice.Player:Play(at)
	self.Scheduled += 1
	return true
end
function Backend.Step(self: Pool, now: number)
	for _, voice in self.Voices do
		if not voice.Active then continue end
		local age = now - voice.Start
		if age >= voice.Duration + voice.Release then stop(voice); continue end
		local envelope: number
		if age < voice.Duration then envelope = heldLevel(voice, age)
		elseif voice.Release > 0 then
			envelope = heldLevel(voice, voice.Duration) * (1 - (age - voice.Duration) / voice.Release)
		else envelope = 0 end
		voice.Level = envelope * voice.Velocity * voice.Gain * self.Volume
		local angle = (math.clamp(voice.Pan + self.Pan, -1, 1) + 1) * math.pi / 4
		voice.Left.Volume = math.clamp(voice.Level * math.cos(angle), 0, 1)
		voice.Right.Volume = math.clamp(voice.Level * math.sin(angle), 0, 1)
		voice.Player.PlaybackSpeed = math.clamp(voice.Pitch * self.Pitch, 0.05, 20)
	end
end
function Backend.SetMix(self: Pool, volume: number?, pitch: number?, pan: number?)
	if volume and volume == volume then self.Volume = math.clamp(volume, 0, 1) end
	if pitch and pitch == pitch then self.Pitch = math.clamp(pitch, 0.05, 4) end
	if pan and pan == pan then self.Pan = math.clamp(pan, -1, 1) end
end
function Backend.StopAll(self: Pool)
	for _, voice in self.Voices do stop(voice) end
end
function Backend.Destroy(self: Pool)
	self:StopAll(); self.Alive = false
	self.Folder:Destroy(); table.clear(self.Voices)
end
return Backend
