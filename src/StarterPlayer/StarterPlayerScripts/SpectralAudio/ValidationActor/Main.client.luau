--!strict
-- Boots the spectral validator inside its Actor.
local actor = script.Parent :: Actor
local stop = require(actor.Parent.ValidatorWorker).Start(actor, actor.Result :: BindableEvent)
script.Destroying:Once(stop)

