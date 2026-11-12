--!strict
-- Validates independently seekable RVF1 tile segments and decodes them to RGBA.
local Format = {}
Format.MAGIC = 0x31465652
Format.HEADER_BYTES = 64
Format.MAX_BYTES = 2 * 1024 * 1024
local PAYLOAD_BYTES = {1, 4, 8, 16}

export type Header = {
	Width: number, Height: number, FPS: number, FrameCount: number, FirstFrame: number,
	TotalFrames: number, SegmentFrames: number, PaletteCount: number, Encoding: number,
	TileSize: number, Duration: number, Bytes: number, Checksum: number,
}
export type Job = {
	Data: buffer, Header: Header, Position: number, A: number, B: number,
	Frame: number, Offset: number, Phase: number,
}

function Format.Header(data: buffer): (Header?, string?)
	local size = buffer.len(data)
	if size < 64 + 768 + 6 or size > Format.MAX_BYTES then return nil, "RVF1 size limit" end
	if buffer.readu32(data, 0) ~= Format.MAGIC or buffer.readu16(data, 4) ~= 1
		or buffer.readu16(data, 6) ~= 64 or buffer.readu32(data, 8) ~= size then
		return nil, "Unsupported RVF1 header"
	end
	local header: Header = {
		Width = buffer.readu16(data, 16), Height = buffer.readu16(data, 18),
		FPS = buffer.readu16(data, 20), FrameCount = buffer.readu16(data, 22),
		FirstFrame = buffer.readu32(data, 24), TotalFrames = buffer.readu32(data, 28),
		SegmentFrames = buffer.readu16(data, 32), PaletteCount = buffer.readu16(data, 34),
		Encoding = buffer.readu16(data, 36), TileSize = buffer.readu16(data, 38),
		Duration = buffer.readf32(data, 40), Bytes = size, Checksum = buffer.readu32(data, 12),
	}
	if header.Width < 16 or header.Width > 256 or header.Height < 16 or header.Height > 256
		or header.Width * header.Height > 36864 or header.FPS < 4 or header.FPS > 20
		or header.FrameCount < 1 or header.FrameCount > header.SegmentFrames
		or header.SegmentFrames < 1 or header.SegmentFrames > header.FPS * 4
		or header.TotalFrames < header.FrameCount or header.TotalFrames > header.FPS * 3600
		or header.FirstFrame + header.FrameCount > header.TotalFrames
		or header.FirstFrame % header.SegmentFrames ~= 0
		or header.PaletteCount ~= 256 or header.Encoding ~= 1 or header.TileSize ~= 4
		or header.Duration ~= header.Duration or header.Duration <= 0 or header.Duration > 3600
		or math.abs(header.TotalFrames - math.ceil(header.Duration * header.FPS)) > 1 then
		return nil, "Invalid RVF1 dimensions"
	end
	for offset = 44, 63 do
		if buffer.readu8(data, offset) ~= 0 then return nil, "Unsupported RVF1 extension" end
	end
	return header, nil
end

function Format.Begin(data: buffer): (Job?, string?)
	local header, problem = Format.Header(data)
	if not header then return nil, problem end
	return {Data = data, Header = header, Position = 0, A = 1, B = 0,
		Frame = 0, Offset = 64 + 768, Phase = 0}, nil
end

local function validateFrame(job: Job): string?
	local data, size = job.Data, job.Header.Bytes
	local offset = job.Offset
	if offset + 6 > size then return "Truncated RVF1 frame" end
	local length = buffer.readu32(data, offset)
	local ending = offset + 4 + length
	if length < 2 or ending > size then return "Invalid RVF1 frame size" end
	local count = buffer.readu16(data, offset + 4)
	local tiles = math.ceil(job.Header.Width / 4) * math.ceil(job.Header.Height / 4)
	if count > tiles or (job.Frame == 0 and count ~= tiles) then return "RVF1 keyframe is incomplete" end
	local seen = buffer.create(tiles)
	offset += 6
	for _ = 1, count do
		if offset + 3 > ending then return "Truncated RVF1 tile" end
		local tile = buffer.readu16(data, offset)
		local mode = buffer.readu8(data, offset + 2)
		local payload = PAYLOAD_BYTES[mode + 1]
		if tile >= tiles or payload == nil or offset + 3 + payload > ending then return "Invalid RVF1 tile" end
		if buffer.readu8(seen, tile) ~= 0 then return "Duplicate RVF1 tile" end
		buffer.writeu8(seen, tile, 1)
		offset += 3 + payload
	end
	if offset ~= ending then return "Unexpected RVF1 frame bytes" end
	job.Offset = ending
	job.Frame += 1
	if job.Frame == job.Header.FrameCount and ending ~= size then return "Unexpected RVF1 trailing bytes" end
	return nil
end

-- Each step handles at most 8 KiB of checksum work or one frame of structural checks.
function Format.Step(job: Job): (boolean, string?)
	if job.Phase == 2 then return true, nil end
	if job.Phase == 0 then
		local ending = math.min(job.Position + 8192, job.Header.Bytes)
		local a, b = job.A, job.B
		for position = job.Position, ending - 1 do
			local value = if position >= 12 and position < 16 then 0 else buffer.readu8(job.Data, position)
			a += value
			b += a
		end
		job.A, job.B, job.Position = a % 65521, b % 65521, ending
		if ending < job.Header.Bytes then return false, nil end
		if job.B * 65536 + job.A ~= job.Header.Checksum then return true, "RVF1 checksum mismatch" end
		job.Phase = 1
		return false, nil
	end
	local problem = validateFrame(job)
	if problem then return true, problem end
	if job.Frame == job.Header.FrameCount then job.Phase = 2; return true, nil end
	return false, nil
end

function Format.Validate(data: buffer): (boolean, string?)
	local job, problem = Format.Begin(data)
	if not job then return false, problem end
	while true do
		local deadline = os.clock() + 0.002
		repeat
			local done, message = Format.Step(job)
			if done then return message == nil, message end
		until os.clock() >= deadline
		task.wait()
	end
end

local Decoder = {}
Decoder.__index = Decoder
export type Decoder = typeof(setmetatable({
	Data = nil :: buffer?, Header = {} :: Header, Pixels = nil :: buffer?,
	Palette = {} :: {number}, Offsets = {} :: {number}, Current = -1,
}, Decoder))

-- Call after Begin/Step or Validate accepts the segment.
function Decoder.new(data: buffer): Decoder
	local header, problem = Format.Header(data)
	assert(header, problem)
	local palette = table.create(256, 0)
	for index = 0, 255 do
		local offset = 64 + index * 3
		palette[index + 1] = buffer.readu8(data, offset) + buffer.readu8(data, offset + 1) * 256
			+ buffer.readu8(data, offset + 2) * 65536 + 4278190080
	end
	local offsets = table.create(header.FrameCount, 0)
	local offset = 64 + 768
	for frame = 1, header.FrameCount do
		assert(offset + 6 <= header.Bytes, "Truncated RVF1 frame")
		offsets[frame] = offset
		offset += 4 + buffer.readu32(data, offset)
		assert(offset <= header.Bytes, "Invalid RVF1 frame size")
	end
	assert(offset == header.Bytes, "Unexpected RVF1 trailing bytes")
	return setmetatable({Data = data, Header = header,
		Pixels = buffer.create(header.Width * header.Height * 4), Palette = palette,
		Offsets = offsets, Current = -1}, Decoder)
end

local function decodeFrame(self: Decoder, frame: number)
	local data, pixels = self.Data, self.Pixels
	assert(data and pixels, "RVF1 decoder was destroyed")
	local header = self.Header
	local columns = math.ceil(header.Width / 4)
	local offset = self.Offsets[frame + 1]
	local count = buffer.readu16(data, offset + 4)
	offset += 6
	for _ = 1, count do
		local tile = buffer.readu16(data, offset)
		local mode = buffer.readu8(data, offset + 2)
		offset += 3
		local x = (tile % columns) * 4
		local y = math.floor(tile / columns) * 4
		local mask = if mode == 1 then buffer.readu16(data, offset + 2)
			elseif mode == 2 then buffer.readu32(data, offset + 4) else 0
		for row = 0, math.min(3, header.Height - y - 1) do
			for column = 0, math.min(3, header.Width - x - 1) do
				local pixel = row * 4 + column
				local paletteIndex: number
				if mode == 0 then paletteIndex = buffer.readu8(data, offset)
				elseif mode == 1 then paletteIndex = buffer.readu8(data, offset + bit32.extract(mask, pixel, 1))
				elseif mode == 2 then paletteIndex = buffer.readu8(data, offset + bit32.extract(mask, pixel * 2, 2))
				else paletteIndex = buffer.readu8(data, offset + pixel) end
				buffer.writeu32(pixels, ((y + row) * header.Width + x + column) * 4, self.Palette[paletteIndex + 1])
			end
		end
		offset += PAYLOAD_BYTES[mode + 1]
	end
	self.Current = frame
end

-- Keeps the last displayed image while seeking; the caller displays only when ready.
function Decoder.Step(self: Decoder, targetFrame: number, budgetMs: number?): (buffer?, boolean)
	assert(self.Data and self.Pixels, "RVF1 decoder was destroyed")
	assert(targetFrame % 1 == 0 and targetFrame >= 0 and targetFrame < self.Header.FrameCount, "RVF1 frame out of range")
	if targetFrame < self.Current then self.Current = -1 end
	local started = os.clock()
	local budget = math.max(0.0001, (budgetMs or 2) / 1000)
	while self.Current < targetFrame do
		decodeFrame(self, self.Current + 1)
		if os.clock() - started >= budget and self.Current < targetFrame then return nil, false end
	end
	return self.Pixels, true
end

function Decoder.Seek(self: Decoder, frame: number): buffer
	local pixels, ready = self:Step(frame, math.huge)
	assert(ready and pixels)
	return pixels
end

function Decoder.Destroy(self: Decoder)
	self.Data = nil
	self.Pixels = nil
	table.clear(self.Palette)
	table.clear(self.Offsets)
	self.Current = -1
end

Format.Decoder = Decoder
return Format

