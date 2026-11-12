--!strict
-- Decodes bounded RVF2 Zstd frames with full-color and YCbCr420 layouts.
local EncodingService = game:GetService("EncodingService")
local Codec = {}
Codec.MAGIC = 0x32465652
Codec.HEADER_BYTES = 64
Codec.MAX_BYTES = 4 * 1024 * 1024

export type Header = {
	Width: number, Height: number, FPS: number, FrameCount: number, FirstFrame: number,
	TotalFrames: number, SegmentFrames: number, PaletteCount: number, Encoding: number,
	TileSize: number, Duration: number, Bytes: number, Checksum: number,
	RawFrameBytes: number, BitsR: number, BitsG: number, BitsB: number, Layout: number,
}
export type Job = {Data: buffer, Header: Header, Position: number, A: number, B: number,
	Phase: number, Frame: number, Offset: number}

function Codec.Header(data: buffer): (Header?, string?)
	local size = buffer.len(data)
	if size < 76 or size > Codec.MAX_BYTES then return nil, "RVF2 size limit" end
	if buffer.readu32(data, 0) ~= Codec.MAGIC or buffer.readu16(data, 4) ~= 1
		or buffer.readu16(data, 6) ~= 64 or buffer.readu32(data, 8) ~= size then return nil, "Unsupported RVF2 header" end
	local header: Header = {
		Width = buffer.readu16(data, 16), Height = buffer.readu16(data, 18),
		FPS = buffer.readu16(data, 20), FrameCount = buffer.readu16(data, 22),
		FirstFrame = buffer.readu32(data, 24), TotalFrames = buffer.readu32(data, 28),
		SegmentFrames = buffer.readu16(data, 32), PaletteCount = buffer.readu16(data, 34),
		Encoding = buffer.readu16(data, 36), TileSize = buffer.readu16(data, 38),
		Duration = buffer.readf32(data, 40), RawFrameBytes = buffer.readu32(data, 44),
		BitsR = buffer.readu8(data, 48), BitsG = buffer.readu8(data, 49), BitsB = buffer.readu8(data, 50),
		Layout = buffer.readu8(data, 52), Bytes = size, Checksum = buffer.readu32(data, 12),
	}
	local expected = if header.Layout == 0 then header.Width * header.Height * 4
		else header.Width * header.Height + 2 * math.ceil(header.Width / 2) * math.ceil(header.Height / 2)
	if header.Width < 16 or header.Width > 1024 or header.Height < 16 or header.Height > 1024
		or header.Width * header.Height > 1024 * 576 or header.FPS < 4 or header.FPS > 30
		or header.FrameCount < 1 or header.FrameCount > header.SegmentFrames
		or header.SegmentFrames < 1 or header.SegmentFrames > header.FPS * 4
		or header.TotalFrames < header.FrameCount or header.TotalFrames > header.FPS * 3600
		or header.FirstFrame + header.FrameCount > header.TotalFrames or header.FirstFrame % header.SegmentFrames ~= 0
		or header.PaletteCount ~= 0 or header.Encoding ~= 2 or header.TileSize ~= 0
		or header.Duration ~= header.Duration or header.Duration <= 0 or header.Duration > 3600
		or math.abs(header.TotalFrames - math.ceil(header.Duration * header.FPS)) > 1
		or header.RawFrameBytes ~= expected or header.Layout > 1 or buffer.readu8(data, 51) ~= 1
		or header.BitsR < 3 or header.BitsR > 8 or header.BitsG < 3 or header.BitsG > 8
		or header.BitsB < 3 or header.BitsB > 8
		or (header.Layout == 1 and header.BitsR + header.BitsG + header.BitsB > 20) then
		return nil, "Invalid RVF2 dimensions"
	end
	for offset = 53, 63 do if buffer.readu8(data, offset) ~= 0 then return nil, "Unsupported RVF2 extension" end end
	return header, nil
end

function Codec.Begin(data: buffer): (Job?, string?)
	local header, problem = Codec.Header(data)
	if not header then return nil, problem end
	return {Data = data, Header = header, Position = 0, A = 1, B = 0, Phase = 0, Frame = 0, Offset = 64}, nil
end

local function frameHeader(data: buffer, offset: number, header: Header, frame: number): (number?, number?, string?)
	if offset + 12 > header.Bytes then return nil, nil, "Truncated RVF2 frame" end
	local size = buffer.readu32(data, offset)
	local rawSize = buffer.readu32(data, offset + 4)
	local mode = buffer.readu8(data, offset + 8)
	if size < 6 or offset + 12 + size > header.Bytes or rawSize ~= header.RawFrameBytes or mode > 2
		or (frame == 0 and mode ~= 0) or (mode == 2 and rawSize % 4 ~= 0)
		or buffer.readu8(data, offset + 9) ~= 0 or buffer.readu16(data, offset + 10) ~= 0 then
		return nil, nil, "Invalid RVF2 frame"
	end
	return size, mode, nil
end

-- Each step handles at most 32 KiB of checksum or one compressed-frame header.
function Codec.Step(job: Job): (boolean, string?)
	if job.Phase == 2 then return true, nil end
	if job.Phase == 0 then
		local ending = math.min(job.Position + 32768, job.Header.Bytes)
		local a, b = job.A, job.B
		for position = job.Position, ending - 1 do
			local value = if position >= 12 and position < 16 then 0 else buffer.readu8(job.Data, position)
			a += value; b += a
		end
		job.A, job.B, job.Position = a % 65521, b % 65521, ending
		if ending < job.Header.Bytes then return false, nil end
		if job.B * 65536 + job.A ~= job.Header.Checksum then return true, "RVF2 checksum mismatch" end
		job.Phase = 1
		return false, nil
	end
	local size, _, problem = frameHeader(job.Data, job.Offset, job.Header, job.Frame)
	if not size then return true, problem end
	local compressed = buffer.create(size)
	buffer.copy(compressed, 0, job.Data, job.Offset + 12, size)
	local ok, declared = pcall(function()
		return EncodingService:GetDecompressedBufferSize(compressed, Enum.CompressionAlgorithm.Zstd)
	end)
	if not ok or declared ~= job.Header.RawFrameBytes then return true, "RVF2 Zstd output size mismatch" end
	job.Offset += 12 + size
	job.Frame += 1
	if job.Frame == job.Header.FrameCount then
		if job.Offset ~= job.Header.Bytes then return true, "Unexpected RVF2 trailing bytes" end
		job.Phase = 2
		return true, nil
	end
	return false, nil
end

function Codec.Validate(data: buffer): (boolean, string?)
	local job, problem = Codec.Begin(data)
	if not job then return false, problem end
	while true do
		local done, message = Codec.Step(job)
		if done then return message == nil, message end
		task.wait()
	end
end

type Lookup = {Data: buffer, Position: number, Count: number, YCount: number, CbCount: number, CrCount: number}
local lookups: {[string]: Lookup} = {}

local function getLookup(r: number, g: number, b: number): Lookup
	local key = `{r}:{g}:{b}`
	local found = lookups[key]
	if found then return found end
	local count = 2 ^ (r + g + b)
	-- Only four profiles are cached; existing decoders retain their own reference.
	local entries = 0
	for _ in lookups do entries += 1 end
	if entries >= 4 then table.clear(lookups) end
	found = {Data = buffer.create(count * 4), Position = 0, Count = count,
		YCount = 2 ^ r, CbCount = 2 ^ g, CrCount = 2 ^ b}
	lookups[key] = found
	return found
end

local function prepareLookup(lookup: Lookup, deadline: number): boolean
	local position = lookup.Position
	local yc, cc, rc = lookup.YCount, lookup.CbCount, lookup.CrCount
	while position < lookup.Count do
		local ending = math.min(position + 512, lookup.Count)
		for index = position, ending - 1 do
			local y = (index % yc) * 255 / (yc - 1)
			local cb = (math.floor(index / yc) % cc) * 255 / (cc - 1) - 128
			local cr = math.floor(index / (yc * cc)) * 255 / (rc - 1) - 128
			local r = math.clamp(math.floor(y + 1.402 * cr + 0.5), 0, 255)
			local green = -0.344136 * cb - 0.714136 * cr
			local g = math.clamp(math.floor(y + green + 0.5), 0, 255)
			local b = math.clamp(math.floor(y + 1.772 * cb + 0.5), 0, 255)
			buffer.writeu32(lookup.Data, index * 4, r + g * 256 + b * 65536 + 4278190080)
		end
		position = ending; lookup.Position = position
		if os.clock() >= deadline then return position == lookup.Count end
	end
	return true
end

-- Warms the default profile without yielding or creating an image.
function Codec.Prepare(budgetMs: number?): boolean
	return prepareLookup(getLookup(6, 6, 6), os.clock() + math.max(0.0001, (budgetMs or 2) / 1000))
end

function Codec.PrepareFor(header: Header, budgetMs: number?): boolean
	if header.Layout == 0 then return true end
	return prepareLookup(getLookup(header.BitsR, header.BitsG, header.BitsB),
		os.clock() + math.max(0.0001, (budgetMs or 2) / 1000))
end

local Decoder = {}
Decoder.__index = Decoder
type Pending = {Raw: buffer, Mode: number, Position: number, Index: number}
export type Decoder = typeof(setmetatable({
	Data = nil :: buffer?, Header = {} :: Header, Pixels = nil :: buffer?,
	Offsets = {} :: {number}, Current = -1, RawFrame = -1, Previous = nil :: buffer?,
	Pending = nil :: Pending?, Lookup = nil :: Lookup?, ConvertRow = 0, ConvertFrame = -1,
}, Decoder))

function Decoder.new(data: buffer): Decoder
	local header, problem = Codec.Header(data)
	assert(header, problem)
	local offsets = table.create(header.FrameCount, 0)
	local offset = 64
	for frame = 0, header.FrameCount - 1 do
		local size, _, message = frameHeader(data, offset, header, frame)
		assert(size, message)
		offsets[frame + 1] = offset; offset += 12 + size
	end
	assert(offset == header.Bytes, "Unexpected RVF2 trailing bytes")
	return setmetatable({Data = data, Header = header, Pixels = buffer.create(header.Width * header.Height * 4),
		Offsets = offsets, Current = -1, RawFrame = -1, Previous = nil, Pending = nil,
		Lookup = if header.Layout == 1 then getLookup(header.BitsR, header.BitsG, header.BitsB) else nil,
		ConvertRow = 0, ConvertFrame = -1}, Decoder)
end

local function beginFrame(self: Decoder): Pending
	local data = assert(self.Data, "RVF2 decoder was destroyed")
	local index = self.RawFrame + 1
	local offset = self.Offsets[index + 1]
	local size, mode, problem = frameHeader(data, offset, self.Header, index)
	assert(size and mode, problem)
	local packed = buffer.create(size)
	buffer.copy(packed, 0, data, offset + 12, size)
	assert(EncodingService:GetDecompressedBufferSize(packed, Enum.CompressionAlgorithm.Zstd) == self.Header.RawFrameBytes,
		"RVF2 Zstd output size mismatch")
	local raw = EncodingService:DecompressBuffer(packed, Enum.CompressionAlgorithm.Zstd)
	assert(buffer.len(raw) == self.Header.RawFrameBytes, "RVF2 decompression size mismatch")
	return {Raw = raw, Mode = mode, Position = 0, Index = index}
end

local function reversePrediction(self: Decoder, pending: Pending, deadline: number): boolean
	if pending.Mode == 0 then return true end
	local previous = assert(self.Previous, "RVF2 prediction requires a preceding frame")
	local raw = pending.Raw
	local bytes = self.Header.RawFrameBytes
	local aligned = bytes - bytes % 4
	while pending.Position < aligned do
		local ending = math.min(pending.Position + 2048, aligned)
		if pending.Mode == 1 then
			for offset = pending.Position, ending - 1, 4 do
				buffer.writeu32(raw, offset, bit32.bxor(buffer.readu32(raw, offset), buffer.readu32(previous, offset)))
			end
		else
			for offset = pending.Position, ending - 1, 4 do
				buffer.writeu32(raw, offset, bit32.band(buffer.readu32(raw, offset) + buffer.readu32(previous, offset), 0xFFFFFFFF))
			end
		end
		pending.Position = ending
		if os.clock() >= deadline then return false end
	end
	for offset = aligned, bytes - 1 do
		assert(pending.Mode == 1, "Invalid RVF2 prediction alignment")
		buffer.writeu8(raw, offset, bit32.bxor(buffer.readu8(raw, offset), buffer.readu8(previous, offset)))
	end
	return true
end

local function convertPixels(self: Decoder, deadline: number): boolean
	local raw, pixels = assert(self.Previous), assert(self.Pixels)
	if self.Header.Layout == 0 then buffer.copy(pixels, 0, raw); return true end
	local lookup = assert(self.Lookup)
	local width, height = self.Header.Width, self.Header.Height
	local area, columns, rows = width * height, math.ceil(width / 2), math.ceil(height / 2)
	local yc, cc = lookup.YCount, lookup.CbCount
	local palette = lookup.Data
	while self.ConvertRow < rows do
		local row = self.ConvertRow
		for column = 0, columns - 1 do
			local chroma = row * columns + column
			local cb = buffer.readu8(raw, area + chroma)
			local cr = buffer.readu8(raw, area + columns * rows + chroma)
			assert(cb < cc and cr < lookup.CrCount, "RVF2 chroma code out of range")
			local base = cb * yc + cr * yc * cc
			local x, y = column * 2, row * 2
			local offset = y * width + x
			local a = buffer.readu8(raw, offset)
			assert(a < yc, "RVF2 luminance code out of range")
			buffer.writeu32(pixels, offset * 4, buffer.readu32(palette, (base + a) * 4))
			if x + 1 < width then
				local b = buffer.readu8(raw, offset + 1)
				assert(b < yc, "RVF2 luminance code out of range")
				buffer.writeu32(pixels, (offset + 1) * 4, buffer.readu32(palette, (base + b) * 4))
			end
			if y + 1 < height then
				local c = buffer.readu8(raw, offset + width)
				assert(c < yc, "RVF2 luminance code out of range")
				buffer.writeu32(pixels, (offset + width) * 4, buffer.readu32(palette, (base + c) * 4))
				if x + 1 < width then
					local d = buffer.readu8(raw, offset + width + 1)
					assert(d < yc, "RVF2 luminance code out of range")
					buffer.writeu32(pixels, (offset + width + 1) * 4, buffer.readu32(palette, (base + d) * 4))
				end
			end
		end
		self.ConvertRow += 1
		if os.clock() >= deadline then return self.ConvertRow == rows end
	end
	return true
end

-- Only the target frame is converted to RGBA when seeking across intermediate predictions.
function Decoder.Step(self: Decoder, targetFrame: number, budgetMs: number?): (buffer?, boolean)
	assert(self.Data and self.Pixels, "RVF2 decoder was destroyed")
	assert(targetFrame % 1 == 0 and targetFrame >= 0 and targetFrame < self.Header.FrameCount, "RVF2 frame out of range")
	local deadline = os.clock() + math.max(0.0001, (budgetMs or 2) / 1000)
	if self.Lookup and not prepareLookup(self.Lookup, deadline) then return nil, false end
	if targetFrame < self.RawFrame then
		self.Previous = nil; self.Pending = nil; self.RawFrame = -1; self.Current = -1
		self.ConvertFrame = -1; self.ConvertRow = 0
	end
	while self.RawFrame < targetFrame do
		local pending = self.Pending
		if not pending then pending = beginFrame(self); self.Pending = pending end
		if not reversePrediction(self, pending, deadline) then return nil, false end
		self.Previous = pending.Raw; self.RawFrame = pending.Index; self.Pending = nil
		if os.clock() >= deadline then return nil, false end
	end
	if self.Current == targetFrame then return self.Pixels, true end
	if self.ConvertFrame ~= self.RawFrame then self.ConvertFrame = self.RawFrame; self.ConvertRow = 0 end
	if not convertPixels(self, deadline) then return nil, false end
	self.Current = self.RawFrame
	return self.Pixels, true
end

function Decoder.Seek(self: Decoder, targetFrame: number): buffer
	local pixels, ready = self:Step(targetFrame, math.huge)
	assert(ready and pixels)
	return pixels
end

function Decoder.Destroy(self: Decoder)
	self.Data = nil; self.Pixels = nil; self.Previous = nil; self.Pending = nil; self.Lookup = nil
	table.clear(self.Offsets); self.Current = -1; self.RawFrame = -1
end

Codec.Decoder = Decoder
return Codec
