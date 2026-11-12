--!strict
-- Bounds cached references by bytes and optional expiration.
export type Entry = {Value: any, Bytes: number, Used: number, Expires: number}
export type Cache = {
	Entries: {[string]: Entry}, Bytes: number, Limit: number, Clock: number,
	Get: (Cache, string, number) -> any,
	Put: (Cache, string, any, number, number) -> (),
	Remove: (Cache, string) -> (),
	Destroy: (Cache) -> (),
}
local LRU = {}
LRU.__index = LRU
function LRU.new(limit: number): Cache
	return setmetatable({Entries = {}, Bytes = 0, Limit = limit, Clock = 0}, LRU) :: any
end
function LRU.Remove(self: Cache, key: string)
	local entry = self.Entries[key]
	if entry then self.Bytes -= entry.Bytes; self.Entries[key] = nil end
end
function LRU.Get(self: Cache, key: string, now: number): any
	local entry = self.Entries[key]
	if not entry then return nil end
	if now >= entry.Expires then self:Remove(key); return nil end
	self.Clock += 1; entry.Used = self.Clock
	return entry.Value
end
function LRU.Put(self: Cache, key: string, value: any, bytes: number, expires: number)
	self:Remove(key)
	if bytes > self.Limit or bytes < 0 then return end
	while self.Bytes + bytes > self.Limit do
		local oldest: string? = nil
		local age = math.huge
		for id, entry in self.Entries do
			if entry.Used < age then age = entry.Used; oldest = id end
		end
		if not oldest then break end
		self:Remove(oldest)
	end
	self.Clock += 1
	self.Entries[key] = {Value = value, Bytes = bytes, Used = self.Clock, Expires = expires}
	self.Bytes += bytes
end
function LRU.Destroy(self: Cache)
	table.clear(self.Entries); self.Bytes = 0
end
return LRU
