--!strict
-- Validates RSEQ and decodes bounded batches into packed event/track buffers.
local Format = require(script.Parent.Format)
local Types = require(script.Parent.Types)
local Checksum = require(script.Parent.Checksum)
type Decoder = Types.Decoder
type Metadata = Types.Metadata
type Sequence = Types.Sequence
local Parser = {}

local function requireBytes(job: Decoder, count: number, limit: number)
    if job.Position + count > limit then error(`Truncated data at byte {job.Position}`, 0) end
end

local function varint(job: Decoder): number
    local value = 0
    local multiplier = 1
    for index = 1, 4 do
        requireBytes(job, 1, job.TrackEnd)
        local byte = buffer.readu8(job.Input, job.Position)
        job.Position += 1
        local digit = byte % 128
        value += digit * multiplier
        if byte < 128 then
            if index > 1 and digit == 0 then error("Noncanonical varint", 0) end
            return value
        end
        multiplier *= 128
    end
    error("Varint exceeds four bytes", 0)
end

-- The caller owns Input and must not mutate it until decoding completes.
function Parser.Begin(data: buffer): (Decoder?, string?)
    local size = buffer.len(data)
    if size < Format.HEADER_BYTES or size > Format.MAX_FILE_BYTES then return nil, "Invalid file size" end
    if buffer.readu32(data, 0) ~= Format.MAGIC then return nil, "Invalid RSEQ magic" end
    if buffer.readu16(data, 4) ~= Format.VERSION then return nil, "Unsupported version" end
    if buffer.readu16(data, 6) ~= Format.HEADER_BYTES then return nil, "Invalid header size" end
    if buffer.readu32(data, 8) ~= size then return nil, "Declared length mismatch" end
    if buffer.readu32(data, 32) ~= 0 or buffer.readu32(data, 36) ~= 0 then return nil, "Unsupported header flags" end
    local metadata: Metadata = {
        Version = buffer.readu16(data, 4), TotalBytes = size, Checksum = buffer.readu32(data, 12),
        TrackCount = buffer.readu16(data, 16), TicksPerBeat = buffer.readu16(data, 18),
        BPM = buffer.readf32(data, 20), EventCount = buffer.readu32(data, 24),
        DurationTicks = buffer.readu32(data, 28),
    }
    if metadata.TrackCount < 1 or metadata.TrackCount > Format.MAX_TRACKS then return nil, "Track limit" end
    if metadata.EventCount < 1 or metadata.EventCount > Format.MAX_EVENTS then return nil, "Event limit" end
    if metadata.TicksPerBeat < Format.MIN_TICKS_PER_BEAT or metadata.TicksPerBeat > Format.MAX_TICKS_PER_BEAT then
        return nil, "Invalid ticks per beat"
    end
    if metadata.BPM ~= metadata.BPM or metadata.BPM < Format.MIN_BPM or metadata.BPM > Format.MAX_BPM then
        return nil, "Invalid BPM"
    end
    if metadata.DurationTicks < 1 or metadata.DurationTicks > Format.MAX_TICKS then return nil, "Invalid duration" end
    local minimum = Format.HEADER_BYTES + metadata.TrackCount * Format.TRACK_HEADER_BYTES
        + metadata.EventCount * Format.MIN_WIRE_EVENT_BYTES
    if minimum > size then return nil, "Impossible declared counts" end
    local job: Decoder = {
        Input = data, Metadata = metadata, Phase = "Checksum", Error = nil,
        ChecksumPosition = 0, AdlerA = 1, AdlerB = 0,
        Events = buffer.create(0), Tracks = buffer.create(0),
        Position = Format.HEADER_BYTES, EventIndex = 0, TrackIndex = 0,
        TrackID = -1, TrackRemaining = 0, TrackEnd = Format.HEADER_BYTES, Tick = 0,
    }
    return job, nil
end

local function openTrack(job: Decoder)
    if job.Position ~= job.TrackEnd then error("Trailing bytes inside track", 0) end
    if job.TrackIndex >= job.Metadata.TrackCount then error("Missing events", 0) end
    requireBytes(job, Format.TRACK_HEADER_BYTES, job.Metadata.TotalBytes)
    local offset = job.Position
    local id = buffer.readu16(job.Input, offset)
    local reserved = buffer.readu16(job.Input, offset + 2)
    local count = buffer.readu32(job.Input, offset + 4)
    local bytes = buffer.readu32(job.Input, offset + 8)
    if id <= job.TrackID or reserved ~= 0 then error("Invalid track ID/order/flags", 0) end
    if count == 0 or count > job.Metadata.EventCount - job.EventIndex then error("Invalid track count", 0) end
    job.Position += Format.TRACK_HEADER_BYTES
    if bytes < count * Format.MIN_WIRE_EVENT_BYTES or bytes > job.Metadata.TotalBytes - job.Position then
        error("Invalid track payload size", 0)
    end
    job.TrackEnd = job.Position + bytes
    job.TrackID = id; job.TrackRemaining = count; job.Tick = 0
    local output = job.TrackIndex * Format.TRACK_INDEX_BYTES
    buffer.writeu16(job.Tracks, output, id)
    buffer.writeu32(job.Tracks, output + 4, job.EventIndex)
    buffer.writeu32(job.Tracks, output + 8, count)
    job.TrackIndex += 1
end

local function readEvent(job: Decoder)
    local tick = job.Tick + varint(job)
    requireBytes(job, 4, job.TrackEnd)
    local note = buffer.readu8(job.Input, job.Position)
    local velocity = buffer.readu8(job.Input, job.Position + 1)
    local instrument = buffer.readu16(job.Input, job.Position + 2)
    job.Position += 4
    local duration = varint(job)
    requireBytes(job, 8, job.TrackEnd)
    local attack = buffer.readu16(job.Input, job.Position)
    local decay = buffer.readu16(job.Input, job.Position + 2)
    local sustain = buffer.readu8(job.Input, job.Position + 4)
    local release = buffer.readu16(job.Input, job.Position + 5)
    local pan = buffer.readi8(job.Input, job.Position + 7)
    job.Position += 8
    if tick > job.Metadata.DurationTicks or duration == 0 or tick + duration > job.Metadata.DurationTicks then
        error("Event extends beyond sequence duration", 0)
    end
    if note > 127 or velocity == 0 or velocity > 127 or instrument > Format.MAX_INSTRUMENT then
        error("Invalid note, velocity, or instrument", 0)
    end
    if attack > Format.MAX_ATTACK_MS or decay > Format.MAX_DECAY_MS or release > Format.MAX_RELEASE_MS
        or sustain > 127 or pan == -128 then error("Invalid envelope or pan", 0) end
    local output = job.EventIndex * Format.EVENT_BYTES
    buffer.writeu32(job.Events, output, tick)
    buffer.writeu32(job.Events, output + 4, duration)
    buffer.writeu8(job.Events, output + 8, note)
    buffer.writeu8(job.Events, output + 9, velocity)
    buffer.writeu16(job.Events, output + 10, instrument)
    buffer.writef32(job.Events, output + 12, attack / 1000)
    buffer.writef32(job.Events, output + 16, decay / 1000)
    buffer.writef32(job.Events, output + 20, sustain / 127)
    buffer.writef32(job.Events, output + 24, release / 1000)
    buffer.writef32(job.Events, output + 28, pan / 127)
    buffer.writeu16(job.Events, output + 32, job.TrackID)
    buffer.writeu32(job.Events, output + 36, job.EventIndex)
    job.Tick = tick; job.EventIndex += 1; job.TrackRemaining -= 1
end

local function step(job: Decoder, maximum: number)
    if job.Phase == "Checksum" then
        local count = math.min(Format.CHECKSUM_BATCH_BYTES, job.Metadata.TotalBytes - job.ChecksumPosition)
        job.AdlerA, job.AdlerB = Checksum.Update(job.Input, job.ChecksumPosition, count, job.AdlerA, job.AdlerB)
        job.ChecksumPosition += count
        if job.ChecksumPosition < job.Metadata.TotalBytes then return end
        if Checksum.Finish(job.AdlerA, job.AdlerB) ~= job.Metadata.Checksum then error("Checksum mismatch", 0) end
        job.Events = buffer.create(job.Metadata.EventCount * Format.EVENT_BYTES)
        job.Tracks = buffer.create(job.Metadata.TrackCount * Format.TRACK_INDEX_BYTES)
        job.Phase = "Events"
        return
    end
    for _ = 1, maximum do
        if job.EventIndex == job.Metadata.EventCount then
            if job.TrackRemaining ~= 0 or job.TrackIndex ~= job.Metadata.TrackCount
                or job.Position ~= job.TrackEnd or job.Position ~= job.Metadata.TotalBytes then
                error("Trailing bytes or track/count mismatch", 0)
            end
            job.Phase = "Complete"
            return
        end
        if job.TrackRemaining == 0 then openTrack(job) end
        readEvent(job)
    end
end

-- Call once per frame for bounded serial work in phase 1; Actor dispatch is phase 4.
function Parser.Step(job: Decoder, maximum: number?): (boolean, string?)
    if job.Phase == "Complete" then return true, nil end
    if job.Phase == "Error" or job.Phase == "Destroyed" then return true, job.Error or "Decoder destroyed" end
    local limit = maximum or Format.DEFAULT_EVENT_BATCH
    if limit ~= limit or limit < 1 or limit > Format.MAX_EVENT_BATCH or limit % 1 ~= 0 then
        return true, "Invalid event batch size"
    end
    local ok, err = pcall(step, job, limit)
    if not ok then
        job.Error = tostring(err); job.Phase = "Error"
        job.Input = buffer.create(0); job.Events = buffer.create(0); job.Tracks = buffer.create(0)
    end
    return job.Phase == "Complete" or job.Phase == "Error", job.Error
end
function Parser.Result(job: Decoder): Sequence?
    if job.Phase ~= "Complete" then return nil end
    return {Metadata = job.Metadata, Events = job.Events, Tracks = job.Tracks}
end
function Parser.Destroy(job: Decoder)
    job.Input = buffer.create(0); job.Events = buffer.create(0); job.Tracks = buffer.create(0)
    job.Phase = "Destroyed"; job.Error = nil
end
return table.freeze(Parser)
