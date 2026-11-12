--!strict
-- Deduplicates trusted video downloads and limits HTTP work and cached bytes.
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.VideoSequence.Config)
local LRU = require(Shared.AudioSequence.LRU)
type Pending = {Done: boolean, Data: buffer?, Error: string?}
export type Fetch = (string) -> {Success: boolean, StatusCode: number, Body: string}
export type Validator = (buffer, string) -> (boolean, string?)
local Downloads = {}
Downloads.__index = Downloads
function Downloads.new(catalog: any, validate: Validator, fetch: Fetch?)
	return setmetatable({
		Catalog = catalog, Validator = validate, Cache = LRU.new(Config.ServerCacheBytes),
		Pending = {} :: {[string]: Pending}, PendingCount = 0, Alive = true,
		Tokens = Config.HttpRequestsPerMinute, Refill = os.clock(),
		Fetch = fetch or function(url: string)
			return HttpService:RequestAsync({Url = url, Method = "GET", Timeout = Config.HttpTimeout})
		end,
	}, Downloads)
end
export type Downloader = typeof(Downloads.new(nil :: any, nil :: any))
function Downloads.Get(self: Downloader, id: string): (buffer?, string?)
	if not self.Alive then return nil, "Video downloader stopped" end
	local entry = self.Catalog.Entries[id]
	if not entry then return nil, "Unknown video segment" end
	local key = entry.Url
	if type(key) ~= "string" or not self.Catalog.IsAllowed(key) then return nil, "Video source is not allowlisted" end
	local cached = self.Cache:Get(key, os.clock())
	if cached then return cached, nil end
	local existing = self.Pending[key]
	if existing then
		while self.Alive and not existing.Done do task.wait(0.05) end
		if not self.Alive then return nil, "Video downloader stopped" end
		return existing.Data, existing.Error
	end
	if self.PendingCount >= Config.MaxPendingDownloads then return nil, "Video download queue is busy" end
	local pending: Pending = {Done = false}
	self.Pending[key] = pending
	self.PendingCount += 1
	local ok, problem = pcall(function()
		local bytes: buffer? = nil
		for attempt = 1, Config.HttpAttempts do
			assert(self.Alive, "Video downloader stopped")
			local now = os.clock()
			self.Tokens = math.min(Config.HttpRequestsPerMinute,
				self.Tokens + (now - self.Refill) * Config.HttpRequestsPerMinute / 60)
			self.Refill = now
			assert(self.Tokens >= 1, "Video HTTP request budget exhausted")
			self.Tokens -= 1
			local finished, success, response = false, false, nil :: any
			task.spawn(function()
				success, response = pcall(self.Fetch, key)
				finished = true
			end)
			local deadline = os.clock() + Config.HttpTimeout + 1
			while self.Alive and not finished and os.clock() < deadline do task.wait(0.05) end
			assert(self.Alive, "Video downloader stopped")
			if not finished then error("Video HTTP timeout; late result discarded") end
			if success and response.Success and response.StatusCode == 200 then
				assert(type(response.Body) == "string" and #response.Body >= 40
					and #response.Body <= Config.MaxSegmentBytes, "Video segment exceeds its byte limit")
				bytes = buffer.fromstring(response.Body)
				break
			end
			local status = if success then response.StatusCode else 0
			if status >= 400 and status < 500 and status ~= 408 and status ~= 429 then
				error(`Video HTTP {status}`)
			end
			if attempt == Config.HttpAttempts then error(`Video download failed (HTTP {status})`) end
			task.wait(2 ^ (attempt - 1))
		end
		assert(bytes, "Video source returned no data")
		local valid, message = self.Validator(bytes, id)
		assert(valid, message or "Invalid video segment")
		assert(self.Alive, "Video downloader stopped")
		pending.Data = bytes
		self.Cache:Put(key, bytes, buffer.len(bytes), os.clock() + Config.CacheSeconds)
	end)
	if not ok then pending.Error = tostring(problem) end
	pending.Done = true
	if self.Pending[key] == pending then self.Pending[key] = nil end
	self.PendingCount = math.max(0, self.PendingCount - 1)
	return pending.Data, pending.Error
end
function Downloads.Destroy(self: Downloader)
	if not self.Alive then return end
	self.Alive = false
	self.Cache:Destroy()
	for _, pending in self.Pending do
		pending.Data = nil
		pending.Error = "Video downloader stopped"
		pending.Done = true
	end
	table.clear(self.Pending)
	self.PendingCount = 0
end
return Downloads

