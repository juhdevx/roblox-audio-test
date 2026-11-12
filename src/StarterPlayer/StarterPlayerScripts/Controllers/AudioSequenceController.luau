--!strict
-- Connects transport, Actor decoding, cache and playback through one client lifecycle.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Shared = ReplicatedStorage.Shared.AudioSequence
local Config = require(Shared.Config)
local Protocol = require(Shared.Protocol)
local Types = require(Shared.Types)
local LRU = require(Shared.LRU)
local SampleBank = require(Shared.SampleBank)
local Modules = script.Parent.Parent.AudioSequence
local Receiver = require(Modules.Receiver)
local Decoder = require(Modules.Decoder)
local Backend = require(Modules.AudioBackend)
local Sequencer = require(Modules.Sequencer)
local Controller = {}
local connections: {RBXScriptConnection} = {}
local cache = LRU.new(Config.ClientCacheBytes)
local request: RemoteEvent
local dataRemote: RemoteEvent
local stateRemote: RemoteEvent
local receiver: Receiver.Reassembler
local decoder: Decoder.ClientDecoder
local backend: Backend.Pool
local sequencer: Sequencer.Player
local active = false
local desiredId = ""
local loadedId = ""
local pendingHeader: Protocol.Header? = nil
local latestState: any = nil
local localPlay = false
local statusAt = 0
local loadStarted = 0
local retryAt = 0
local function problem(message: string)
	script:SetAttribute("LastError", message)
	warn(`[AudioSequence] {message}`)
end
local function applyState()
	local state = latestState
	if not state or state.Id ~= loadedId then return end
	sequencer:SetBPM(state.BPM); sequencer:SetLoop(state.Loop)
	local tick = state.Tick
	if state.Playing then tick += math.max(0, workspace:GetServerTimeNow() - state.Epoch) * state.BPM * state.PPQ / 60 end
	if state.Loop then tick %= state.Duration end
	sequencer:Seek(math.min(tick, state.Duration))
	if state.Playing and (state.Loop or tick < state.Duration) then sequencer:Play()
	else sequencer.Playing = false end
end
local function loaded(header: Protocol.Header, sequence: Types.Sequence)
	if header.Id ~= desiredId then return end
	if sequence.Metadata.Checksum ~= header.Checksum or sequence.Metadata.TotalBytes ~= header.Bytes
		or sequence.Metadata.Version ~= header.Version then problem("Header/content mismatch"); return end
	cache:Put(Protocol.Key(header), sequence, buffer.len(sequence.Events) + buffer.len(sequence.Tracks), math.huge)
	loadedId = header.Id; sequencer:Load(sequence)
	script:SetAttribute("LoadedId", loadedId)
	script:SetAttribute("EventCount", sequence.Metadata.EventCount)
	script:SetAttribute("LastError", nil)
	if latestState and latestState.Id == loadedId then applyState()
	elseif localPlay then sequencer:Play() end
end
function Controller.Init(_dependencies: any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	assert(remotes, "Missing Remotes")
	local folder = remotes:WaitForChild("AudioSequence", 15)
	assert(folder, "Missing AudioSequence remotes")
	request = folder:WaitForChild("Request", 10) :: RemoteEvent
	dataRemote = folder:WaitForChild("Data", 10) :: RemoteEvent
	stateRemote = folder:WaitForChild("State", 10) :: RemoteEvent
	assert(request and dataRemote and stateRemote, "AudioSequence remotes incomplete")
	backend = Backend.new()
	sequencer = Sequencer.new(backend :: any)
	local actor = Modules:WaitForChild("DecoderActor", 10) :: Actor
	assert(actor, "Missing DecoderActor")
	decoder = Decoder.new(actor, function(sequence)
		if pendingHeader then loaded(pendingHeader, sequence) end
		pendingHeader = nil
	end, problem)
	receiver = Receiver.new(function(action, a, b) request:FireServer(action, a, b) end,
		function(header, data)
			pendingHeader = header
			decoder:Begin(data)
		end, problem)
	script:SetAttribute("SamplesConfigured", next(SampleBank) ~= nil)
end
-- Load only accepts catalog IDs. Optional autoplay affects this client alone.
function Controller.Load(id: string, autoplay: boolean?)
	assert(Protocol.Id(id), "Invalid catalog ID")
	if desiredId ~= "" then request:FireServer("Cancel", desiredId) end
	desiredId = id; localPlay = autoplay == true
	loadedId = ""
	script:SetAttribute("LoadedId", nil)
	sequencer:Stop()
	loadStarted = os.clock(); retryAt = loadStarted + 2.5
	pendingHeader = nil; decoder:Cancel(); receiver:Expect(id)
	request:FireServer("Load", id)
end
function Controller.Start()
	if active then return end
	active = true
	table.insert(connections, dataRemote.OnClientEvent:Connect(function(action: string, a: any, b: any, c: any)
		if action == "Header" and Protocol.Header(a) and a.Id == desiredId then
			local cached = cache:Get(Protocol.Key(a), os.clock())
			if cached then
				request:FireServer("Ack", a.Token)
				if loadedId ~= a.Id or not sequencer.Sequence or sequencer.Sequence ~= cached then
					decoder:Cancel(); receiver:Destroy(); loaded(a, cached)
				end
			else receiver:Header(a) end
		elseif action == "Chunk" then receiver:Chunk(a, b, c)
		elseif action == "Error" and a == desiredId then problem(tostring(b)) end
	end))
	table.insert(connections, stateRemote.OnClientEvent:Connect(function(state: any)
		if latestState and state.Revision < latestState.Revision then return end
		latestState = state
		if state.Id == "" then return end
		if state.Id ~= loadedId then
			if state.Id ~= desiredId then Controller.Load(state.Id) end
		else applyState() end
	end))
	table.insert(connections, RunService.Heartbeat:Connect(function(dt: number)
		receiver:Step(); decoder:Step()
		if desiredId ~= "" and loadedId ~= desiredId and not receiver.Current and not decoder.Busy
			and os.clock() >= retryAt and os.clock() - loadStarted < Config.TransferSeconds then
			retryAt = os.clock() + 2.5
			request:FireServer("Load", desiredId)
		end
		sequencer:Step(dt, SoundService:GetMixerTime())
		statusAt += dt
		if statusAt >= 1 then
			statusAt = 0
			script:SetAttribute("CacheBytes", cache.Bytes)
			script:SetAttribute("Playing", sequencer.Playing)
			script:SetAttribute("Tick", sequencer:GetTick())
			script:SetAttribute("NotesScheduled", sequencer.Scheduled)
			script:SetAttribute("MissingSamples", backend.Unavailable)
		end
	end))
	request:FireServer("Status")
end
function Controller.Play() sequencer:Play() end
function Controller.Pause() sequencer:Pause() end
function Controller.Stop() sequencer:Stop() end
function Controller.Seek(tick: number) sequencer:Seek(tick) end
function Controller.SetBPM(bpm: number) sequencer:SetBPM(bpm) end
function Controller.SetLoop(looped: boolean) sequencer:SetLoop(looped) end
function Controller.SetMix(volume: number?, pitch: number?, pan: number?) backend:SetMix(volume, pitch, pan) end
function Controller.GetStatus()
	return {Id = loadedId, Playing = sequencer.Playing, Tick = sequencer:GetTick(),
		CacheBytes = cache.Bytes, Decoding = decoder.Busy, SamplesConfigured = next(SampleBank) ~= nil}
end
function Controller.Destroy()
	if desiredId ~= "" and request then request:FireServer("Cancel", desiredId) end
	active = false
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	receiver:Destroy(); decoder:Destroy(); sequencer:Destroy(); backend:Destroy(); cache:Destroy()
	pendingHeader = nil; latestState = nil; desiredId = ""; loadedId = ""
	script:SetAttribute("LoadedId", nil); script:SetAttribute("Playing", false)
end
return Controller
