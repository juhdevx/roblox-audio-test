--!strict
-- Reuses PaniniEvent choreography and traversal with the full spectral test track.
local Shared = script.Parent.Parent.Parent
local experiment = require(Shared.Config.AudioExperimentConfig).TestSound
local entry = require(Shared.Utils.TableUtils).Copy(require(script.Parent.PaniniEvent))
entry.Name = "TestSound"
entry.Order = 13
entry.Default = false
entry.Exclusive = true
entry.Song = {Backend = "Spectral", Track = if experiment.Enabled then experiment.ExperimentalTrack else experiment.StandardTrack,
	Volume = 1, PlaybackSpeed = 1}
return entry

