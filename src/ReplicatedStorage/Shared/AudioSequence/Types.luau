--!strict
-- Exports the binary sequence and incremental decoder contracts.
export type Metadata = {
    Version: number, Checksum: number, TotalBytes: number, TrackCount: number,
    TicksPerBeat: number, BPM: number, EventCount: number, DurationTicks: number,
}
export type Sequence = {Metadata: Metadata, Events: buffer, Tracks: buffer}
export type Decoder = {
    Input: buffer, Metadata: Metadata, Phase: string, Error: string?,
    ChecksumPosition: number, AdlerA: number, AdlerB: number,
    Events: buffer, Tracks: buffer, Position: number, EventIndex: number,
    TrackIndex: number, TrackID: number, TrackRemaining: number,
    TrackEnd: number, Tick: number,
}
return {}
