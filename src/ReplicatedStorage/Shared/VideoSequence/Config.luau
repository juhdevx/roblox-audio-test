--!strict
-- Bounds external video transfer, memory and retry costs independently of music streaming.
return table.freeze({
	ChunkBytes = 8192,
	ChunksPerSecond = 96,
	GlobalChunksPerSecond = 768,
	TransferSeconds = 60,
	RepairInterval = 1.5,
	MaxRepairIndices = 16,
	RequestBurst = 20,
	RequestRate = 8,
	MaxSegmentBytes = 4 * 1024 * 1024,
	ServerCacheBytes = 96 * 1024 * 1024,
	ClientCacheBytes = 96 * 1024 * 1024,
	CacheSeconds = 300,
	HttpTimeout = 10,
	HttpAttempts = 3,
	HttpRequestsPerMinute = 40,
	MaxPendingDownloads = 3,
	StartupSeconds = 8,
	PrefetchSeconds = 24,
	PrepareTimeout = 35,
	DecodeBudgetMs = 4,
	ValidateBudgetMs = 2,
	StatusHz = 4,
	ScreenHeight = 10,
	ScreenScaleMin = 0.75,
	ScreenScaleMax = 1.5,
	ScreenOffset = 0.5, -- Clearance between the screen's lower edge and the rig's floor.
	ScreenMaxDistance = 100,
	ScreenPartName = "VideoEmoteScreen",
})

