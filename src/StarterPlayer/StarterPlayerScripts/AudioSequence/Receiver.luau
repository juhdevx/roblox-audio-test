--!strict
-- Reassembles validated chunks in one buffer and requests bounded repairs.
local Shared = game:GetService("ReplicatedStorage").Shared.AudioSequence
local Config = require(Shared.Config)
local Protocol = require(Shared.Protocol)
export type Receipt = {
	Header: Protocol.Header, Data: buffer, Seen: buffer, Received: number,
	Started: number, RepairAt: number,
}
local Receiver = {}
Receiver.__index = Receiver
function Receiver.new(send: (string, any, any?) -> (), completed: (Protocol.Header, buffer) -> (),
	failed: (string) -> ())
	return setmetatable({
		Send = send, Completed = completed, Failed = failed,
		Current = nil :: Receipt?, CompletedToken = "", ExpectedId = "",
	}, Receiver)
end
export type Reassembler = typeof(Receiver.new(nil :: any, nil :: any, nil :: any))
function Receiver.Expect(self: Reassembler, id: string)
	self.ExpectedId = id; self.Current = nil; self.CompletedToken = ""
end
function Receiver.Header(self: Reassembler, header: any)
	if not Protocol.Header(header) or header.Id ~= self.ExpectedId then return end
	if self.CompletedToken == header.Token then self.Send("Ack", header.Token); return end
	if self.Current and self.Current.Header.Token == header.Token then return end
	self.Current = {
		Header = header, Data = buffer.create(header.Bytes), Seen = buffer.create(header.Count),
		Received = 0, Started = os.clock(), RepairAt = os.clock() + Config.RepairInterval,
	}
end
function Receiver.Chunk(self: Reassembler, token: any, index: any, chunk: any)
	local receipt = self.Current
	if not receipt or token ~= receipt.Header.Token or typeof(chunk) ~= "buffer"
		or not Protocol.Integer(index, 1, receipt.Header.Count) then return end
	local offset = (index - 1) * Config.ChunkBytes
	if buffer.len(chunk) ~= math.min(Config.ChunkBytes, receipt.Header.Bytes - offset) then return end
	if buffer.readu8(receipt.Seen, index - 1) ~= 0 then return end
	buffer.copy(receipt.Data, offset, chunk, 0, buffer.len(chunk))
	buffer.writeu8(receipt.Seen, index - 1, 1); receipt.Received += 1
	if receipt.Received == receipt.Header.Count then
		self.Current = nil; self.CompletedToken = token
		-- The parser verifies the complete checksum before the sequence can play.
		self.Send("Ack", token); self.Completed(receipt.Header, receipt.Data)
	end
end
function Receiver.Step(self: Reassembler)
	local receipt = self.Current
	if not receipt then return end
	local now = os.clock()
	if now - receipt.Started > Config.TransferSeconds then
		self.Current = nil; self.Failed("Transfer timed out"); return
	end
	if now < receipt.RepairAt then return end
	receipt.RepairAt = now + Config.RepairInterval
	local missing = {}
	for index = 1, receipt.Header.Count do
		if buffer.readu8(receipt.Seen, index - 1) == 0 then
			table.insert(missing, index)
			if #missing == Config.MaxRepairIndices then break end
		end
	end
	if #missing > 0 then self.Send("Repair", receipt.Header.Token, missing) end
end
function Receiver.Destroy(self: Reassembler)
	self.Current = nil; self.CompletedToken = ""; self.ExpectedId = ""
end
return Receiver
