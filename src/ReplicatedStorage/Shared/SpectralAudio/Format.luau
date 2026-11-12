--!strict
-- Validates SPC1 spectral segments and reads quantized tracked partials without note tables.
local Checksum = require(script.Parent.Parent.AudioSequence.Checksum)
export type Header = {Voices: number, FPS: number, Frames: number, First: number,
	TotalFrames: number, RootHz: number, Bytes: number, Checksum: number,
	Encoding: number, NoiseBands: number, Stride: number, RecordBytes: number}
export type Job = {Data: buffer, Header: Header, Position: number, A: number, B: number}
local Format = {}
Format.HEADER_BYTES = 48
Format.RECORD_BYTES = 6
Format.MAGIC = 0x31435053
function Format.Begin(data: buffer): (Job?, string?)
	local size = buffer.len(data)
	if size < 48 or size > 4 * 1024 * 1024 then return nil, "SPC1 size limit" end
	if buffer.readu32(data, 0) ~= Format.MAGIC or buffer.readu16(data, 4) ~= 1
		or buffer.readu16(data, 6) ~= 48 then return nil, "Unsupported SPC1 header" end
	local header: Header = {
		Voices = buffer.readu16(data, 16), FPS = buffer.readu16(data, 18),
		Frames = buffer.readu32(data, 20), First = buffer.readu32(data, 24),
		TotalFrames = buffer.readu32(data, 32), RootHz = buffer.readf32(data, 36),
		Bytes = size, Checksum = buffer.readu32(data, 12),
		Encoding = buffer.readu32(data, 40), NoiseBands = buffer.readu32(data, 44),
		Stride = 0, RecordBytes = 0,
	}
	if header.Encoding == 1 and header.NoiseBands == 0 then
		header.RecordBytes = 6
	elseif header.Encoding == 3 and header.NoiseBands >= 1 and header.NoiseBands <= 16 then
		header.RecordBytes = 8
	else return nil, "Unsupported SPC1 encoding" end
	header.Stride = header.Voices * header.RecordBytes + header.NoiseBands * 4
	if buffer.readu32(data, 8) ~= size or header.Voices < 16 or header.Voices > 128
		or header.FPS < 20 or header.FPS > 90 or header.Frames < 1 or header.Frames > 2700
		or header.TotalFrames < header.Frames or header.TotalFrames > 90 * 3600
		or header.First + header.Frames > header.TotalFrames
		or header.RootHz ~= 440 or buffer.readu32(data, 28) ~= 24000
		or size ~= 48 + header.Frames * header.Stride then return nil, "Invalid SPC1 dimensions" end
	return {Data = data, Header = header, Position = 0, A = 1, B = 0}, nil
end
function Format.Step(job: Job): (boolean, string?)
	local count = math.min(32768, job.Header.Bytes - job.Position)
	job.A, job.B = Checksum.Update(job.Data, job.Position, count, job.A, job.B)
	job.Position += count
	if job.Position < job.Header.Bytes then return false, nil end
	if Checksum.Finish(job.A, job.B) ~= job.Header.Checksum then return true, "SPC1 checksum mismatch" end
	return true, nil
end
function Format.Validate(data: buffer): (boolean, string?)
	local job, message = Format.Begin(data)
	if not job then return false, message end
	while true do
		local done, problem = Format.Step(job)
		if done then return problem == nil, problem end
		task.wait()
	end
end
local function decodeGain(value: number): number
	return if value == 0 then 0 else 10 ^ (((value - 1) / 65534 * 100 - 100) / 20)
end
function Format.Read(data: buffer, frame: number, voice: number, voices: number): (number, number, number, number)
	local hybrid = buffer.readu32(data, 40) == 3
	local recordBytes = if hybrid then 8 else 6
	local bands = if hybrid then buffer.readu32(data, 44) else 0
	local offset = 48 + frame * (voices * recordBytes + bands * 4) + voice * recordBytes
	local frequency = buffer.readu16(data, offset)
	local gain = buffer.readu16(data, offset + 2)
	local phase = if hybrid then buffer.readu16(data, offset + 6) / 65535 else 0
	if frequency == 0 or gain == 0 then return 0, 0, 0, phase end
	return 20 * 440 ^ ((frequency - 1) / 65534),
		decodeGain(gain), buffer.readu16(data, offset + 4) / 32767.5 - 1, phase
end
-- Reads zero-based residual bands; legacy segments have no residual layer.
function Format.ReadNoise(data: buffer, frame: number, band: number, voices: number): (number, number)
	if buffer.readu32(data, 40) ~= 3 then return 0, 0 end
	local bands = buffer.readu32(data, 44)
	if band < 0 or band >= bands then return 0, 0 end
	local offset = 48 + frame * (voices * 8 + bands * 4) + voices * 8 + band * 4
	return decodeGain(buffer.readu16(data, offset)), decodeGain(buffer.readu16(data, offset + 2))
end
return Format

