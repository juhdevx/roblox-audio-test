--!strict
-- Normalizes inline song data and Sound templates into one playback descriptor.
local Tables = require(script.Parent.TableUtils)
local Resolver = {}
function Resolver.Resolve(definition: any, sounds: Instance?): any
    if definition.Song then return Tables.Copy(definition.Song) end
    local folder = sounds and sounds:FindFirstChild(definition.Name)
    local template = folder and folder:FindFirstChildWhichIsA("Sound")
    if not template then return nil end
    return {Template=definition.Name, SoundId=template.SoundId, Volume=template.Volume,
        PlaybackSpeed=template.PlaybackSpeed, StartTime=template:GetAttribute("StartTime") or 0,
        StartDelay=template:GetAttribute("StartDelay") or 0,
        LoopStartTime=template:GetAttribute("LoopStartTime"), LoopEndTime=template:GetAttribute("LoopEndTime")}
end
return Resolver
