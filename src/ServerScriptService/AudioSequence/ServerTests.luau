--!strict
-- Runs opt-in Studio tests for download retries, deduplication and source validation.
local RunService = game:GetService("RunService")
local Catalog = require(script.Parent.Catalog)
local Downloads = require(script.Parent.Downloads)
local Transport = require(script.Parent.Transport)
local Tests = {}
function Tests.Run(): number
	assert(RunService:IsStudio(), "Studio tests only")
	local checks = 0
	local function check(condition: boolean, message: string)
		assert(condition, message); checks += 1
	end
	local embedded = assert(Catalog.Entries.Demo.Embedded)()
	local body = buffer.tostring(embedded)
	check(Catalog.IsAllowed("https://raw.githubusercontent.com/a/b/c.rseq"), "Configured host allowed")
	check(not Catalog.IsAllowed("http://raw.githubusercontent.com/a"), "HTTP rejected")
	check(not Catalog.IsAllowed("https://raw.githubusercontent.com.evil.test/a"), "Suffix spoof rejected")
	check(not Catalog.IsAllowed("https://user@raw.githubusercontent.com/a"), "Credentials rejected")
	check(not Catalog.IsAllowed("https://raw.githubusercontent.com:443/a"), "Explicit port rejected")
	local names = {"__TestA", "__TestB", "__TestBad", "__TestDenied", "__TestDown"}
	Catalog.Entries.__TestA = {Url = "https://raw.githubusercontent.com/test/shared.rseq"}
	Catalog.Entries.__TestB = {Url = "https://raw.githubusercontent.com/test/shared.rseq"}
	Catalog.Entries.__TestBad = {Url = "https://raw.githubusercontent.com/test/bad.rseq"}
	Catalog.Entries.__TestDenied = {Url = "https://evil.test/file.rseq"}
	Catalog.Entries.__TestDown = {Url = "https://raw.githubusercontent.com/test/down.rseq"}
	local downloader: Downloads.Downloader? = nil
	local ok, failure = pcall(function()
		local calls = 0
		downloader = Downloads.new(function(url)
			calls += 1; task.wait(0.05)
			if url:find("bad", 1, true) then return {Success = true, StatusCode = 200, Body = "bad"} end
			if url:find("down", 1, true) then return {Success = false, StatusCode = 503, Body = ""} end
			if calls == 1 then return {Success = false, StatusCode = 503, Body = ""} end
			return {Success = true, StatusCode = 200, Body = body}
		end)
		local loader = downloader :: Downloads.Downloader
		local done, successes = 0, 0
		for index = 1, 5 do
			task.spawn(function()
				local data = loader:Get(if index % 2 == 0 then "__TestA" else "__TestB")
				if data and buffer.tostring(data) == body then successes += 1 end
				done += 1
			end)
		end
		local deadline = os.clock() + 15
		while done < 5 and os.clock() < deadline do task.wait(0.05) end
		check(done == 5 and successes == 5, "Concurrent callers receive one validated source")
		check(calls == 2, "Deduplicate URL and retry transient response")
		check(loader:Get("__TestA") ~= nil and calls == 2, "Server cache hit avoids HTTP")
		check(loader:Get("__TestDenied") == nil and calls == 2, "Allowlist blocks fetch")
		loader.PendingCount = 4
		check(loader:Get("__TestBad") == nil and calls == 2, "Concurrent download budget")
		loader.PendingCount = 0
		check(loader:Get("__TestBad") == nil, "Corrupt payload rejected")
		local prior = calls
		check(loader:Get("__TestDown") == nil and calls == prior + 3, "Outage uses bounded retries")
		check(loader:Get("unknown-id") == nil, "Unknown ID rejected")
		loader:Destroy()
		check(loader.Cache.Bytes == 0 and next(loader.Pending) == nil, "Download cleanup")
		local remote = Instance.new("RemoteEvent")
		local sender = Transport.new(remote)
		local fakePlayer = {} :: any
		for _ = 1, 8 do check(sender:Allow(fakePlayer), "Initial request tokens") end
		check(not sender:Allow(fakePlayer), "Request spam blocked")
		sender:Remove(fakePlayer)
		check(next(sender.Limits) == nil, "Player removal clears rate state")
		sender:Destroy(); remote:Destroy()
	end)
	if downloader then downloader:Destroy() end
	for _, name in names do Catalog.Entries[name] = nil end
	assert(ok, failure)
	script:SetAttribute("PassedChecks", checks)
	print(`[AudioSequence Server] PASS: {checks} checks`)
	return checks
end
return Tests
