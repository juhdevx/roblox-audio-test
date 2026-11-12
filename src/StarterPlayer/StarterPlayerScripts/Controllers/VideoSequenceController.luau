--!strict
-- Streams bounded video segments and follows the selected emote's shared audio clock.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.VideoSequence.Config)
local Format = require(Shared.VideoSequence.Format)
local Metadata = require(Shared.VideoSequence.Metadata)
local Protocol = require(Shared.AudioSequence.Protocol)
local LRU = require(Shared.AudioSequence.LRU)
local Scope = require(Shared.Utils.Scope)
local Receiver = require(script.Parent.Parent.AudioSequence.Receiver)
local Renderer = require(script.Parent.Parent.VideoSequence.Renderer)

type Track = {
	Width: number, Height: number, FPS: number, Frames: number,
	SegmentFrames: number, Segments: number, AudioTrack: string,
	Encoding: number?, Title: string?, Preload: boolean?,
}
type Load = {Id: string, Track: string, Part: number, Started: number, RetryAt: number,
	Data: buffer?, Header: any?, Validation: any?}
type Clock = {Track: string, StartTime: number, Rate: number, Preview: boolean?, Own: boolean?, Character: Model?,
	Duration: number?, Position: number?, Video: string?, State: string?}

local Controller = {}
local manifest: {[string]: Track} = {}
local byAudio: {[string]: string} = {}
local cache = LRU.new(Config.ClientCacheBytes)
local queue: {{Id: string, Track: string, Part: number}} = {}
local queued: {[string]: boolean} = {}
local retries: {[string]: number} = {}
local retryAt: {[string]: number} = {}
local scope: any = nil
local receiver: any = nil
local renderer: Renderer.Display? = nil
local audio: any = nil
local requestRemote: RemoteEvent? = nil
local dataRemote: RemoteEvent? = nil
local loading: Load? = nil
local initialized = false
local active = false
local generation = 0
local nextManifest = 0
local preparing = ""
local preparationDeadline = 0
local preparationToken = 0
local selected = ""
local selectedPart = 0
local sourceKey = ""
local decoder: any = nil
local decoderId = ""
local lastFrame = -1
local decodeTargetFrame = -1
local displayedFrame = -1
local displayedSourceKey = ""
local displayedFrames = 0
local skippedFrames = 0
local recoveredBuffers = 0
local buffering = false
local bufferedAhead = 0
local drift = 0
local decodeMs = 0
local maxDecodeMs = 0
local state = "Idle"
local lastError: string? = nil
local lastStatus = 0
local progress = 0
local position = 0
local duration = 0
local allocationId = ""

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function idFor(name: string, part: number): string
	return `{name}_{string.format("%04d", part)}`
end

local function dataFor(name: string, part: number): any
	return cache:Get(idFor(name, part), os.clock())
end

local function discardDecoder()
	if decoder then decoder:Destroy(); decoder = nil end
	decoderId = ""
	lastFrame = -1
	decodeTargetFrame = -1
end

local function cancelLoading()
	if loading and requestRemote then requestRemote:FireServer("Cancel", loading.Id) end
	loading = nil
	if receiver then receiver:Destroy() end
end

local function startupParts(track: Track): number
	return math.min(track.Segments, math.max(1, math.ceil(Config.StartupSeconds * track.FPS / track.SegmentFrames)))
end

local function prefetchParts(track: Track, rate: number): number
	return math.min(track.Segments, math.max(2, math.ceil(Config.PrefetchSeconds * rate * track.FPS / track.SegmentFrames)))
end

local function enqueue(name: string, part: number)
	local track = manifest[name]
	if not track or part < 0 or part >= track.Segments then return end
	local id = idFor(name, part)
	if dataFor(name, part) or queued[id] or (loading and loading.Id == id) then return end
	queued[id] = true
	table.insert(queue, {Id = id, Track = name, Part = part})
end

local function queueRank(name: string, part: number): number?
	local track = manifest[name]
	if not track then return nil end
	if selected == name then
		local ahead = (part - selectedPart) % track.Segments
		if ahead < prefetchParts(track, 2) then
			return if ahead <= 1 then ahead else 20 + ahead
		end
	end
	if preparing == name and part < startupParts(track) then
		return 5 + part / startupParts(track)
	end
	return nil
end

local function nextQueued(now: number): number?
	for index = #queue, 1, -1 do
		local entry = queue[index]
		if not queueRank(entry.Track, entry.Part) or dataFor(entry.Track, entry.Part) then
			queued[entry.Id] = nil
			table.remove(queue, index)
		end
	end
	local best: number? = nil
	local bestRank = math.huge
	for index, entry in queue do
		local rank = queueRank(entry.Track, entry.Part)
		if rank and rank < bestRank and now >= (retryAt[entry.Id] or 0) then
			best = index
			bestRank = rank
		end
	end
	return best
end

local function fail(message: string)
	lastError = message
	local previous = loading
	cancelLoading()
	if previous then
		local attempts = (retries[previous.Id] or 0) + 1
		retries[previous.Id] = attempts
		retryAt[previous.Id] = os.clock() + math.min(20, 2 ^ math.min(attempts, 5))
		enqueue(previous.Track, previous.Part)
		if attempts == 1 or attempts % 3 == 0 then warn(`[VideoSequence] {message}`) end
	end
end

local function validManifest(raw: any): {[string]: Track}
	local accepted: {[string]: Track} = {}
	if type(raw) ~= "table" then return accepted end
	local count = 0
	for name, track in raw do
		if count >= 64 then break end
		if not Protocol.Id(name) or not Metadata.Valid(track) then continue end
		accepted[name] = {
			Width = track.Width, Height = track.Height, FPS = track.FPS, Frames = track.Frames,
			SegmentFrames = track.SegmentFrames, Segments = track.Segments, AudioTrack = track.AudioTrack,
			Encoding = track.Encoding, Preload = track.Preload == true,
			Title = if type(track.Title) == "string" then string.sub(track.Title, 1, 80) else name,
		}
		count += 1
	end
	return accepted
end

local function validateDownload()
	local load = loading
	if not load or not load.Data or not load.Validation then return end
	local started = os.clock()
	for _ = 1, 64 do
		local done, reason = Format.Step(load.Validation)
		if reason then fail(tostring(reason)); return end
		if done then
			cache:Put(load.Id, {Data = load.Data, Header = load.Validation.Header}, buffer.len(load.Data), math.huge)
			retries[load.Id] = nil
			retryAt[load.Id] = nil
			loading = nil
			lastError = nil
			return
		end
		if (os.clock() - started) * 1000 >= Config.ValidateBudgetMs then return end
	end
end

local function bufferedSeconds(name: string, frame: number): number
	local track = manifest[name]
	if not track then return 0 end
	local frames = 0
	local part = math.floor(frame / track.SegmentFrames)
	for ahead = 0, prefetchParts(track, 2) - 1 do
		local currentPart = (part + ahead) % track.Segments
		local entry = dataFor(name, currentPart)
		if not entry then break end
		local available = entry.Header.FrameCount
		if ahead == 0 then available -= frame - entry.Header.FirstFrame end
		frames += math.max(0, available)
	end
	return math.min(track.Frames, frames) / track.FPS
end

local function allocate(name: string, track: Track): boolean
	local display = renderer
	if not display then return false end
	if allocationId ~= name then
		allocationId = name
		return display:SetVideo(track.Width, track.Height, track.Title or name)
	end
	return display.Editable ~= nil and display.CapabilityError == nil
end

local function prepare(name: string): boolean
	local track = manifest[name]
	if not active or not track then progress = 0; return false end
	-- Warming another catalog entry must not replace the image that is currently playing.
	if (selected == "" or selected == name) and not allocate(name, track) then return false end
	local count = startupParts(track)
	local cached = 0
	for part = 0, count - 1 do
		enqueue(name, part)
		if dataFor(name, part) then cached += 1 end
	end
	progress = cached / count
	if loading and loading.Track == name and loading.Part < count and receiver.Current then
		progress += receiver.Current.Received / receiver.Current.Header.Count / count
	end
	progress = math.clamp(progress, 0, 1)
	if cached == count then
		local first = dataFor(name, 0)
		if not first or not Format.Prepare(track.Encoding or 1, Config.DecodeBudgetMs, first.Header) then return false end
	end
	return cached == count
end

local function beginPreparation(name: string)
	if preparing ~= name then preparationToken += 1 end
	preparing = name
	preparationDeadline = os.clock() + Config.PrepareTimeout
end

local function clearPreparation()
	preparing = ""
	preparationDeadline = 0
	preparationToken += 1
end

local function currentClock(): Clock?
	if not audio or type(audio.GetPlaybackClock) ~= "function" then return nil end
	local clock = audio.GetPlaybackClock()
	if type(clock) ~= "table" or type(clock.Track) ~= "string"
		or not finite(clock.StartTime) or not finite(clock.Rate) then return nil end
	return clock
end

local function updatePlayback()
	local display = renderer
	if not display then return end
	local clock = currentClock()
	local name = if clock then (if Protocol.Id(clock.Video) then clock.Video else byAudio[clock.Track]) else nil
	local track = if name then manifest[name] else nil
	if not clock or not name or not track then
		if selected ~= "" then
			discardDecoder()
			selected = ""
			sourceKey = ""
			buffering = false
			displayedFrame = -1
			bufferedAhead = 0
			drift = 0
		end
		state = if preparing ~= "" then "Preparing" else "Idle"
		display:SetVisible(false)
		return
	end
	local nextKey = `{name}:{clock.StartTime}:{clock.Rate}`
	if sourceKey ~= nextKey then
		discardDecoder()
		selected = name
		sourceKey = nextKey
		displayedFrame = -1
		displayedSourceKey = ""
		buffering = false
		position = 0
		allocate(name, track)
		display:SetVisible(true, true)
	else
		display:SetVisible(true)
	end
	display:SetSource(clock, name)
	if display.CapabilityError then state = "Unavailable"; return end
	local rate = math.clamp(clock.Rate, 0.25, 2)
	duration = if finite(clock.Duration) and (clock.Duration :: number) > 0
		then clock.Duration :: number else track.Frames / track.FPS
	position = if finite(clock.Position) then math.clamp(clock.Position :: number, 0, duration)
		else (math.max(0, workspace:GetServerTimeNow() - clock.StartTime) * rate) % duration
	local targetFrame = math.clamp(math.floor(position * track.FPS), 0, track.Frames - 1)
	selectedPart = math.floor(targetFrame / track.SegmentFrames)
	for ahead = 0, prefetchParts(track, rate) - 1 do
		enqueue(name, (selectedPart + ahead) % track.Segments)
	end
	bufferedAhead = bufferedSeconds(name, targetFrame) / rate
	local id = idFor(name, selectedPart)
	local entry = dataFor(name, selectedPart)
	if not entry then
		buffering = true
		state = "Buffering"
		drift = if displayedFrame >= 0 then math.max(0, position - displayedFrame / track.FPS) else 0
		return
	end
	if buffering then recoveredBuffers += 1 end
	buffering = false
	state = "Playing"
	if decoderId ~= id then
		discardDecoder()
		local ok, created = pcall(Format.Decoder.new, entry.Data)
		if not ok or not created then
			lastError = `Unable to decode {id}`
			cache:Remove(id)
			retryAt[id] = os.clock() + 4
			buffering = true
			state = "Buffering"
			return
		end
		decoder = created
		decoderId = id
	end
	-- A loop or backward seek supersedes unfinished work from the previous position.
	if decodeTargetFrame >= 0 and targetFrame < decodeTargetFrame then decodeTargetFrame = -1 end
	if targetFrame == lastFrame and displayedSourceKey == sourceKey then
		drift = math.abs(position - displayedFrame / track.FPS)
		return
	end
	-- Finish an incremental image before following a newer audio frame. Changing the
	-- target every tick can repeatedly discard partial color conversion on slow devices.
	if decodeTargetFrame < 0 then decodeTargetFrame = targetFrame end
	local frameToDecode = decodeTargetFrame
	local started = os.clock()
	local ok, pixels, ready = pcall(function()
		return decoder:Step(frameToDecode - entry.Header.FirstFrame, Config.DecodeBudgetMs)
	end)
	decodeMs = (os.clock() - started) * 1000
	maxDecodeMs = math.max(maxDecodeMs, decodeMs)
	if not ok then
		lastError = tostring(pixels)
		cache:Remove(id)
		discardDecoder()
		buffering = true
		state = "Buffering"
		return
	end
	if ready and pixels then
		decodeTargetFrame = -1
		if display:Write(pixels) then
			if displayedSourceKey == sourceKey and displayedFrame >= 0 and frameToDecode > displayedFrame + 1 then
				skippedFrames += frameToDecode - displayedFrame - 1
			end
			displayedFrame = frameToDecode
			displayedSourceKey = sourceKey
			displayedFrames += 1
			lastFrame = frameToDecode
		end
	else
		state = "CatchingUp"
	end
	drift = if displayedFrame >= 0 then math.abs(position - displayedFrame / track.FPS) else 0
end

local function statusAttributes()
	local display = renderer
	script:SetAttribute("State", state)
	script:SetAttribute("Ready", active and display ~= nil and display.Editable ~= nil and display.CapabilityError == nil)
	script:SetAttribute("Track", selected)
	script:SetAttribute("LoadingTrack", preparing)
	script:SetAttribute("PrepareProgress", progress)
	script:SetAttribute("CacheBytes", cache.Bytes)
	script:SetAttribute("DisplayedFrames", displayedFrames)
	script:SetAttribute("SkippedFrames", skippedFrames)
	script:SetAttribute("Buffering", buffering)
	script:SetAttribute("BufferedSeconds", bufferedAhead)
	script:SetAttribute("RecoveryCount", recoveredBuffers)
	script:SetAttribute("Position", position)
	script:SetAttribute("DriftSeconds", drift)
	script:SetAttribute("DecodeMs", decodeMs)
	script:SetAttribute("MaxDecodeMs", maxDecodeMs)
	script:SetAttribute("CapabilityError", if display then display.CapabilityError else nil)
	script:SetAttribute("LastError", lastError)
	script:SetAttribute("DownloadingPart", if loading then loading.Part else -1)
	if display then display:SetStatus(state, position, duration, progress) end
end

function Controller.Init(dependencies: any)
	if initialized then Controller.Destroy() end
	generation += 1
	local token = generation
	initialized = true
	active = false
	cache = LRU.new(Config.ClientCacheBytes)
	manifest = {}
	byAudio = {}
	preparing = ""
	selected = ""
	sourceKey = ""
	allocationId = ""
	lastError = nil
	buffering = false
	state = "Idle"
	displayedFrames = 0
	skippedFrames = 0
	recoveredBuffers = 0
	bufferedAhead = 0
	position = 0
	duration = 0
	drift = 0
	decodeMs = 0
	maxDecodeMs = 0
	lastStatus = 0
	progress = 0
	nextManifest = 0
	audio = if type(dependencies) == "table" and dependencies.SpectralAudioController
		then dependencies.SpectralAudioController else require(script.Parent.SpectralAudioController)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if generation ~= token then return end
	assert(remotes, "Missing Remotes")
	local videoRemotes = remotes:WaitForChild("VideoSequence", 15)
	if generation ~= token then return end
	assert(videoRemotes, "Missing VideoSequence remotes")
	requestRemote = videoRemotes:WaitForChild("Request", 10) :: RemoteEvent
	if generation ~= token then return end
	dataRemote = videoRemotes:WaitForChild("Data", 10) :: RemoteEvent
	if generation ~= token then return end
	assert(requestRemote and dataRemote, "Missing video transport")
	scope = Scope.new()
	renderer = Renderer.new()
	local function current(): boolean return initialized and generation == token end
	receiver = Receiver.new(function(action, a, b)
		if current() and requestRemote then requestRemote:FireServer(action, a, b) end
	end, function(header, data)
		if not current() then return end
		local load = loading
		if not load or header.Id ~= load.Id then return end
		local job, reason = Format.Begin(data)
		if not job then fail(tostring(reason)); return end
		local details = job.Header
		local track = manifest[load.Track]
		if not track or details.Checksum ~= header.Checksum or details.Width ~= track.Width
			or details.Height ~= track.Height or details.FPS ~= track.FPS or details.TotalFrames ~= track.Frames
			or details.Encoding ~= track.Encoding
			or details.FirstFrame ~= load.Part * track.SegmentFrames or details.SegmentFrames ~= track.SegmentFrames
			or details.FrameCount ~= math.min(track.SegmentFrames, track.Frames - details.FirstFrame) then
			fail("Video segment does not match its manifest")
			return
		end
		load.Data = data
		load.Header = header
		load.Validation = job
	end, function(message)
		if current() then fail(message) end
	end)
	statusAttributes()
end

function Controller.Start()
	if active or not initialized or not scope or not renderer or not requestRemote or not dataRemote then return end
	active = true
	local token = generation
	scope:Connect(dataRemote.OnClientEvent, function(action: string, a: any, b: any, c: any)
		if generation ~= token or not active then return end
		if action == "Manifest" then
			manifest = validManifest(a)
			table.clear(byAudio)
			local names = {}
			for name in manifest do table.insert(names, name) end
			table.sort(names)
			for _, name in names do
				if not byAudio[manifest[name].AudioTrack] then byAudio[manifest[name].AudioTrack] = name end
			end
		elseif action == "Header" and loading and Protocol.Header(a) and a.Id == loading.Id then
			if a.Bytes > Config.MaxSegmentBytes then fail("Video segment exceeds its memory budget"); return end
			receiver:Header(a)
		elseif action == "Chunk" then
			receiver:Chunk(a, b, c)
		elseif action == "Error" and loading and a == loading.Id then
			fail(tostring(b))
		end
	end)
	scope:Connect(RunService.Heartbeat, function(dt: number)
		if generation ~= token or not active then return end
		receiver:Step()
		validateDownload()
		local now = os.clock()
		if next(manifest) == nil and now >= nextManifest and requestRemote then
			requestRemote:FireServer("Manifest")
			nextManifest = now + 3
		end
		if preparing ~= "" then
			if now >= preparationDeadline then clearPreparation() else prepare(preparing) end
		end
		updatePlayback()
		if loading and not queueRank(loading.Track, loading.Part) then cancelLoading() end
		local nextIndex = nextQueued(now)
		if not loading and nextIndex and requestRemote then
			local entry = table.remove(queue, nextIndex)
			queued[entry.Id] = nil
			loading = {Id = entry.Id, Track = entry.Track, Part = entry.Part, Started = now, RetryAt = now + 3}
			receiver:Expect(entry.Id)
			requestRemote:FireServer("Load", entry.Id)
		elseif loading and not receiver.Current and not loading.Validation and now >= loading.RetryAt then
			if now - loading.Started > Config.TransferSeconds then fail("Video download timed out")
			elseif requestRemote then
				requestRemote:FireServer("Load", loading.Id)
				loading.RetryAt = now + 3
			end
		end
		lastStatus += dt
		if lastStatus >= 1 / Config.StatusHz then lastStatus = 0; statusAttributes() end
	end)
	requestRemote:FireServer("Manifest")
	nextManifest = os.clock() + 3
end

-- Warms the first bounded segments while the catalog remains interactive.
function Controller.Prepare(name: string): boolean
	if not active or not Protocol.Id(name) then return false end
	beginPreparation(name)
	return prepare(name)
end

-- Yields until the startup buffer and image allocation are ready, or the request is superseded.
function Controller.EnsureReady(name: string): boolean
	if not active or not Protocol.Id(name) then return false end
	beginPreparation(name)
	local token, prepareToken = generation, preparationToken
	local deadline = os.clock() + Config.PrepareTimeout
	while active and generation == token and preparationToken == prepareToken and os.clock() < deadline do
		if prepare(name) then clearPreparation(); return true end
		if renderer and renderer.CapabilityError then clearPreparation(); return false end
		task.wait(0.05)
	end
	if generation == token and preparationToken == prepareToken then clearPreparation() end
	return false
end

function Controller.CancelPrepare()
	clearPreparation()
end

function Controller.CancelPreparation()
	clearPreparation()
end

function Controller.GetStatus()
	return {
		Ready = active and renderer ~= nil and renderer.Editable ~= nil and renderer.CapabilityError == nil,
		State = state, Track = selected, LoadingTrack = preparing, PrepareProgress = progress,
		CacheBytes = cache.Bytes, DisplayedFrames = displayedFrames, SkippedFrames = skippedFrames,
		Buffering = buffering, BufferedSeconds = bufferedAhead, RecoveryCount = recoveredBuffers,
		Position = position, DriftSeconds = drift, DecodeMs = decodeMs, MaxDecodeMs = maxDecodeMs,
		CapabilityError = if renderer then renderer.CapabilityError else nil, LastError = lastError,
		DownloadingPart = if loading then loading.Part else -1,
		Hidden = if renderer then renderer.Hidden else false,
		DisplayedFrame = displayedFrame, DecoderFrame = if decoder then decoder.Current else -1,
		WriteMs = if renderer then renderer.LastWriteMs else 0,
	}
end

function Controller.Destroy()
	if not initialized then return end
	active = false
	initialized = false
	generation += 1
	clearPreparation()
	cancelLoading()
	discardDecoder()
	if scope then scope:Destroy(); scope = nil end
	if renderer then renderer:Destroy(); renderer = nil end
	cache:Destroy()
	requestRemote = nil
	dataRemote = nil
	audio = nil
	selected = ""
	sourceKey = ""
	buffering = false
	bufferedAhead = 0
	state = "Idle"
	table.clear(manifest)
	table.clear(byAudio)
	table.clear(queue)
	table.clear(queued)
	table.clear(retries)
	table.clear(retryAt)
	statusAttributes()
end

return Controller

