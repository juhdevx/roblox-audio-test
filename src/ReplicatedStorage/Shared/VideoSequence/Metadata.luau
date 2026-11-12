--!strict
-- Shares allocation and timing bounds between trusted catalogs and untrusted client manifests.
local Metadata = {}
local function integer(value: any, low: number, high: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= low and value <= high
end
function Metadata.Valid(track: any): boolean
	if type(track) ~= "table" then return false end
	local modern = track.Encoding == 2
	if not modern and track.Encoding ~= 1 then return false end
	local maxSize, maxPixels, maxFPS = if modern then 1024 else 256, if modern then 589824 else 36864, if modern then 30 else 20
	return integer(track.Width, 16, maxSize) and integer(track.Height, 16, maxSize)
		and track.Width * track.Height <= maxPixels and integer(track.FPS, 4, maxFPS)
		and integer(track.Frames, 1, track.FPS * 3600)
		and integer(track.SegmentFrames, 1, track.FPS * 4) and integer(track.Segments, 1, 9999)
		and track.Segments == math.ceil(track.Frames / track.SegmentFrames)
		and type(track.AudioTrack) == "string" and #track.AudioTrack >= 1 and #track.AudioTrack <= 40
		and track.AudioTrack:match("^[%w_]+$") ~= nil
end
return table.freeze(Metadata)
