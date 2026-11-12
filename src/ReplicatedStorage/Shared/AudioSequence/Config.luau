--!strict
-- Centralizes bounded transfer, decoding, cache and playback settings.
return table.freeze({
	ChunkBytes = 8192,
	TransferSeconds = 120,
	ChunksPerSecond = 10,
	GlobalChunksPerSecond = 160,
	RepairInterval = 1.5,
	MaxRepairIndices = 24,
	RequestBurst = 8,
	RequestRate = 2,
	ServerCacheBytes = 16 * 1024 * 1024,
	ClientCacheBytes = 16 * 1024 * 1024,
	CacheSeconds = 300,
	HttpAttempts = 3,
	HttpTimeout = 10,
	HttpRequestsPerMinute = 60,
	MaxPendingDownloads = 4,
	DecodeBatch = 256,
	DecodeTimeout = 120,
	Lookahead = 0.08,
	MaxNotesPerFrame = 256,
	MaxVoices = 32,
})
