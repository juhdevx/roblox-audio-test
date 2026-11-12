--!strict
-- Expands trusted track entries into immutable segment URLs and public metadata.
local Tracks = require(script.Parent.SpectralTracks)
local Catalog = {Entries = {}, Manifest = {}}
local allowed: {[string]: boolean} = {}
for name, track in Tracks do
	assert(name:match("^[%w_]+$") and #name <= 40, "Invalid spectral track name")
	assert(track.Segments == math.ceil(track.Frames / track.SegmentFrames), "Invalid spectral segment count")
	local encoding, noiseBands = track.Encoding or 1, track.NoiseBands or 0
	assert((encoding == 1 and noiseBands == 0) or
		(encoding == 3 and noiseBands % 1 == 0 and noiseBands >= 1 and noiseBands <= 16), "Invalid spectral encoding")
	local mixGain = track.MixGain or 1
	assert(type(mixGain) == "number" and mixGain == mixGain and mixGain >= 0.5 and mixGain <= 3,
		"Spectral MixGain must be finite and between 0.5 and 3")
	Catalog.Manifest[name] = {Frames = track.Frames, FPS = track.FPS, Voices = track.Voices,
		SegmentFrames = track.SegmentFrames, Segments = track.Segments, Preload = track.Preload == true,
		Encoding = encoding, NoiseBands = noiseBands, MixGain = mixGain}
	for part = 0, track.Segments - 1 do
		local id = `{name}_{string.format("%03d", part)}`
		local url = `{track.BaseUrl}/{id}.spc`
		assert(url:match("^https://raw%.githubusercontent%.com/[%w%._%-%/]+$"), "Untrusted spectral URL")
		Catalog.Entries[id] = {Url = url}
		allowed[url] = true
	end
end
function Catalog.IsAllowed(url: string): boolean return allowed[url] == true end
return Catalog

