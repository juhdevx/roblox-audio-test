--!strict
-- Streams spectral segments and renders the nearest accepted emote from its replicated server epoch.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Input = game:GetService("UserInputService")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.SpectralAudio.Config)
local Protocol = require(Shared.AudioSequence.Protocol)
local LRU = require(Shared.AudioSequence.LRU)
local Scope = require(Shared.Utils.Scope)
local Modules = script.Parent.Parent.SpectralAudio
local Receiver = require(script.Parent.Parent.AudioSequence.Receiver)
local Validator = require(Modules.Validator)
local Renderer = require(Modules.Renderer)
local OtherVolume = require(script.Parent.Parent.Emotes.SoundVolume)
type Track = {Frames: number, FPS: number, Voices: number, SegmentFrames: number, Segments: number,
	Preload: boolean, Encoding: number?, NoiseBands: number?, MixGain: number?}
type Load = {Id: string, Track: string, Part: number, Started: number, RetryAt: number,
	Data: buffer?, Header: Protocol.Header?}
type Source = {Character: Model?, Song: any, Start: number, Preview: boolean?}
type SourceMix = {Source: Source, Gain: number, Pan: number, Distance: number, Own: boolean}
local Controller = {}
local manifest: {[string]: Track} = {}
local cache = LRU.new(Config.CacheBytes)
local queue: {{Id: string, Track: string, Part: number}} = {}
local queued: {[string]: boolean} = {}
local sources: {[Player]: Source} = {}
local playerScopes: {[Player]: any} = {}
local request: RemoteEvent
local dataRemote: RemoteEvent
local scope: any
local receiver: any
local validator: Validator.Decoder
local renderer: Renderer.Pool
local active = false
local destroyed = true
local initialized = false
local generation = 0
local loading: Load? = nil
local lastStatus = 0
local renderTime = 0
local nextManifest = 0
local retries: {[string]: number} = {}
local retryAt: {[string]: number} = {}
local preparingTrack = ""
local preparationDeadline = 0
local preparationToken = 0
local selected: Source? = nil
local selectedMix: SourceMix? = nil
local outputGain = 0
local handoffActive = false
local handoffTarget: Source? = nil
local handoffElapsed = 0
local handoffStartGain = 0
local preview: Source? = nil
local previewToken = 0
local underruns = 0
local missingId = ""
local buffering = false
local recoveries = 0
local playbackState = "Idle"
local bufferedAhead = 0
local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function validManifest(raw: any): {[string]: Track}
	local accepted: {[string]: Track} = {}
	if type(raw) ~= "table" then return accepted end
	local count = 0
	for name, track in raw do
		if count >= 64 then break end
		if type(name) ~= "string" or #name < 1 or #name > 40 or not name:match("^[%w_]+$")
			or type(track) ~= "table" then continue end
		local encoding, bands, gain = track.Encoding or 1, track.NoiseBands or 0, track.MixGain or 1
		if not Protocol.Integer(track.FPS, 20, 90) or not Protocol.Integer(track.Frames, 1, 90 * 3600)
			or not Protocol.Integer(track.Voices, 16, 128) or not Protocol.Integer(track.SegmentFrames, 1, 2700)
			or not Protocol.Integer(track.Segments, 1, 9999)
			or track.Segments ~= math.ceil(track.Frames / track.SegmentFrames)
			or not ((encoding == 1 and bands == 0) or (encoding == 3 and Protocol.Integer(bands, 1, 16)))
			or not finite(gain) or gain < 0.5 or gain > 3 then continue end
		accepted[name] = {Frames = track.Frames, FPS = track.FPS, Voices = track.Voices,
			SegmentFrames = track.SegmentFrames, Segments = track.Segments, Preload = track.Preload == true,
			Encoding = encoding, NoiseBands = bands, MixGain = gain}
		count += 1
	end
	return accepted
end
local function playbackRate(song: any): number
	return math.clamp(if finite(song.PlaybackSpeed) then song.PlaybackSpeed else 1,
		Config.PlaybackRateMin or 0.25, Config.PlaybackRateMax or 2)
end
local function songVolume(song: any): number
	return math.clamp(if finite(song.Volume) then song.Volume else 1, 0, 2)
end
local function clearPreparation()
	preparingTrack = ""; preparationDeadline = 0; preparationToken += 1
	script:SetAttribute("LoadingTrack", "")
	script:SetAttribute("BufferedSeconds", 0)
end
local function stopPreview()
	local previousTrack = script:GetAttribute("PreviewTrack")
	if previousTrack and previousTrack ~= "" and preparingTrack == previousTrack then clearPreparation() end
	previewToken += 1
	preview = nil
	script:SetAttribute("PreviewTrack", "")
	script:SetAttribute("PreviewLoading", false)
	script:SetAttribute("PreviewProgress", 0)
	script:SetAttribute("PreviewError", nil)
end
local function idFor(name: string, part: number): string return `{name}_{string.format("%03d", part)}` end
local function dataFor(name: string, part: number): buffer?
	return cache:Get(idFor(name, part), os.clock())
end
local function enqueue(name: string, part: number)
	local track = manifest[name]
	if not track or part < 0 or part >= track.Segments then return end
	local id = idFor(name, part)
	if dataFor(name, part) or (loading and loading.Id == id) then return end
	if queued[id] then return end
	queued[id] = true
	table.insert(queue, {Id = id, Track = name, Part = part})
end
local function startupParts(track: Track): number
	local seconds = Config.StartupSeconds or 4
	return math.min(track.Segments, math.max(1, math.ceil(seconds * track.FPS / track.SegmentFrames)))
end
local function prioritize(name: string, firstPart: number, count: number)
	local track = manifest[name]
	if not track then return end
	for ahead = 0, count - 1 do enqueue(name, (firstPart + ahead) % track.Segments) end
end
local function prefetchParts(track: Track, rate: number): number
	return math.min(track.Segments, math.max(Config.PrefetchSegments + 1,
		math.ceil((Config.PrefetchSeconds or 12) * rate * track.FPS / track.SegmentFrames)))
end
local function sourceFrame(source: Source, track: Track): (number, number)
	local elapsed = math.max(0, workspace:GetServerTimeNow() - source.Start) * playbackRate(source.Song)
	return (elapsed * track.FPS) % track.Frames, elapsed
end
local function queueRank(name: string, part: number): number?
	local track = manifest[name]
	if not track then return nil end
	local rank: number? = nil
	local source = selected
	if source and source.Song.Track == name then
		local frame = sourceFrame(source, track)
		local firstPart = math.floor(frame / track.SegmentFrames)
		local ahead = (part - firstPart) % track.Segments
		if ahead < prefetchParts(track, playbackRate(source.Song)) then
			rank = if ahead <= 1 then ahead else 20 + ahead
		end
	end
	if preparingTrack == name and part < startupParts(track) then
		rank = math.min(rank or math.huge, 5 + part / math.max(1, startupParts(track)))
	end
	if track.Preload and part == 0 then rank = math.min(rank or math.huge, 100) end
	return rank
end
local function nextQueued(now: number): number?
	local bestIndex: number? = nil
	local bestRank = math.huge
	for index = #queue, 1, -1 do
		local entry = queue[index]
		local rank = queueRank(entry.Track, entry.Part)
		if not rank or dataFor(entry.Track, entry.Part) then
			queued[entry.Id] = nil; table.remove(queue, index)
		end
	end
	for index, entry in queue do
		local rank = queueRank(entry.Track, entry.Part)
		if rank and now >= (retryAt[entry.Id] or 0) and rank < bestRank then
			bestRank = rank; bestIndex = index
		end
	end
	return bestIndex
end
local function failed(message: string)
	script:SetAttribute("LastError", message)
	local previous = loading
	if previous then request:FireServer("Cancel", previous.Id) end
	loading = nil; receiver:Destroy(); validator:Cancel()
	if previous then
		local attempts = (retries[previous.Id] or 0) + 1
		retries[previous.Id] = attempts
		retryAt[previous.Id] = os.clock() + (if attempts < 3 then 2 ^ attempts else 30)
		enqueue(previous.Track, previous.Part)
		if attempts == 1 or attempts % 3 == 0 then warn(`[SpectralAudio] {message}`) end
	end
end
local function watchPlayer(player: Player)
	if playerScopes[player] then return end
	local owner = Scope.new(); playerScopes[player] = owner
	local characterScope: any = nil
	owner:Add(function() if characterScope then characterScope:Destroy(); characterScope = nil end end)
	local function watchCharacter(character: Model)
		if characterScope then characterScope:Destroy() end
		characterScope = Scope.new()
		local function refresh()
			sources[player] = nil
			local encoded = character:GetAttribute("EmoteSound")
			if type(encoded) ~= "string" then return end
			local ok, descriptor = pcall(HttpService.JSONDecode, HttpService, encoded)
			if ok and type(descriptor) == "table" and type(descriptor.Song) == "table"
				and player == Players.LocalPlayer then stopPreview() end
			if ok and type(descriptor) == "table" and type(descriptor.Song) == "table"
				and descriptor.Song.Backend == "Spectral" and finite(descriptor.StartTime) then
				sources[player] = {Character = character, Song = descriptor.Song, Start = descriptor.StartTime}
			end
		end
		characterScope:Connect(character:GetAttributeChangedSignal("EmoteSound"), refresh)
		refresh()
	end
	owner:Connect(player.CharacterAdded, watchCharacter)
	owner:Connect(player.CharacterRemoving, function()
		sources[player] = nil
		if player == Players.LocalPlayer then stopPreview() end
		if characterScope then characterScope:Destroy(); characterScope = nil end
	end)
	if player.Character then watchCharacter(player.Character) end
end
local function chooseSource(): SourceMix?
	local previewSource = preview
	if previewSource and manifest[previewSource.Song.Track] then
		return {Source = previewSource, Gain = songVolume(previewSource.Song)
			* (Config.PreviewVolume or 0.75), Pan = 0, Distance = 0, Own = true}
	end
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local listenerRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local listenerPosition = if listenerRoot and listenerRoot:IsA("BasePart") then listenerRoot.Position
		elseif camera then camera.CFrame.Position else nil
	local best: SourceMix? = nil
	local current: SourceMix? = nil
	local otherVolume = OtherVolume.Get()
	local show = workspace:GetAttribute("EmoteShowActive") == true
	for player, source in sources do
		local sourceCharacter = source.Character
		if not sourceCharacter then continue end
		local root = sourceCharacter:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or not manifest[source.Song.Track] then continue end
		if show and not sourceCharacter:GetAttribute("EmoteShowHost") then continue end
		local own = player == Players.LocalPlayer
		local multiplier = if own then 1 else otherVolume
		if multiplier <= 0 then continue end
		if not own and not listenerPosition then continue end
		-- Camera zoom changes direction, but never the listener's hearing distance.
		local distance = if own then 0 else (root.Position - (listenerPosition :: Vector3)).Magnitude
		if not own and distance > Config.MaxDistance then continue end
		local attenuation = if own then 1 else math.clamp(1 - (distance - Config.NearDistance)
			/ math.max(1, Config.MaxDistance - Config.NearDistance), 0, 1) ^ 2
		local pan = 0
		if not own and camera then
			local offset = root.Position - camera.CFrame.Position
			if offset.Magnitude > 0.001 then pan = camera.CFrame.RightVector:Dot(offset.Unit) * 0.65 end
		end
		local candidate: SourceMix = {Source = source,
			Gain = attenuation * multiplier * songVolume(source.Song),
			Pan = pan, Distance = distance, Own = own}
		if source == selected then current = candidate end
		if not best or own or (not best.Own and distance < best.Distance) then best = candidate end
	end
	if best and current and not best.Own and not current.Own and best.Source ~= current.Source then
		-- Keep a nearby dancer in focus until another is meaningfully closer.
		local switchRatio = Config.SourceSwitchRatio or 0.8
		local switchMargin = Config.SourceSwitchMargin or 3
		if best.Distance > current.Distance * switchRatio
			or best.Distance + switchMargin > current.Distance then return current end
	end
	return best
end
local function updateSelection(mix: SourceMix?, dt: number)
	local desired = if mix then mix.Source else nil
	local fadeSeconds = math.max(0.01, Config.SourceFadeSeconds or 0.06)
	if desired ~= selected then
		if not selected then
			renderer:Mute(); selected = desired; selectedMix = mix; outputGain = 0
			buffering = false; missingId = ""
			handoffActive = false; handoffTarget = nil
		elseif not handoffActive or handoffTarget ~= desired then
			handoffActive = true; handoffTarget = desired; handoffElapsed = 0; handoffStartGain = outputGain
		end
	elseif handoffActive then
		handoffActive = false; handoffTarget = nil
	end
	if handoffActive then
		handoffElapsed += dt
		outputGain = handoffStartGain * (1 - math.min(1, handoffElapsed / fadeSeconds))
		if handoffElapsed >= fadeSeconds then
			renderer:Mute(); selected = desired; selectedMix = mix; outputGain = 0
			buffering = false; missingId = ""
			handoffActive = false; handoffTarget = nil
		end
	elseif mix then
		selectedMix = mix
		outputGain += (mix.Gain - outputGain) * (1 - math.exp(-dt / fadeSeconds))
	else
		outputGain = 0; selectedMix = nil
	end
end
local function bufferedSeconds(name: string, frame: number, count: number): number
	local track = manifest[name]
	if not track then return 0 end
	local firstPart = math.floor(frame / track.SegmentFrames)
	local frames = 0
	for ahead = 0, math.min(track.Segments, count) - 1 do
		local part = (firstPart + ahead) % track.Segments
		local data = dataFor(name, part)
		if not data then break end
		local available = buffer.readu32(data, 20)
		if ahead == 0 then available -= frame - buffer.readu32(data, 24) end
		frames += math.max(0, available)
	end
	return math.min(track.Frames, frames) / track.FPS
end
local function bufferMissing(name: string, part: number)
	local id = idFor(name, part)
	if missingId ~= id then underruns += 1; missingId = id end
	buffering = true; playbackState = "Buffering"
	renderer:Mute(); outputGain = 0
end
local function render(dt: number)
	updateSelection(chooseSource(), dt)
	local source = selected
	if not source then
		renderer:Mute(); buffering = false; bufferedAhead = 0
		playbackState = if preparingTrack ~= "" then "Preparing" else "Idle"
		return
	end
	local name = source.Song.Track
	local track = manifest[name]
	if not track then
		renderer:Mute(); selected = nil; selectedMix = nil; outputGain = 0; return
	end
	local rate = playbackRate(source.Song)
	local frame, elapsed = sourceFrame(source, track)
	local firstIndex = math.floor(frame)
	local nextIndex = (firstIndex + 1) % track.Frames
	local part = math.floor(firstIndex / track.SegmentFrames)
	local aheadCount = prefetchParts(track, rate)
	prioritize(name, part, aheadCount)
	bufferedAhead = bufferedSeconds(name, frame, aheadCount) / rate
	local first = dataFor(name, part)
	if not first then
		bufferMissing(name, part); return
	end
	local nextPart = math.floor(nextIndex / track.SegmentFrames)
	local second = dataFor(name, nextPart)
	-- A missing successor must never repeat a stale endpoint across a segment or loop boundary.
	if not second then bufferMissing(name, nextPart); return end
	if buffering then recoveries += 1 end
	buffering = false; missingId = ""; playbackState = "Playing"
	local firstFrame = firstIndex - buffer.readu32(first, 24)
	local secondFrame = nextIndex - buffer.readu32(second, 24)
	renderer:Render(first, firstFrame, second, secondFrame, frame - firstIndex,
		math.min(track.Voices, #renderer.Voices), outputGain,
		if selectedMix then selectedMix.Pan else 0, dt, track.MixGain or 1, rate)
	script:SetAttribute("Position", elapsed % (track.Frames / track.FPS))
end
function Controller.Init(_dependencies: any)
	if initialized then Controller.Destroy() end
	generation += 1
	local currentGeneration = generation
	initialized = true; active = false
	destroyed = false
	cache = LRU.new(Config.CacheBytes)
	lastStatus = 0; renderTime = 0; nextManifest = 0
	underruns = 0; missingId = ""; outputGain = 0; selected = nil; selectedMix = nil
	buffering = false; recoveries = 0; playbackState = "Idle"; bufferedAhead = 0
	handoffActive = false; handoffTarget = nil; handoffElapsed = 0; handoffStartGain = 0
	clearPreparation()
	stopPreview()
	script:SetAttribute("SourceGain", 0)
	script:SetAttribute("SourceDistance", 0)
	script:SetAttribute("SourceOwn", false)
	script:SetAttribute("LoadingTrack", "")
	script:SetAttribute("BufferedSeconds", 0)
	script:SetAttribute("PreviewError", nil)
	script:SetAttribute("State", playbackState)
	script:SetAttribute("Ready", false)
	script:SetAttribute("LastError", nil)
	script:SetAttribute("Position", 0)
	script:SetAttribute("Buffering", false)
	script:SetAttribute("BufferedAheadSeconds", 0)
	script:SetAttribute("RecoveryCount", 0)
	script:SetAttribute("SelectionSwitches", 0)
	script:SetAttribute("SelectionScans", 0)
	script:SetAttribute("SelectionAdaptive", false)
	script:SetAttribute("DownloadProgress", 0)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if generation ~= currentGeneration or destroyed then return end
	assert(remotes, "Missing Remotes")
	local root = remotes:WaitForChild("SpectralAudio", 15)
	if generation ~= currentGeneration or destroyed then return end
	assert(root, "Missing SpectralAudio remotes")
	request = root:WaitForChild("Request", 10) :: RemoteEvent
	if generation ~= currentGeneration or destroyed then return end
	dataRemote = root:WaitForChild("Data", 10) :: RemoteEvent
	if generation ~= currentGeneration or destroyed then return end
	assert(request and dataRemote, "Missing spectral transport")
	scope = Scope.new()
	local mobile = Input.TouchEnabled and not Input.KeyboardEnabled
	local voices = if mobile then Config.MobileVoices else Config.DesktopVoices
	renderer = Renderer.new(voices, mobile)
	local actor = Modules.ValidationActor :: Actor
	local function current(): boolean return generation == currentGeneration and not destroyed end
	local function onFailed(message: string) if current() then failed(message) end end
	validator = Validator.new(actor, function(header)
		if not current() then return end
		local load = loading
		if not load or not load.Data or not load.Header then return end
		local track = manifest[load.Track]
		if not track or header.Checksum ~= load.Header.Checksum or header.Voices ~= track.Voices
			or header.FPS ~= track.FPS or header.TotalFrames ~= track.Frames
			or header.Encoding ~= (track.Encoding or 1) or header.NoiseBands ~= (track.NoiseBands or 0)
			or header.First ~= load.Part * track.SegmentFrames
			or header.Frames ~= math.min(track.SegmentFrames, track.Frames - header.First) then
			failed("Spectral segment does not match its manifest"); return
		end
		cache:Put(load.Id, load.Data, buffer.len(load.Data), math.huge)
		retries[load.Id] = nil; retryAt[load.Id] = nil; loading = nil
		script:SetAttribute("LastError", nil)
	end, onFailed)
	receiver = Receiver.new(function(action, a, b) if current() then request:FireServer(action, a, b) end end,
		function(header, data)
			if not current() then return end
			if not loading or header.Id ~= loading.Id then return end
			loading.Data = data; loading.Header = header; validator:Begin(data)
		end, onFailed)
end
function Controller.Start()
	if active or not initialized or destroyed or not scope or not renderer then return end
	active = true
	local currentGeneration = generation
	scope:Connect(dataRemote.OnClientEvent, function(action: string, a: any, b: any, c: any)
		if generation ~= currentGeneration or destroyed then return end
		if action == "Manifest" then
			manifest = validManifest(a)
			local names = {}
			for name, track in manifest do if track.Preload then table.insert(names, name) end end
			table.sort(names)
			for _, name in names do enqueue(name, 0) end
		elseif action == "Header" and loading and Protocol.Header(a) and a.Id == loading.Id then receiver:Header(a)
		elseif action == "Chunk" then receiver:Chunk(a, b, c)
		elseif action == "Error" and loading and a == loading.Id then failed(tostring(b)) end
	end)
	scope:Connect(Players.PlayerAdded, watchPlayer)
	scope:Connect(Players.PlayerRemoving, function(player)
		sources[player] = nil
		if playerScopes[player] then playerScopes[player]:Destroy(); playerScopes[player] = nil end
	end)
	for _, player in Players:GetPlayers() do watchPlayer(player) end
	scope:Connect(RunService.Heartbeat, function(dt: number)
		if generation ~= currentGeneration or destroyed then return end
		receiver:Step(); validator:Step()
		local now = os.clock()
		if preparingTrack ~= "" and now >= preparationDeadline then clearPreparation() end
		if next(manifest) == nil and now >= nextManifest then request:FireServer("Manifest"); nextManifest = now + 3 end
		local nextIndex = nextQueued(now)
		-- Release obsolete downloads immediately so a new selection can use the transport.
		if loading and not queueRank(loading.Track, loading.Part) then
			request:FireServer("Cancel", loading.Id)
			receiver:Destroy(); validator:Cancel(); loading = nil
		end
		if not loading and nextIndex then
			local entry = table.remove(queue, nextIndex); queued[entry.Id] = nil
			if not cache:Get(entry.Id, now) then
				loading = {Id = entry.Id, Track = entry.Track, Part = entry.Part, Started = now, RetryAt = now + 3}
				receiver:Expect(entry.Id); request:FireServer("Load", entry.Id)
			end
		elseif loading and not receiver.Current and not validator.Busy and now >= loading.RetryAt then
			if now - loading.Started > 30 then failed("Spectral download timed out")
			else request:FireServer("Load", loading.Id); loading.RetryAt = now + 3 end
		end
		renderTime += dt
		if renderTime >= 1 / Config.RenderHz then
			render(math.min(renderTime, 0.1))
			renderTime %= 1 / Config.RenderHz
		end
		lastStatus += dt
		if lastStatus >= 1 then
			lastStatus = 0
			script:SetAttribute("Ready", renderer:IsReady())
			script:SetAttribute("CacheBytes", cache.Bytes)
			script:SetAttribute("Voices", #renderer.Voices)
			script:SetAttribute("RenderMs", renderer.LastMs)
			script:SetAttribute("MaxRenderMs", renderer.MaxMs)
			script:SetAttribute("AverageRenderMs", renderer.AverageMs)
			script:SetAttribute("ActiveVoiceLimit", renderer.VoiceLimit)
			script:SetAttribute("SelectionSwitches", renderer.SelectionSwitches)
			script:SetAttribute("SelectionScans", renderer.SelectionScans)
			script:SetAttribute("SelectionAdaptive", renderer.Selection.Adaptive)
			script:SetAttribute("OutputRms", renderer.Analyzer.RmsLevel)
			script:SetAttribute("PhaseStarts", renderer.PhaseStarts)
			script:SetAttribute("PhaseCorrectedFrames", renderer.PhaseCorrectedFrames or 0)
			script:SetAttribute("NoiseReady", renderer.Noise:IsReady())
			script:SetAttribute("NoiseVoices", #renderer.Noise.Bands * 2)
			script:SetAttribute("RenderedFrames", renderer.Rendered)
			script:SetAttribute("Underruns", underruns)
			script:SetAttribute("Track", if selected then selected.Song.Track else "")
			script:SetAttribute("SourceGain", outputGain)
			script:SetAttribute("SourceDistance", if selectedMix then selectedMix.Distance else 0)
			script:SetAttribute("SourceOwn", if selectedMix then selectedMix.Own else false)
			script:SetAttribute("QueuedSegments", #queue)
			script:SetAttribute("DownloadingTrack", if loading then loading.Track else "")
			script:SetAttribute("DownloadingPart", if loading then loading.Part else -1)
			script:SetAttribute("State", playbackState)
			script:SetAttribute("Buffering", buffering)
			script:SetAttribute("BufferedAheadSeconds", bufferedAhead)
			script:SetAttribute("RecoveryCount", recoveries)
			local receipt = receiver.Current
			script:SetAttribute("DownloadProgress", if receipt then receipt.Received / receipt.Header.Count
				elseif loading and loading.Data then 1 else 0)
		end
	end)
	request:FireServer("Manifest"); nextManifest = os.clock() + 3
end
-- Starts a bounded startup buffer without blocking inventory interaction.
local function beginPreparation(name: string)
	if preparingTrack ~= name then preparationToken += 1 end
	preparingTrack = name; preparationDeadline = os.clock() + Config.PrepareTimeout
	if not selected then playbackState = "Preparing"; script:SetAttribute("State", playbackState) end
end
local function prepare(name: string): boolean
	local track = manifest[name]
	if not active or not track then return false end
	local count = startupParts(track)
	prioritize(name, 0, count)
	local ready = renderer:IsReady()
	local buffered = 0
	for part = 0, count - 1 do
		if dataFor(name, part) then buffered += math.min(track.SegmentFrames, track.Frames - part * track.SegmentFrames) / track.FPS
		else ready = false; break end
	end
	script:SetAttribute("LoadingTrack", if ready then "" else name)
	script:SetAttribute("BufferedSeconds", buffered)
	if script:GetAttribute("PreviewTrack") == name then
		local total = math.min(track.Frames, count * track.SegmentFrames) / track.FPS
		local progress = math.clamp(buffered / math.max(0.001, total), 0, 1)
		script:SetAttribute("PreviewProgress", if renderer:IsReady() then progress else progress * 0.95)
	end
	return ready
end
function Controller.Prepare(name: string): boolean
	if not active or destroyed or type(name) ~= "string" or not manifest[name] then return false end
	beginPreparation(name)
	local ready = prepare(name)
	if ready then clearPreparation() end
	return ready
end
function Controller.EnsureReady(name: string): boolean
	if not active or destroyed or type(name) ~= "string" then return false end
	stopPreview()
	beginPreparation(name)
	local currentGeneration, token = generation, preparationToken
	local started = os.clock()
	local deadline = started + Config.PrepareTimeout
	while active and not destroyed and generation == currentGeneration and preparationToken == token
		and os.clock() < deadline do
		if prepare(name) then
			clearPreparation()
			script:SetAttribute("PrepareMs", (os.clock() - started) * 1000)
			return true
		end
		task.wait(0.05)
	end
	if generation == currentGeneration and preparationToken == token then clearPreparation() end
	return false
end
-- Auditions a catalog song locally without equipping or requesting an emote.
function Controller.Preview(song: any): boolean
	if not active or destroyed or type(song) ~= "table" or song.Backend ~= "Spectral"
		or type(song.Track) ~= "string" or not manifest[song.Track] then return false end
	stopPreview()
	local token = previewToken
	local currentGeneration = generation
	local descriptor = table.clone(song)
	descriptor.PlaybackSpeed = playbackRate(descriptor)
	beginPreparation(descriptor.Track)
	local prepareToken = preparationToken
	script:SetAttribute("PreviewTrack", descriptor.Track)
	script:SetAttribute("PreviewLoading", true)
	script:SetAttribute("PreviewError", nil)
	task.spawn(function()
		local deadline = os.clock() + Config.PrepareTimeout
		while active and not destroyed and generation == currentGeneration and token == previewToken
			and preparationToken == prepareToken and os.clock() < deadline do
			if prepare(descriptor.Track) then
				if token ~= previewToken or not active or destroyed or generation ~= currentGeneration then return end
				clearPreparation()
				preview = {Song = descriptor, Start = workspace:GetServerTimeNow(), Preview = true}
				script:SetAttribute("PreviewLoading", false)
				script:SetAttribute("PreviewProgress", 1)
				return
			end
			task.wait(0.05)
		end
		if token == previewToken and generation == currentGeneration then
			stopPreview()
			script:SetAttribute("PreviewError", "Audio preview could not be prepared")
		end
	end)
	return true
end
function Controller.StopPreview()
	stopPreview()
end
function Controller.CancelPreparation()
	clearPreparation()
end
-- Returns the actual selected audio epoch so optional visuals share its loop and playback rate.
function Controller.GetPlaybackClock()
	local source = selected
	if not active or destroyed or not source then return nil end
	local track = manifest[source.Song.Track]
	if not track then return nil end
	local rate = playbackRate(source.Song)
	local length = track.Frames / track.FPS
	return {Track = source.Song.Track, StartTime = source.Start, Rate = rate, Character = source.Character,
		Preview = source.Preview == true, Own = selectedMix ~= nil and selectedMix.Own,
		Duration = length, Position = math.max(0, workspace:GetServerTimeNow() - source.Start) * rate % length,
		Video = if type(source.Song.Video) == "string" then source.Song.Video else nil, State = playbackState}
end
function Controller.GetStatus()
	local liveRenderer = if initialized and renderer then renderer else nil
	return {CacheBytes = cache.Bytes, Ready = active and not destroyed and liveRenderer ~= nil and liveRenderer:IsReady(),
		Voices = if liveRenderer then #liveRenderer.Voices else 0,
		Rms = if liveRenderer then liveRenderer.Analyzer.RmsLevel else 0,
		Frames = if liveRenderer then liveRenderer.Rendered else 0, Underruns = underruns,
		Track = if selected then selected.Song.Track else "", MaxRenderMs = if liveRenderer then liveRenderer.MaxMs else 0,
		AverageRenderMs = if liveRenderer then liveRenderer.AverageMs else 0,
		ActiveVoiceLimit = if liveRenderer then liveRenderer.VoiceLimit else 0,
		SelectionSwitches = if liveRenderer then liveRenderer.SelectionSwitches else 0,
		SelectionScans = if liveRenderer then liveRenderer.SelectionScans else 0,
		SelectionAdaptive = liveRenderer ~= nil and liveRenderer.Selection.Adaptive,
		RecoveredVoices = if liveRenderer then liveRenderer.RecoveredVoices or 0 else 0,
		UnavailableVoiceFrames = if liveRenderer then liveRenderer.UnavailableVoiceFrames or 0 else 0,
		LastError = script:GetAttribute("LastError"),
		PhaseCorrectedFrames = if liveRenderer then liveRenderer.PhaseCorrectedFrames or 0 else 0,
		SourceGain = outputGain, SourceDistance = if selectedMix then selectedMix.Distance else 0,
		SourceOwn = if selectedMix then selectedMix.Own else false,
		LoadingTrack = script:GetAttribute("LoadingTrack"), BufferedSeconds = script:GetAttribute("BufferedSeconds"),
		DownloadingTrack = if loading then loading.Track else "", QueuedSegments = #queue,
		PreviewTrack = script:GetAttribute("PreviewTrack"), PreviewLoading = script:GetAttribute("PreviewLoading"),
		PreviewProgress = script:GetAttribute("PreviewProgress"), PreviewError = script:GetAttribute("PreviewError"),
		State = playbackState, Buffering = buffering, BufferedAheadSeconds = bufferedAhead, RecoveryCount = recoveries}
end
function Controller.Destroy()
	if not initialized then return end
	generation += 1; active = false; destroyed = true; initialized = false
	clearPreparation(); stopPreview()
	if loading and request then request:FireServer("Cancel", loading.Id) end
	if scope then scope:Destroy(); scope = nil end
	for player, owner in playerScopes do owner:Destroy(); playerScopes[player] = nil end
	if validator then validator:Destroy() end
	if receiver then receiver:Destroy() end
	if renderer then renderer:Destroy() end
	receiver = nil; validator = nil :: any; renderer = nil :: any
	cache:Destroy()
	loading = nil; selected = nil; selectedMix = nil; outputGain = 0
	handoffActive = false; handoffTarget = nil
	buffering = false; bufferedAhead = 0; playbackState = "Idle"
	script:SetAttribute("SourceGain", 0)
	script:SetAttribute("Track", "")
	script:SetAttribute("Ready", false)
	script:SetAttribute("SourceOwn", false)
	script:SetAttribute("SourceDistance", 0)
	script:SetAttribute("LoadingTrack", "")
	script:SetAttribute("BufferedSeconds", 0)
	script:SetAttribute("State", playbackState)
	script:SetAttribute("Buffering", false)
	script:SetAttribute("BufferedAheadSeconds", 0)
	script:SetAttribute("DownloadProgress", 0)
	script:SetAttribute("SelectionSwitches", 0)
	script:SetAttribute("SelectionScans", 0)
	script:SetAttribute("SelectionAdaptive", false)
	table.clear(queue); table.clear(queued); table.clear(sources); table.clear(manifest); table.clear(retries); table.clear(retryAt)
end
return Controller

