--!strict
-- Computes audio loop positions and circular drift without starting tasks.
local Clock = {}
function Clock.Position(elapsed: number, song: any, length: number): number
    local position = (song.StartTime or 0) + elapsed * (song.PlaybackSpeed or 1)
    local first = song.LoopStartTime
    local last = if song.LoopEndTime and song.LoopEndTime > 0 then song.LoopEndTime else length
    if first and last > first and position >= last then return first + (position-last) % (last-first) end
    if not first and length > 0 then return position % length end
    return position
end
function Clock.Drift(a: number, b: number, length: number): number
    local difference = math.abs(a-b)
    return if length > 0 then math.min(difference, math.abs(length-difference)) else difference
end
return Clock
