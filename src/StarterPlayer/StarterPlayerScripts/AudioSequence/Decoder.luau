--!strict
-- Coordinates one Actor job with bounded messages and cancellation generations.
local Shared = game:GetService("ReplicatedStorage").Shared.AudioSequence
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Decoder = {}
Decoder.__index = Decoder
function Decoder.new(actor: Actor, completed: (Types.Sequence) -> (), failed: (string) -> ())
	local self = setmetatable({
		Actor = actor, Completed = completed, Failed = failed, Generation = actor:GetAttribute("DecodeGeneration") or 0,
		Busy = false, Waiting = false, Started = 0, Written = 0,
		Sequence = nil :: Types.Sequence?, Input = nil :: buffer?,
		Connection = nil :: RBXScriptConnection?,
	}, Decoder)
	self.Connection = (actor.Result :: BindableEvent).Event:Connect(function(generation: number, action: string, a: any, b: any, c: any)
		if generation ~= self.Generation or not self.Busy then return end
		self.Waiting = false
		if action == "Error" then
			self:Cancel(); self.Failed(tostring(a))
		elseif action == "Begin" then
			self.Sequence = {Metadata = a, Events = buffer.create(a.EventCount * 40), Tracks = buffer.create(0)}
		elseif action == "Batch" and self.Sequence then
			if b then
				if a ~= self.Written or a * 40 + buffer.len(b) > buffer.len(self.Sequence.Events) then
					self:Cancel(); self.Failed("Invalid Actor batch"); return
				end
				buffer.copy(self.Sequence.Events, a * 40, b)
				self.Written += buffer.len(b) / 40
			end
			if c then
				if self.Written ~= self.Sequence.Metadata.EventCount then
					self:Cancel(); self.Failed("Incomplete Actor result"); return
				end
				self.Sequence.Tracks = c
				local result = self.Sequence
				self.Sequence = nil; self.Busy = false
				self.Completed(result)
			end
		end
	end)
	return self
end
export type ClientDecoder = typeof(Decoder.new(nil :: any, nil :: any, nil :: any))
function Decoder.Cancel(self: ClientDecoder)
	self.Generation += 1
	self.Actor:SetAttribute("DecodeGeneration", self.Generation)
	self.Actor:SendMessage("Cancel", self.Generation)
	self.Busy = false; self.Waiting = false; self.Sequence = nil; self.Input = nil
end
function Decoder.Begin(self: ClientDecoder, data: buffer)
	self:Cancel()
	self.Busy = true; self.Started = os.clock(); self.Written = 0; self.Input = data
end
function Decoder.Step(self: ClientDecoder)
	if not self.Busy then return end
	if os.clock() - self.Started > Config.DecodeTimeout then
		self:Cancel(); self.Failed("Parallel decoder timed out"); return
	end
	if self.Waiting or not self.Actor:GetAttribute("Ready") then return end
	self.Waiting = true
	if self.Input then
		self.Actor:SendMessage("Begin", self.Generation, self.Input); self.Input = nil
	else self.Actor:SendMessage("Step", self.Generation) end
end
function Decoder.Destroy(self: ClientDecoder)
	self:Cancel()
	if self.Connection then self.Connection:Disconnect(); self.Connection = nil end
end
return Decoder
