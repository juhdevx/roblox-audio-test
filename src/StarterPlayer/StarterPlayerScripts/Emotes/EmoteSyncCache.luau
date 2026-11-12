--!strict
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
--!strict
-- Manages EmoteSyncCache for client playback.
local Workspace = game:GetService("Workspace")

local EmoteSyncCache = {}
EmoteSyncCache.__index = EmoteSyncCache

function EmoteSyncCache.new()
	return setmetatable({ entries = {} }, EmoteSyncCache)
end

function EmoteSyncCache:Set(key, data, startTime)
	self.entries[key] = {
		Data = data,
		StartTime = startTime or workspace:GetServerTimeNow(),
	}
end

function EmoteSyncCache:Get(key)
	return self.entries[key]
end

function EmoteSyncCache:Clear(key)
	self.entries[key] = nil
end

function EmoteSyncCache:GetStartTime(key)
	local entry = self.entries[key]
	return entry and entry.StartTime or nil
end

function EmoteSyncCache:GetElapsed(key)
	local startTime = self:GetStartTime(key)
	if not startTime then return nil end
	return math.max(workspace:GetServerTimeNow() - startTime, 0)
end

function EmoteSyncCache:GetProgress(key, length)
	local elapsed = self:GetElapsed(key)
	if not elapsed or not length or length <= 0 then return nil end
	return (elapsed % length) / length
end

function EmoteSyncCache:Destroy()
	table.clear(self.entries)
end

return EmoteSyncCache
