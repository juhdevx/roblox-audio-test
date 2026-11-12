--!strict
-- Expands trusted video definitions into exact allowlisted URLs and public playback metadata.
local Tracks = require(script.Parent.VideoTracks)
local Protocol = require(game:GetService("ReplicatedStorage").Shared.AudioSequence.Protocol)
local Metadata = require(game:GetService("ReplicatedStorage").Shared.VideoSequence.Metadata)
local Catalog = {}
local function trustedBase(url: any): boolean
	if type(url) ~= "string" or #url > 512 then return false end
	local revision, path = url:match("^https://raw%.githubusercontent%.com/juhdevx/roblox%-audio%-test/([%w]+)/([%w_%-/]+)$")
	if not revision or not path or path:find("//", 1, true) or path:sub(-1) == "/" then return false end
	return revision == "main" or (#revision == 40 and revision:match("^[a-f0-9]+$") ~= nil)
end
function Catalog.Build(tracks: any): any
	local entries: {[string]: any} = {}
	local manifest: {[string]: any} = {}
	local allowed: {[string]: boolean} = {}
	for name, track in tracks do
		assert(Protocol.Id(name) and #name <= 40 and name:match("^[%w_]+$"), "Invalid video track name")
		assert(type(track) == "table" and trustedBase(track.BaseUrl), "Untrusted video source")
		assert(Metadata.Valid(track), "Invalid video dimensions, timing or encoding")
		assert(track.Title == nil or (type(track.Title) == "string" and #track.Title <= 80), "Invalid video title")
		local public = table.freeze({
			Width = track.Width, Height = track.Height, FPS = track.FPS, Frames = track.Frames,
			SegmentFrames = track.SegmentFrames, Segments = track.Segments, Encoding = track.Encoding,
			AudioTrack = track.AudioTrack, Preload = track.Preload == true, Title = track.Title or name,
		})
		manifest[name] = public
		for part = 0, track.Segments - 1 do
			local id = `{name}_{string.format("%04d", part)}`
			local url = `{track.BaseUrl}/{id}.rvf`
			entries[id] = table.freeze({Url = url, Track = name, Part = part})
			allowed[url] = true
		end
	end
	return table.freeze({
		Entries = table.freeze(entries), Manifest = table.freeze(manifest),
		IsAllowed = function(url: string): boolean return allowed[url] == true end,
	})
end
local built = Catalog.Build(Tracks)
Catalog.Entries = built.Entries
Catalog.Manifest = built.Manifest
Catalog.IsAllowed = built.IsAllowed
return table.freeze(Catalog)

