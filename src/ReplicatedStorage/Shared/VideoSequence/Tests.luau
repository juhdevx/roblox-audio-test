--!strict
-- Exercises RVF1 modes, seeking, incremental validation and malformed segments.
local Format = require(script.Parent.Format)
local Tests = {}

local function checksum(data: buffer): number
	local a, b = 1, 0
	for offset = 0, buffer.len(data) - 1 do
		local value = if offset >= 12 and offset < 16 then 0 else buffer.readu8(data, offset)
		a = (a + value) % 65521
		b = (b + a) % 65521
	end
	return b * 65536 + a
end

local function fixture(): buffer
	local first = buffer.create(2 + 4 * (4 + 7 + 11 + 19))
	buffer.writeu16(first, 0, 16)
	local offset = 2
	for tile = 0, 15 do
		local mode = tile % 4
		buffer.writeu16(first, offset, tile)
		buffer.writeu8(first, offset + 2, mode)
		offset += 3
		if mode == 0 then buffer.writeu8(first, offset, 11); offset += 1
		elseif mode == 1 then
			buffer.writeu8(first, offset, 20); buffer.writeu8(first, offset + 1, 40)
			buffer.writeu16(first, offset + 2, 0xA55A); offset += 4
		elseif mode == 2 then
			for index = 0, 3 do buffer.writeu8(first, offset + index, 60 + index) end
			buffer.writeu32(first, offset + 4, 0xE4E4E4E4); offset += 8
		else
			for index = 0, 15 do buffer.writeu8(first, offset + index, 100 + index) end
			offset += 16
		end
	end
	assert(offset == buffer.len(first))
	local second = buffer.create(6)
	buffer.writeu16(second, 0, 1); buffer.writeu16(second, 2, 0)
	buffer.writeu8(second, 4, 0); buffer.writeu8(second, 5, 99)
	local data = buffer.create(64 + 768 + 8 + buffer.len(first) + buffer.len(second))
	buffer.writeu32(data, 0, Format.MAGIC); buffer.writeu16(data, 4, 1); buffer.writeu16(data, 6, 64)
	buffer.writeu32(data, 8, buffer.len(data)); buffer.writeu16(data, 16, 16); buffer.writeu16(data, 18, 16)
	buffer.writeu16(data, 20, 4); buffer.writeu16(data, 22, 2); buffer.writeu32(data, 28, 2)
	buffer.writeu16(data, 32, 8); buffer.writeu16(data, 34, 256); buffer.writeu16(data, 36, 1)
	buffer.writeu16(data, 38, 4); buffer.writef32(data, 40, 0.5)
	for index = 0, 255 do
		buffer.writeu8(data, 64 + index * 3, index)
		buffer.writeu8(data, 65 + index * 3, 255 - index)
		buffer.writeu8(data, 66 + index * 3, (index * 7) % 256)
	end
	buffer.writeu32(data, 832, buffer.len(first)); buffer.copy(data, 836, first)
	local nextFrame = 836 + buffer.len(first)
	buffer.writeu32(data, nextFrame, buffer.len(second)); buffer.copy(data, nextFrame + 4, second)
	buffer.writeu32(data, 12, checksum(data))
	return data
end

local function copy(data: buffer): buffer
	local result = buffer.create(buffer.len(data)); buffer.copy(result, 0, data)
	return result
end

local function expectedIndex(x: number, y: number, frame: number): number
	local tile = math.floor(y / 4) * 4 + math.floor(x / 4)
	local pixel = (y % 4) * 4 + x % 4
	if frame == 1 and tile == 0 then return 99 end
	local mode = tile % 4
	if mode == 0 then return 11
	elseif mode == 1 then return if bit32.extract(0xA55A, pixel, 1) == 0 then 20 else 40
	elseif mode == 2 then return 60 + bit32.extract(0xE4E4E4E4, pixel * 2, 2)
	else return 100 + pixel end
end

function Tests.Run(): {Checks: number, Passed: boolean}
	local count = 0
	local function check(condition: boolean, message: string)
		assert(condition, message); count += 1
	end
	local original = fixture()
	local valid, problem = Format.Validate(original)
	check(valid and problem == nil, "Valid fixture rejected")
	local job = assert(Format.Begin(original))
	local done = false
	local steps = 0
	while not done do done, problem = Format.Step(job); steps += 1 end
	check(problem == nil and steps == 3, "Validation phases are not incremental")
	local decoder = Format.Decoder.new(original)
	for _, frame in {0, 1, 0, 1} do
		local pixels = decoder:Seek(frame)
		local allMatch = true
		for y = 0, 15 do
			for x = 0, 15 do
				local index = expectedIndex(x, y, frame)
				local offset = (y * 16 + x) * 4
				if buffer.readu8(pixels, offset) ~= index or buffer.readu8(pixels, offset + 1) ~= 255 - index
					or buffer.readu8(pixels, offset + 2) ~= (index * 7) % 256
					or buffer.readu8(pixels, offset + 3) ~= 255 then allMatch = false end
			end
		end
		check(allMatch, "Decoded mode or seek differs from expected RGBA")
	end
	check(not pcall(function() decoder:Seek(-1) end), "Negative frame accepted")
	check(not pcall(function() decoder:Seek(2) end), "Out of range frame accepted")
	decoder:Destroy(); decoder:Destroy()
	check(not pcall(function() decoder:Seek(0) end), "Destroyed decoder accepted work")
	local corrupt = copy(original)
	buffer.writeu8(corrupt, 70, (buffer.readu8(corrupt, 70) + 1) % 256)
	check(not Format.Validate(corrupt), "Checksum corruption accepted")
	local function rejected(change: (buffer) -> (), message: string)
		local data = copy(original); change(data); buffer.writeu32(data, 12, checksum(data))
		check(not Format.Validate(data), message)
	end
	rejected(function(data) buffer.writeu16(data, 16, 512) end, "Oversized dimensions accepted")
	rejected(function(data) buffer.writeu16(data, 20, 60) end, "Oversized FPS accepted")
	rejected(function(data) buffer.writeu16(data, 34, 255) end, "Partial palette accepted")
	rejected(function(data) buffer.writeu8(data, 44, 1) end, "Unknown extension accepted")
	rejected(function(data) buffer.writeu16(data, 836, 15) end, "Incomplete keyframe accepted")
	rejected(function(data) buffer.writeu8(data, 840, 7) end, "Invalid tile mode accepted")
	rejected(function(data) buffer.writeu16(data, 838, 16) end, "Out of range tile accepted")
	rejected(function(data) buffer.writeu16(data, 842, 0) end, "Duplicate tile accepted")
	rejected(function(data) buffer.writeu32(data, 832, 2) end, "Truncated frame accepted")
	check(not Format.Validate(buffer.create(20)), "Short header accepted")
	check(not Format.Validate(buffer.create(Format.MAX_BYTES + 1)), "Oversized segment accepted")
	return {Checks = count, Passed = true}
end

return Tests

