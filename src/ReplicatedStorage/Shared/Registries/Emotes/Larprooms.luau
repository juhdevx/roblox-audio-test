--!strict
-- Pairs PaniniEvent choreography with the external YippeVideo image and audio streams.
local Shared = script.Parent.Parent.Parent
local entry = require(Shared.Utils.TableUtils).Copy(require(script.Parent.PaniniEvent))
entry.Name = "Larprooms"
entry.Order = 16
entry.Default = false
entry.Exclusive = true
entry.DisableEmoteCamera = true
entry.Song = {Backend = "Spectral", Track = "YippeVideo", Video = "YippeVideo", Volume = 1, PlaybackSpeed = 1}
return entry

