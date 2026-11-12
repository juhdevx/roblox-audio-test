--!strict
-- Retains the original packed segment while its Actor verifies a private copy.
local Validator = {}
Validator.__index = Validator
function Validator.new(actor: Actor, complete: (any) -> (), failed: (string) -> ())
	local self = setmetatable({Actor = actor, Complete = complete, Failed = failed,
		Token = actor:GetAttribute("Generation") or 0, Busy = false, Waiting = false,
		Input = nil :: buffer?, Started = 0, Connection = nil :: RBXScriptConnection?}, Validator)
	self.Connection = (actor.Result :: BindableEvent).Event:Connect(function(token: number, action: string, result: any)
		if token ~= self.Token or not self.Busy then return end
		self.Waiting = false
		if action == "Complete" then self.Busy = false; self.Complete(result)
		elseif action == "Error" then self.Busy = false; self.Failed(tostring(result)) end
	end)
	return self
end
export type Decoder = typeof(Validator.new(nil :: any, nil :: any, nil :: any))
function Validator.Cancel(self: Decoder)
	self.Token += 1; self.Actor:SetAttribute("Generation", self.Token)
	self.Actor:SendMessage("Cancel", self.Token)
	self.Busy = false; self.Waiting = false; self.Input = nil
end
function Validator.Begin(self: Decoder, data: buffer)
	self:Cancel(); self.Busy = true; self.Input = data; self.Started = os.clock()
end
function Validator.Step(self: Decoder)
	if not self.Busy then return end
	if os.clock() - self.Started > 20 then self:Cancel(); self.Failed("Spectral decoder timed out"); return end
	if self.Waiting or not self.Actor:GetAttribute("Ready") then return end
	self.Waiting = true
	if self.Input then self.Actor:SendMessage("Begin", self.Token, self.Input); self.Input = nil
	else self.Actor:SendMessage("Step", self.Token) end
end
function Validator.Destroy(self: Decoder)
	self:Cancel()
	if self.Connection then self.Connection:Disconnect(); self.Connection = nil end
end
return Validator

