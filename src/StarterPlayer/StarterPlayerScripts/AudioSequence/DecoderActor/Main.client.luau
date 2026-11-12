--!strict
-- Boots the parallel decoding worker in its Actor.
local actor = script.Parent :: Actor
local Worker = require(actor.Parent.DecoderWorker)
local stop = Worker.Start(actor, actor.Result :: BindableEvent)
local connection: RBXScriptConnection?
connection = actor.Destroying:Connect(function()
	if connection then connection:Disconnect(); connection = nil end
	stop()
end)
