--!strict
-- Merges track cursors into a bounded lookahead scheduler with an injectable audio backend.
local Shared = game:GetService("ReplicatedStorage").Shared.AudioSequence
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Backend = require(script.Parent.AudioBackend)
local Sequencer = {}
Sequencer.__index = Sequencer
function Sequencer.new(backend: Backend.IAudioBackend)
	return setmetatable({
		Backend = backend, Sequence = nil :: Types.Sequence?,
		Cursors = buffer.create(0), AbsoluteTick = 0, ScheduleCycle = 0,
		BPM = 120, Loop = false, Playing = false, Scheduled = 0, Late = 0,
	}, Sequencer)
end
export type Player = typeof(Sequencer.new(nil :: any))
local function resetCursors(self: Player, tick: number)
	local sequence = self.Sequence
	if not sequence then return end
	for track = 0, sequence.Metadata.TrackCount - 1 do
		local first = buffer.readu32(sequence.Tracks, track * 12 + 4)
		local count = buffer.readu32(sequence.Tracks, track * 12 + 8)
		-- Binary search makes seek independent of the number of preceding notes.
		local low, high = first, first + count
		while low < high do
			local middle = math.floor((low + high) / 2)
			if buffer.readu32(sequence.Events, middle * 40) < tick then low = middle + 1
			else high = middle end
		end
		buffer.writeu32(self.Cursors, track * 4, low)
	end
end
function Sequencer.Load(self: Player, sequence: Types.Sequence)
	self.Backend:StopAll()
	self.Sequence = sequence
	self.Cursors = buffer.create(sequence.Metadata.TrackCount * 4)
	self.AbsoluteTick = 0; self.ScheduleCycle = 0
	self.BPM = sequence.Metadata.BPM; self.Playing = false; self.Loop = false
	resetCursors(self, 0)
end
function Sequencer.GetTick(self: Player): number
	if not self.Sequence then return 0 end
	local duration = self.Sequence.Metadata.DurationTicks
	return if self.Loop then self.AbsoluteTick % duration else math.min(self.AbsoluteTick, duration)
end
function Sequencer.Seek(self: Player, tick: number)
	if not self.Sequence then return end
	assert(tick == tick and math.abs(tick) < math.huge, "Invalid seek")
	self.Backend:StopAll()
	self.AbsoluteTick = math.clamp(tick, 0, self.Sequence.Metadata.DurationTicks)
	self.ScheduleCycle = 0
	resetCursors(self, self.AbsoluteTick)
end
function Sequencer.Play(self: Player)
	if not self.Sequence then return end
	if not self.Loop and self:GetTick() >= self.Sequence.Metadata.DurationTicks then self:Seek(0) end
	self.Playing = true
end
function Sequencer.Pause(self: Player)
	self:Seek(self:GetTick()); self.Playing = false
end
function Sequencer.Stop(self: Player)
	self.Playing = false; self:Seek(0)
end
function Sequencer.SetBPM(self: Player, bpm: number)
	assert(bpm == bpm and bpm >= 20 and bpm <= 400, "BPM must be between 20 and 400")
	self:Seek(self:GetTick()); self.BPM = bpm
end
function Sequencer.SetLoop(self: Player, looped: boolean)
	self:Seek(self:GetTick()); self.Loop = looped
end
function Sequencer.Step(self: Player, dt: number, mixerNow: number)
	local sequence = self.Sequence
	if not sequence then return end
	if self.Playing then
		local ticksPerSecond = self.BPM * sequence.Metadata.TicksPerBeat / 60
		self.AbsoluteTick += math.max(0, dt) * ticksPerSecond
		local duration = sequence.Metadata.DurationTicks
		local horizon = self.AbsoluteTick + Config.Lookahead * ticksPerSecond
		-- Skip whole missed cycles after a suspended client, instead of replaying a backlog.
		if self.Loop and self.AbsoluteTick >= (self.ScheduleCycle + 1) * duration then
			self.ScheduleCycle = math.floor(self.AbsoluteTick / duration)
			resetCursors(self, self.AbsoluteTick % duration)
			self.Backend:StopAll()
		end
		for _ = 1, Config.MaxNotesPerFrame do
			local selectedTrack, selectedIndex, nextTick = -1, 0, math.huge
			for track = 0, sequence.Metadata.TrackCount - 1 do
				local index = buffer.readu32(self.Cursors, track * 4)
				local finish = buffer.readu32(sequence.Tracks, track * 12 + 4)
					+ buffer.readu32(sequence.Tracks, track * 12 + 8)
				if index < finish then
					local tick = buffer.readu32(sequence.Events, index * 40) + self.ScheduleCycle * duration
					if tick < nextTick then selectedTrack = track; selectedIndex = index; nextTick = tick end
				end
			end
			if selectedTrack < 0 then
				if self.Loop and (self.ScheduleCycle + 1) * duration <= horizon then
					self.ScheduleCycle += 1; resetCursors(self, 0); continue
				end
				break
			end
			if nextTick > horizon then break end
			buffer.writeu32(self.Cursors, selectedTrack * 4, selectedIndex + 1)
			local noteSeconds = buffer.readu32(sequence.Events, selectedIndex * 40 + 4) / ticksPerSecond
			local delay = (nextTick - self.AbsoluteTick) / ticksPerSecond
			if delay < -noteSeconds then self.Late += 1; continue end
			self.Backend:Schedule(sequence.Events, selectedIndex, mixerNow + math.max(0, delay),
				noteSeconds + math.min(0, delay))
			self.Scheduled += 1
		end
		if not self.Loop and self.AbsoluteTick >= duration then self.Playing = false end
	end
	self.Backend:Step(mixerNow)
end
function Sequencer.Destroy(self: Player)
	self.Backend:StopAll(); self.Sequence = nil
	self.Cursors = buffer.create(0); self.Playing = false
end
return Sequencer
