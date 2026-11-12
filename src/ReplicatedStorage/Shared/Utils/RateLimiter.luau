--!strict
-- Limits requests per player/action with a token bucket and explicit cleanup.
local RateLimiter = {}
RateLimiter.__index = RateLimiter
function RateLimiter.new(capacity: number, refill: number)
    return setmetatable({_buckets = {}, _capacity = capacity, _refill = refill}, RateLimiter)
end
function RateLimiter:Allow(player: Player, action: string): boolean
    local buckets = self._buckets[player]
    if not buckets then buckets = {}; self._buckets[player] = buckets end
    local now = os.clock()
    local bucket = buckets[action] or {tokens = self._capacity, time = now}
    buckets[action] = bucket
    bucket.tokens = math.min(self._capacity, bucket.tokens + (now - bucket.time) * self._refill)
    bucket.time = now
    if bucket.tokens < 1 then return false end
    bucket.tokens -= 1
    return true
end
function RateLimiter:Remove(player: Player) self._buckets[player] = nil end
function RateLimiter:Destroy() table.clear(self._buckets) end
return RateLimiter
