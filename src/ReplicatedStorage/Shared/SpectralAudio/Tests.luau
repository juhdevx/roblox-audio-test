--!strict
-- Exercises spectral payload rejection, quantization endpoints and the Panini variant contract.
local Format = require(script.Parent.Format)
local Checksum = require(script.Parent.Parent.AudioSequence.Checksum)
local Tests = {}
function Tests.Run(): number
	local count = 0
	local function check(ok: boolean, message: string) assert(ok, message); count += 1 end
	local function seal(data: buffer)
		local a, b = Checksum.Update(data, 0, buffer.len(data), 1, 0)
		buffer.writeu32(data, 12, Checksum.Finish(a, b))
	end
	local function fixture(hybrid: boolean?): buffer
		local data = buffer.create(48 + (if hybrid then 96 * 8 + 8 * 4 else 96 * 6))
		buffer.writeu32(data, 0, Format.MAGIC); buffer.writeu16(data, 4, 1); buffer.writeu16(data, 6, 48)
		buffer.writeu32(data, 8, buffer.len(data)); buffer.writeu16(data, 16, 96); buffer.writeu16(data, 18, 60)
		buffer.writeu32(data, 20, 1); buffer.writeu32(data, 28, 24000); buffer.writeu32(data, 32, 1)
		buffer.writef32(data, 36, 440); buffer.writeu32(data, 40, if hybrid then 3 else 1)
		buffer.writeu32(data, 44, if hybrid then 8 else 0); seal(data)
		return data
	end
	local valid = fixture()
	check(Format.Validate(valid), "Valid SPC1")
	local hz, gain = Format.Read(valid, 0, 0, 96)
	check(hz == 0 and gain == 0, "Silent partial")
	buffer.writeu16(valid, 48, 65535); buffer.writeu16(valid, 50, 65535); buffer.writeu16(valid, 52, 65535)
	local high, loud, right = Format.Read(valid, 0, 0, 96)
	check(math.abs(high - 8800) < 0.01 and loud == 1 and right == 1, "Quantized upper endpoints")
	buffer.writeu16(valid, 48, 1); buffer.writeu16(valid, 50, 1); buffer.writeu16(valid, 52, 0)
	local low, quiet, left = Format.Read(valid, 0, 0, 96)
	check(low == 20 and math.abs(quiet - 0.00001) < 1e-9 and left == -1, "Quantized lower endpoints")
	check(not Format.Validate(valid), "Corrupt body rejected")
	local mutations = {
		function(d: buffer) buffer.writeu32(d, 0, 0) end,
		function(d: buffer) buffer.writeu16(d, 4, 2) end,
		function(d: buffer) buffer.writeu16(d, 6, 40) end,
		function(d: buffer) buffer.writeu32(d, 8, 1) end,
		function(d: buffer) buffer.writeu16(d, 16, 129) end,
		function(d: buffer) buffer.writeu16(d, 18, 0) end,
		function(d: buffer) buffer.writeu32(d, 20, 0) end,
		function(d: buffer) buffer.writeu32(d, 24, 1) end,
		function(d: buffer) buffer.writeu32(d, 28, 44100) end,
		function(d: buffer) buffer.writeu32(d, 32, 0) end,
		function(d: buffer) buffer.writef32(d, 36, 0/0) end,
		function(d: buffer) buffer.writeu32(d, 40, 0) end,
		function(d: buffer) buffer.writeu32(d, 44, 1) end,
	}
	for index, mutate in mutations do
		local data = fixture(); mutate(data); seal(data)
		check(not Format.Validate(data), `Malformed header {index}`)
	end
	check(not Format.Validate(buffer.create(12)), "Truncated header")
	local hybrid = fixture(true)
	check(Format.Validate(hybrid), "Valid hybrid SPC1")
	local job = Format.Begin(hybrid)
	check(job ~= nil and job.Header.Encoding == 3 and job.Header.NoiseBands == 8
		and job.Header.RecordBytes == 8 and job.Header.Stride == 800, "Hybrid layout metadata")
	buffer.writeu16(hybrid, 48, 32768); buffer.writeu16(hybrid, 50, 65535)
	buffer.writeu16(hybrid, 52, 32768); buffer.writeu16(hybrid, 54, 16384)
	local _, _, _, phase = Format.Read(hybrid, 0, 0, 96)
	check(math.abs(phase - 0.25) < 0.00002, "Phase is decoded in cycles")
	buffer.writeu16(hybrid, 48 + 96 * 8, 65535)
	buffer.writeu16(hybrid, 48 + 96 * 8 + 2, 1)
	local residualLeft, residualRight = Format.ReadNoise(hybrid, 0, 0, 96)
	check(residualLeft == 1 and math.abs(residualRight - 0.00001) < 1e-9, "Independent stereo residual gains")
	local absentLeft, absentRight = Format.ReadNoise(hybrid, 0, 8, 96)
	check(absentLeft == 0 and absentRight == 0, "Out of range residual band is silent")
	local legacyLeft, legacyRight = Format.ReadNoise(fixture(), 0, 0, 96)
	check(legacyLeft == 0 and legacyRight == 0, "Legacy has no residual")
	check(not Format.Validate(hybrid), "Hybrid body corruption rejected")
	seal(hybrid); check(Format.Validate(hybrid), "Hybrid checksum seals updated payload")
	local hybridMutations = {
		function(d: buffer) buffer.writeu32(d, 40, 2) end,
		function(d: buffer) buffer.writeu32(d, 44, 0) end,
		function(d: buffer) buffer.writeu32(d, 44, 17) end,
		function(d: buffer) buffer.writeu32(d, 40, 1) end,
		function(d: buffer) buffer.writeu32(d, 44, 7) end,
	}
	for index, mutate in hybridMutations do
		local data = fixture(true); mutate(data); seal(data)
		check(not Format.Validate(data), `Malformed hybrid layout {index}`)
	end
	local truncated = buffer.create(buffer.len(hybrid) - 1)
	buffer.copy(truncated, 0, hybrid, 0, buffer.len(truncated))
	buffer.writeu32(truncated, 8, buffer.len(truncated)); seal(truncated)
	check(not Format.Validate(truncated), "Truncated hybrid record rejected")
	local emotes = script.Parent.Parent.Registries.Emotes
	local original = require(emotes.PaniniEvent)
	local test = require(emotes.TestSound)
	check(original.Name == "PaniniEvent" and test.Name == "TestSound", "Stable emote names")
	check(test.Loop == original.Loop and test.AnimSpeed == original.AnimSpeed, "Panini animation retained")
	check(test.Traversal == original.Traversal and test.Speed == original.Speed, "Panini traversal retained")
	check(test.Song.Backend == "Spectral" and test.Song.Track == "WoahUseItPhaseFit", "Spectral track selected")
	check(type(test.Default) == "boolean" and type(test.Exclusive) == "boolean", "Ownership policy remains data driven")
	return count
end
return Tests

