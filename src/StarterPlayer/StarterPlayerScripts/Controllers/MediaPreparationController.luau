--!strict
-- Prepares both streams before starting a local preview or requesting a synchronized emote.
local Controller = {}
local audio: any
local video: any
local alive = false
local generation = 0
local previewToken = 0
local prepareToken = 0
local preparationOwner = ""
local function validId(value: any): boolean
	return type(value) == "string" and #value >= 1 and #value <= 40 and value:match("^[%w_]+$") ~= nil
end
local function validSong(song: any): boolean
	return type(song) == "table" and song.Backend == "Spectral" and validId(song.Track)
		and (song.Video == nil or validId(song.Video))
end

local function previewStatus(track: string, preparing: boolean, failure: string?)
	script:SetAttribute("PreviewTrack", track)
	script:SetAttribute("Preparing", preparing)
	script:SetAttribute("PreviewError", failure)
	if not preparing then script:SetAttribute("Progress", 0) end
end

local function prepareSong(song: any, valid: () -> boolean): boolean
	if not valid() then return false end
	local selectedAudio, selectedVideo = audio, video
	local audioDone, videoDone = false, song.Video == nil
	local audioReady, videoReady = false, song.Video == nil
	task.spawn(function()
		if not valid() then audioDone = true; return end
		local ok, ready = pcall(selectedAudio.EnsureReady, song.Track)
		audioReady = ok and ready == true; audioDone = true
	end)
	if song.Video ~= nil then
		task.spawn(function()
			if not valid() then videoDone = true; return end
			local ok, ready = pcall(selectedVideo.EnsureReady, song.Video)
			local statusOk, status = pcall(selectedVideo.GetStatus)
			local unsupported = statusOk and type(status) == "table"
				and type(status.CapabilityError) == "string" and status.CapabilityError ~= ""
			videoReady = (ok and ready == true) or unsupported
			videoDone = true
		end)
	end
	local deadline = os.clock() + 36
	while valid() and os.clock() < deadline and not (audioDone and videoDone) do
		if script:GetAttribute("Preparing") then
			local audioOk, audioStatus = pcall(selectedAudio.GetStatus)
			local videoOk, videoStatus = pcall(selectedVideo.GetStatus)
			if not audioOk or type(audioStatus) ~= "table" then audioStatus = {} end
			if not videoOk or type(videoStatus) ~= "table" then videoStatus = {} end
			local audioProgress = if audioDone and audioReady then 1 else math.clamp((audioStatus.BufferedSeconds or 0) / 4, 0, 0.95)
			local videoProgress = if song.Video == nil or (videoDone and videoReady) then 1
				else math.clamp(videoStatus.PrepareProgress or 0, 0, 0.95)
			script:SetAttribute("Progress", math.min(audioProgress, videoProgress))
		end
		task.wait(0.03)
	end
	return valid() and audioDone and videoDone and audioReady and videoReady
end

local function failureMessage(song: any): string
	local audioOk, audioStatus = pcall(audio.GetStatus)
	local videoOk, videoStatus = pcall(video.GetStatus)
	if not audioOk or type(audioStatus) ~= "table" then audioStatus = {} end
	if not videoOk or type(videoStatus) ~= "table" then videoStatus = {} end
	if type(audioStatus.LastError) == "string" and audioStatus.LastError ~= "" then
		return "Could not load the audio. Please try again."
	end
	if song.Video and type(videoStatus.LastError) == "string" and videoStatus.LastError ~= "" then
		return "Could not load the video. Please try again."
	end
	return "Loading timed out. Please try again."
end

function Controller.Init(dependencies: any)
	if alive then Controller.Destroy() end
	generation += 1; alive = true
	audio = dependencies.SpectralAudioController
	video = dependencies.VideoSequenceController
	assert(audio and video, "Missing media preparation dependencies")
	previewStatus("", false, nil)
end

function Controller.Start() end

function Controller.StopPreview()
	previewToken += 1
	if audio then audio.StopPreview() end
	-- Hiding a catalog preview must not cancel an emote requested by its wheel button.
	if preparationOwner == "Equip" then return end
	preparationOwner = ""
	previewStatus("", false, nil)
	if audio and audio.CancelPreparation then audio.CancelPreparation() end
	if video then video.CancelPreparation() end
end

-- Returns acceptance immediately; opening audio and video happens only after both buffers are ready.
function Controller.Preview(song: any): boolean
	if not alive or not validSong(song) then return false end
	prepareToken += 1
	preparationOwner = ""
	Controller.StopPreview()
	preparationOwner = "Preview"
	if song.Video == nil then return audio.Preview(song) end
	local descriptor = table.clone(song)
	local token, currentGeneration = previewToken, generation
	previewStatus(descriptor.Track, true, nil)
	task.spawn(function()
		local function valid(): boolean return alive and token == previewToken and currentGeneration == generation end
		local ready = prepareSong(descriptor, valid)
		if not valid() then return end
		if ready then
			local accepted = audio.Preview(descriptor)
			previewStatus("", false, if accepted then nil else failureMessage(descriptor))
		else previewStatus("", false, failureMessage(descriptor)) end
	end)
	return true
end

function Controller.EnsureReady(song: any): boolean
	if not alive or not validSong(song) then return false end
	Controller.CancelPreparation()
	Controller.StopPreview()
	prepareToken += 1
	preparationOwner = "Equip"
	local token, currentGeneration = prepareToken, generation
	local descriptor = table.clone(song)
	previewStatus(descriptor.Track, true, nil)
	local function valid(): boolean
		return alive and token == prepareToken and currentGeneration == generation
	end
	local ready = prepareSong(descriptor, valid)
	if valid() then
		preparationOwner = ""
		previewStatus("", false, if ready then nil else failureMessage(descriptor))
	end
	return ready
end

function Controller.CancelPreparation()
	prepareToken += 1
	previewToken += 1
	preparationOwner = ""
	previewStatus("", false, nil)
	if video then video.CancelPreparation() end
	if audio and audio.CancelPreparation then audio.CancelPreparation() end
end

function Controller.GetStatus()
	return {Preparing = script:GetAttribute("Preparing") == true,
		Owner = preparationOwner,
		PreviewTrack = script:GetAttribute("PreviewTrack"), PreviewError = script:GetAttribute("PreviewError"),
		Progress = script:GetAttribute("Progress") or 0}
end

function Controller.Destroy()
	alive = false; generation += 1; prepareToken += 1
	preparationOwner = ""
	Controller.StopPreview()
end

return Controller

