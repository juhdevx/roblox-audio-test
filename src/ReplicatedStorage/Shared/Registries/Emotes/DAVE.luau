--!strict
-- Reuses PaniniEvent choreography and traversal with the full spectral test track.
local Shared = script.Parent.Parent.Parent
local entry = require(Shared.Utils.TableUtils).Copy(require(script.Parent.PopularVibe))
entry.Name = "GD"
entry.Order = 15
entry.Default = false
entry.Exclusive = true
entry.Song = {Backend = "Spectral", Track = "maybe", Volume = 1, PlaybackSpeed = 1}
return entry

