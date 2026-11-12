--!strict
-- Defines the RSEQ v1 wire format, decoded layout, and allocation limits.
-- All fixed-width numbers are little-endian; offsets below are zero-based.
-- Header (40 bytes): "RSEQ", u16 version, u16 headerBytes, u32 totalBytes,
-- u32 Adler32 (whole file, bytes 12..15 treated as zero), u16 trackCount,
-- u16 ticksPerBeat, f32 BPM, u32 eventCount, u32 durationTicks, u32 flags=0,
-- u32 reserved=0. Track IDs must increase; each track is stored contiguously.
-- Track header (12 bytes): u16 ID, u16 reserved=0, u32 count, u32 bodyBytes.
-- Event: ULEB128 deltaTicks, u8 note, u8 velocity, u16 sample instrument,
-- ULEB128 durationTicks, u16 attackMs, u16 decayMs, u8 sustain127,
-- u16 releaseMs, i8 pan127. Varints are canonical, at most four bytes.
-- A note ends within durationTicks; release tails are additional seconds.
-- Decoded events are track-major, chronological within each track, NOT globally
-- sorted. Later playback must merge the track cursors rather than scan as one.
-- Decoded event (40 bytes): u32 tick, u32 duration, u8 note, u8 velocity,
-- u16 instrument, f32 attack/decay/sustain/release/pan at 12/16/20/24/28,
-- u16 trackID at 32, u16 reserved at 34, u32 original ordinal at 36.
-- Track index (12 bytes): u16 ID, u16 reserved, u32 firstEvent, u32 count.
return table.freeze({
    MAGIC = 0x51455352,
    VERSION = 1,
    HEADER_BYTES = 40,
    CHECKSUM_OFFSET = 12,
    TRACK_HEADER_BYTES = 12,
    EVENT_BYTES = 40,
    TRACK_INDEX_BYTES = 12,
    MIN_WIRE_EVENT_BYTES = 14,
    MAX_FILE_BYTES = 4 * 1024 * 1024,
    MAX_EVENTS = 65536,
    MAX_TRACKS = 64,
    MAX_TICKS = 0x0FFFFFFF,
    MAX_INSTRUMENT = 255,
    MAX_ATTACK_MS = 10000,
    MAX_DECAY_MS = 10000,
    MAX_RELEASE_MS = 20000,
    MIN_BPM = 20,
    MAX_BPM = 400,
    MIN_TICKS_PER_BEAT = 24,
    MAX_TICKS_PER_BEAT = 9600,
    CHECKSUM_BATCH_BYTES = 32768,
    DEFAULT_EVENT_BATCH = 256,
    MAX_EVENT_BATCH = 1024,
})
