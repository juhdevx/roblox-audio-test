--!strict
-- Runs opt-in Studio tests for reassembly, Actors, scheduling and lifecycle cleanup.
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage").Shared.AudioSequence
local Config = require(Shared.Config)
local Parser = require(Shared.Parser)
local LRU = require(Shared.LRU)
local Protocol = require(Shared.Protocol)
local Fixture = require(script.Parent.Fixture)
local Receiver = require(script.Parent.Receiver)
local Decoder = require(script.Parent.Decoder)
local Backend = require(script.Parent.AudioBackend)
local Sequencer = require(script.Parent.Sequencer)
local Tests = {}
function Tests.Run(): number
	assert(RunService:IsStudio(), "Studio tests only")
	local checks = 0
	local function check(condition: boolean, message: string)
		assert(condition, message); checks += 1
	end
	local function frame() RunService.Heartbeat:Wait() end
	local small = Fixture.Small()
	local large = Fixture.Large(frame)
	local header: Protocol.Header = {
		Id = "Test", Token = "test-token", Bytes = buffer.len(large),
		ChunkBytes = Config.ChunkBytes, Count = math.ceil(buffer.len(large) / Config.ChunkBytes),
		Version = 1, Checksum = buffer.readu32(large, 12),
	}
	local requests = {}
	local received: buffer? = nil
	local failed = ""
	local receiver = Receiver.new(function(action, a, b)
		table.insert(requests, {action, a, b})
	end, function(_, data) received = data end, function(message) failed = message end)
	receiver:Expect("Test")
	local bad = table.clone(header); bad.Bytes = 100000000
	receiver:Header(bad); check(receiver.Current == nil, "Reject oversized header")
	receiver:Header(header)
	local allocation = (receiver.Current :: Receiver.Receipt).Data
	receiver:Header(header)
	check((receiver.Current :: Receiver.Receipt).Data == allocation, "Repeated header preserves allocation")
	receiver:Chunk("wrong-token", 1, buffer.create(Config.ChunkBytes))
	check((receiver.Current :: Receiver.Receipt).Received == 0, "Reject foreign chunk")
	for index = header.Count, 2, -1 do
		local offset = (index - 1) * Config.ChunkBytes
		local chunk = buffer.create(math.min(Config.ChunkBytes, header.Bytes - offset))
		buffer.copy(chunk, 0, large, offset, buffer.len(chunk))
		receiver:Chunk(header.Token, index, chunk)
		receiver:Chunk(header.Token, index, chunk)
	end
	check(received == nil, "Missing chunk blocks completion")
	check((receiver.Current :: Receiver.Receipt).Received == header.Count - 1, "Ignore duplicate chunks")
	local receipt = receiver.Current :: Receiver.Receipt
	receipt.RepairAt = 0
	receiver:Step()
	check(requests[#requests][1] == "Repair" and requests[#requests][3][1] == 1, "Request missing first chunk")
	local first = buffer.create(Config.ChunkBytes); buffer.copy(first, 0, large, 0, Config.ChunkBytes)
	receiver:Chunk(header.Token, 1, first)
	check(received == allocation, "Reassembly uses the original buffer")
	check(buffer.tostring(received :: buffer) == buffer.tostring(large), "Out-of-order reassembly exact")
	receiver:Expect("Test"); receiver:Header(header)
	local expiring = receiver.Current :: Receiver.Receipt
	expiring.Started = -math.huge
	receiver:Step(); check(failed == "Transfer timed out", "Transfer deadline enforced")
	receiver:Destroy(); check(receiver.Current == nil, "Receiver releases buffer")

	local cache = LRU.new(10)
	cache:Put("a", "A", 4, 100); cache:Put("b", "B", 4, 100)
	check(cache:Get("a", 0) == "A", "Cache hit")
	cache:Put("c", "C", 4, 100)
	check(cache:Get("b", 0) == nil and cache.Bytes == 8, "Evict least recently used")
	check(cache:Get("a", 101) == nil and cache.Bytes == 4, "Cache TTL")
	cache:Put("huge", "X", 20, 100)
	check(cache.Bytes == 4, "Oversized cache entry rejected")
	cache:Destroy(); check(cache.Bytes == 0 and next(cache.Entries) == nil, "Cache cleanup")

	local decoded: any = nil
	local decodeError = ""
	local testActor = script.Parent.DecoderActor:Clone() :: Actor
	testActor.Name = "IntegrationTestActor"; testActor:SetAttribute("Ready", false)
	testActor.Parent = script.Parent
	local decoder = Decoder.new(testActor,
		function(sequence) decoded = sequence end, function(message) decodeError = message end)
	decoder:Begin(large)
	local deadline = os.clock() + 60
	while not decoded and decodeError == "" and os.clock() < deadline do decoder:Step(); frame() end
	check(decodeError == "" and decoded ~= nil, "Actor completes large file: " .. decodeError)
	check(decoded.Metadata.EventCount == 16384, "Actor returns all 16384 events")
	check(buffer.len(decoded.Events) == 16384 * 40 and buffer.len(decoded.Tracks) == 12, "Actor packed output sizes")
	local job = assert(Parser.Begin(large))
	while not Parser.Step(job, 256) do frame() end
	local serial = assert(Parser.Result(job))
	check(buffer.tostring(serial.Events) == buffer.tostring(decoded.Events)
		and buffer.tostring(serial.Tracks) == buffer.tostring(decoded.Tracks), "Actor output equals serial parser")
	Parser.Destroy(job)
	decoder:Begin(large); decoder:Step(); decoder:Cancel()
	for _ = 1, 4 do frame(); decoder:Step() end
	check(not decoder.Busy and decoder.Sequence == nil, "Decoder cancellation releases job")
	decoded = nil
	decoder:Begin(large); decoder:Step(); decoder:Begin(small)
	deadline = os.clock() + 10
	while not decoded and decodeError == "" and os.clock() < deadline do decoder:Step(); frame() end
	check(decoded ~= nil and decoded.Metadata.EventCount == 6, "New job supersedes cancelled Actor work")
	decoded = nil
	local corrupt = Fixture.Small()
	buffer.writeu8(corrupt, buffer.len(corrupt) - 1, 99)
	decoder:Begin(corrupt); deadline = os.clock() + 10
	while decodeError == "" and os.clock() < deadline do decoder:Step(); frame() end
	check(decodeError ~= "" and decoded == nil, "Actor rejects checksum corruption")
	decoder:Destroy(); check(decoder.Connection == nil, "Decoder disconnects result listener")
	testActor:Destroy()

	local smallJob = assert(Parser.Begin(small))
	while not Parser.Step(smallJob, 256) do frame() end
	local sequence = assert(Parser.Result(smallJob))
	local records = {}
	local stops = 0
	local fake = {
		Schedule = function(_self: any, events: buffer, index: number, at: number, duration: number): boolean
			table.insert(records, {Tick = buffer.readu32(events, index * 40), At = at, Duration = duration})
			return true
		end,
		Step = function() end,
		StopAll = function() stops += 1 end,
		SetMix = function() end,
		Destroy = function() end,
	}
	local sequencer = Sequencer.new(fake :: any)
	sequencer:Load(sequence); sequencer:Play()
	for index = 0, 299 do sequencer:Step(if index == 0 then 0 else 1 / 60, index / 60) end
	check(#records == sequence.Metadata.EventCount, "Scheduler emits each note once")
	for index = 2, #records do check(records[index].At >= records[index - 1].At, "Tracks merge chronologically") end
	sequencer:Stop(); table.clear(records); sequencer:Play()
	sequencer:Step(0, 0)
	sequencer:Pause(); local count = #records
	sequencer:Step(1, 1)
	check(#records == count and not sequencer.Playing, "Paused transport emits no notes")
	sequencer:Seek(sequence.Metadata.DurationTicks / 2)
	check(sequencer:GetTick() == sequence.Metadata.DurationTicks / 2, "Seek positions transport")
	sequencer:SetBPM(90); check(sequencer.BPM == 90, "BPM adjustment")
	sequencer:SetLoop(true); sequencer:Seek(0); sequencer:Play()
	table.clear(records)
	local seconds = sequence.Metadata.DurationTicks / (90 * sequence.Metadata.TicksPerBeat / 60)
	for index = 0, math.ceil(seconds * 2.2 * 60) do sequencer:Step(if index == 0 then 0 else 1 / 60, index / 60) end
	check(#records > sequence.Metadata.EventCount * 2, "Loop schedules following cycles")
	sequencer:Stop(); check(sequencer:GetTick() == 0 and stops > 0, "Stop resets and cancels audio")
	sequencer:Destroy(); Parser.Destroy(smallJob)

	local SoundService = game:GetService("SoundService")
	local before = #SoundService:GetDescendants()
	for _ = 1, 30 do local pool = Backend.new({}); pool:Destroy() end
	check(#SoundService:GetDescendants() == before, "Repeated pool destruction leaves no instances")
	local pool = Backend.new({})
	local plays, cancellations, stopped = 0, 0, 0
	local fakePlayer: any = {
		IsReady = true, PlaybackSpeed = 1, TimePosition = 0, Volume = 0,
		Play = function(_self: any, _at: number) plays += 1; return plays end,
		Cancel = function() cancellations += 1 end,
		Stop = function() stopped += 1 end,
	}
	local voice: any = {
		Player = fakePlayer, Left = {Volume = 0}, Right = {Volume = 0}, Instrument = 0,
		RootNote = 60, Gain = 1, Active = false, Start = 0, Duration = 0, Attack = 0,
		Decay = 0, Sustain = 0, Release = 0, Velocity = 0, Pan = 0, Pitch = 1, Level = 0,
	}
	table.insert(pool.Voices, voice)
	local events = buffer.create(40)
	buffer.writeu8(events, 8, 60); buffer.writeu8(events, 9, 127)
	buffer.writef32(events, 12, 0.1); buffer.writef32(events, 16, 0.1)
	buffer.writef32(events, 20, 0.5); buffer.writef32(events, 24, 0.2)
	check(pool:Schedule(events, 0, 10, 1), "Voice schedule")
	pool:Step(10.05); check(math.abs(voice.Level - 0.5) < 0.001, "Attack envelope")
	pool:Step(10.3); check(math.abs(voice.Level - 0.5) < 0.001, "Sustain envelope")
	pool:Step(11.1); check(math.abs(voice.Level - 0.25) < 0.001, "Release envelope")
	pool:SetMix(0.5, 2, 1); pool:Step(11.1)
	check(voice.Left.Volume < 0.0001 and voice.Right.Volume > 0 and fakePlayer.PlaybackSpeed == 2, "Realtime mix and pan")
	check(pool:Schedule(events, 0, 12, 1) and pool.Stolen == 1 and cancellations > 0, "Stealing cancels pending actions")
	pool:StopAll(); check(not voice.Active and stopped > 0, "Stop cancels voices")
	pool:Destroy()
	check(#SoundService:GetDescendants() == before, "Pool cleanup with reused voice")
	script:SetAttribute("PassedChecks", checks)
	print(`[AudioSequence Integration] PASS: {checks} checks`)
	return checks
end
return Tests
