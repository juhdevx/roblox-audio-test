--!strict
-- Downloads and validates catalog entries with deduplication and a bounded TTL cache.
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage").Shared.AudioSequence
local Config = require(Shared.Config)
local Parser = require(Shared.Parser)
local LRU = require(Shared.LRU)
local Catalog = require(script.Parent.Catalog)
type Pending = {Done: boolean, Data: buffer?, Error: string?}
export type Fetch = (string) -> {Success: boolean, StatusCode: number, Body: string}
local Downloads = {}
Downloads.__index = Downloads
function Downloads.new(fetch: Fetch?, catalog: any?, validate: ((buffer) -> (boolean, string?))?)
	return setmetatable({
		Cache = LRU.new(Config.ServerCacheBytes),
		Catalog = catalog or Catalog, Validator = validate or Downloads.Validate,
		Pending = {} :: {[string]: Pending}, Alive = true,
		PendingCount = 0,
		Tokens = Config.HttpRequestsPerMinute, Refill = os.clock(),
		Fetch = fetch or function(url: string)
			return HttpService:RequestAsync({Url = url, Method = "GET", Timeout = Config.HttpTimeout})
		end,
	}, Downloads)
end
export type Downloader = typeof(Downloads.new())
function Downloads.Validate(data: buffer): (boolean, string?)
	local job, message = Parser.Begin(data)
	if not job then return false, message end
	while true do
		local done, problem = Parser.Step(job, Config.DecodeBatch)
		if done then Parser.Destroy(job); return problem == nil, problem end
		task.wait()
	end
end
function Downloads.Get(self: Downloader, id: string): (buffer?, string?)
	if not self.Alive then return nil, "Downloader stopped" end
	local entry = self.Catalog.Entries[id]
	if not entry then return nil, "Unknown catalog ID" end
	local key = entry.Url or id
	local cached = self.Cache:Get(key, os.clock())
	if cached then return cached, nil end
	local existing = self.Pending[key]
	if existing then
		while self.Alive and not existing.Done do task.wait(0.05) end
		return existing.Data, existing.Error or (if self.Alive then nil else "Downloader stopped")
	end
	local pending: Pending = {Done = false}
	if self.PendingCount >= Config.MaxPendingDownloads then return nil, "Download queue is busy" end
	self.PendingCount += 1
	self.Pending[key] = pending
	local ok, failure = pcall(function()
		local data: buffer? = nil
		if entry.Embedded then
			data = entry.Embedded()
		else
			assert(entry.Url and self.Catalog.IsAllowed(entry.Url), "Source URL is not allowlisted")
			for attempt = 1, Config.HttpAttempts do
				assert(self.Alive, "Downloader stopped")
				local now = os.clock()
				self.Tokens = math.min(Config.HttpRequestsPerMinute,
					self.Tokens + (now - self.Refill) * Config.HttpRequestsPerMinute / 60)
				self.Refill = now
				assert(self.Tokens >= 1, "HTTP request budget exhausted")
				self.Tokens -= 1
				-- RequestAsync also has a native timeout. A late result is never used.
				local finished, success, response = false, false, nil :: any
				task.spawn(function()
					success, response = pcall(self.Fetch, entry.Url :: string)
					finished = true
				end)
				local deadline = os.clock() + Config.HttpTimeout + 1
				while self.Alive and not finished and os.clock() < deadline do task.wait(0.05) end
				assert(self.Alive, "Downloader stopped")
				if not finished then error("HTTP timeout; late response discarded") end
				if success and response.Success and response.StatusCode == 200 then
					assert(#response.Body <= 4 * 1024 * 1024, "Payload exceeds 4 MiB")
					data = buffer.fromstring(response.Body)
					break
				end
				local status = if success then response.StatusCode else 0
				if status >= 400 and status < 500 and status ~= 408 and status ~= 429 then
					error(`HTTP {status}`)
				end
				if attempt == Config.HttpAttempts then error(`Download failed (HTTP {status})`) end
				task.wait(2 ^ (attempt - 1))
			end
		end
		assert(data, "Source returned no data")
		local valid, problem = self.Validator(data)
		assert(valid, problem or "Invalid sequence")
		assert(self.Alive, "Downloader stopped")
		pending.Data = data
		self.Cache:Put(key, data, buffer.len(data), os.clock() + Config.CacheSeconds)
	end)
	if not ok then pending.Error = tostring(failure) end
	pending.Done = true
	self.Pending[key] = nil
	self.PendingCount = math.max(0, self.PendingCount - 1)
	return pending.Data, pending.Error
end
function Downloads.Destroy(self: Downloader)
	self.Alive = false
	self.Cache:Destroy()
	for _, pending in self.Pending do pending.Done = true; pending.Error = "Downloader stopped" end
	table.clear(self.Pending)
	self.PendingCount = 0
end
return Downloads

