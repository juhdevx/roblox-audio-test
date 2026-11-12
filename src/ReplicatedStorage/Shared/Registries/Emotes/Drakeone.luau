--!strict
-- Reuses PaniniEvent choreography and traversal with the full spectral test track.
local Shared = script.Parent.Parent.Parent
local entry = require(Shared.Utils.TableUtils).Copy(require(script.Parent.ToosieSlide))
entry.Name = "Drakeone"
entry.Order = 14
entry.Default = false
entry.Exclusive = true
entry.Song = {Backend = "Spectral", Track = "Drake___You_Broke_My_Heart__Audio_", Volume = 1, PlaybackSpeed = 1}
return entry

