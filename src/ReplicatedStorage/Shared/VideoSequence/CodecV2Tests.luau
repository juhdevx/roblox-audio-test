--!strict
-- Checks RVF2 prediction modes, bounds, incremental decode and resource cleanup.
local Codec = require(script.Parent.CodecV2)
local EncodingService = game:GetService("EncodingService")
local Tests = {}

local function checksum(data: buffer): number
	local a, b = 1, 0
	for offset = 0, buffer.len(data) - 1 do
		local value = if offset >= 12 and offset < 16 then 0 else buffer.readu8(data, offset)
		a = (a + value) % 65521; b = (b + a) % 65521
	end
	return b * 65536 + a
end

local function copy(data: buffer): buffer
	local result = buffer.create(buffer.len(data)); buffer.copy(result, 0, data); return result
end

local function fixture(layout: number): (buffer, {buffer})
	local rawBytes = if layout == 0 then 16 * 16 * 4 else 16 * 16 + 2 * 8 * 8
	local originals = {}
	local compressed = {}
	for frame = 0, 2 do
		local raw = buffer.create(rawBytes)
		if layout == 0 then
			for pixel = 0, 255 do buffer.writeu32(raw, pixel * 4, 4278190080 + (pixel + frame * 13) % 256 * 65793) end
		else
			for pixel = 0, 255 do buffer.writeu8(raw, pixel, (pixel + frame * 5) % 64) end
			for pixel = 256, rawBytes - 1 do buffer.writeu8(raw, pixel, 32) end
		end
		originals[frame + 1] = raw
		local filtered = copy(raw)
		if frame > 0 then
			for offset = 0, rawBytes - 1, 4 do
				local current = buffer.readu32(raw, offset)
				local previous = buffer.readu32(originals[frame], offset)
				buffer.writeu32(filtered, offset, if frame == 1 then bit32.bxor(current, previous)
					else bit32.band(current - previous, 0xFFFFFFFF))
			end
		end
		compressed[frame + 1] = EncodingService:CompressBuffer(filtered, Enum.CompressionAlgorithm.Zstd, 3)
	end
	local size = 64 + 3 * 12
	for _, frame in compressed do size += buffer.len(frame) end
	local data = buffer.create(size)
	buffer.writeu32(data, 0, Codec.MAGIC); buffer.writeu16(data, 4, 1); buffer.writeu16(data, 6, 64)
	buffer.writeu32(data, 8, size); buffer.writeu16(data, 16, 16); buffer.writeu16(data, 18, 16)
	buffer.writeu16(data, 20, 4); buffer.writeu16(data, 22, 3); buffer.writeu32(data, 28, 3)
	buffer.writeu16(data, 32, 8); buffer.writeu16(data, 36, 2); buffer.writef32(data, 40, 0.75)
	buffer.writeu32(data, 44, rawBytes)
	buffer.writeu8(data, 48, 6); buffer.writeu8(data, 49, 6); buffer.writeu8(data, 50, 6)
	buffer.writeu8(data, 51, 1); buffer.writeu8(data, 52, layout)
	local offset = 64
	for frame, packed in compressed do
		buffer.writeu32(data, offset, buffer.len(packed)); buffer.writeu32(data, offset + 4, rawBytes)
		buffer.writeu8(data, offset + 8, frame - 1); buffer.copy(data, offset + 12, packed)
		offset += 12 + buffer.len(packed)
	end
	buffer.writeu32(data, 12, checksum(data))
	return data, originals
end

function Tests.Run(): {Checks: number, Passed: boolean}
	local checks = 0
	local function check(condition: boolean, message: string) assert(condition, message); checks += 1 end
	for layout = 0, 1 do
		local data, originals = fixture(layout)
		check(Codec.Validate(data), "Valid RVF2 fixture rejected")
		local decoder = Codec.Decoder.new(data)
		for _, frame in {0, 2, 1, 2} do
			local pixels = decoder:Seek(frame)
			check(buffer.len(pixels) == 16 * 16 * 4 and decoder.Current == frame, "Decode dimensions or frame mismatch")
			if layout == 0 then check(buffer.tostring(pixels) == buffer.tostring(originals[frame + 1]), "RGBA prediction differs")
			else
				check(buffer.readu8(pixels, 3) == 255 and buffer.readu8(pixels, 7) == 255, "YCbCr alpha differs")
			end
		end
		check(not pcall(function() decoder:Seek(3) end), "Out of range RVF2 frame accepted")
		decoder:Destroy(); decoder:Destroy()
		check(not pcall(function() decoder:Seek(0) end), "Destroyed decoder accepted work")
	end
	local original = fixture(0)
	local function rejected(mutate: (buffer) -> (), message: string)
		local data = copy(original); mutate(data); buffer.writeu32(data, 12, checksum(data))
		check(not Codec.Validate(data), message)
	end
	rejected(function(data) buffer.writeu32(data, 44, 99999999) end, "Oversized decompression target accepted")
	rejected(function(data) buffer.writeu8(data, 52, 2) end, "Unknown layout accepted")
	rejected(function(data) buffer.writeu8(data, 51, 2) end, "Unknown compression accepted")
	rejected(function(data) buffer.writeu8(data, 53, 1) end, "Unknown extension accepted")
	rejected(function(data) buffer.writeu8(data, 72, 1) end, "Prediction keyframe accepted")
	rejected(function(data) buffer.writeu32(data, 64, 99999999) end, "Truncated compression accepted")
	rejected(function(data) buffer.writeu32(data, 68, 16) end, "Frame raw size mismatch accepted")
	rejected(function(data) buffer.writeu16(data, 16, 1024) end, "Oversized dimensions accepted")
	local bad = copy(original); buffer.writeu8(bad, buffer.len(bad) - 1, 255)
	check(not Codec.Validate(bad), "Checksum corruption accepted")
	check(not Codec.Validate(buffer.create(10)), "Short header accepted")
	check(not Codec.Validate(buffer.create(Codec.MAX_BYTES + 1)), "Huge segment accepted")
	local decoder = Codec.Decoder.new(original)
	local ready, calls = false, 0
	while not ready do
		local _, done = decoder:Step(2, 0.001); ready = done; calls += 1
		assert(calls < 100, "Incremental decoder stopped progressing")
	end
	check(decoder.Current == 2 and calls > 1, "Incremental prediction did not complete")
	decoder:Destroy()
	return {Checks = checks, Passed = true}
end

return Tests
