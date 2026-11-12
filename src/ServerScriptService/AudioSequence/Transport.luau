--!strict
-- Sends bounded reliable chunks and validates repair requests without trusting client URLs.
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage").Shared.AudioSequence
local Config = require(Shared.Config)
local Protocol = require(Shared.Protocol)
type Transfer = {
	Header: Protocol.Header, Data: buffer, Next: number, Expires: number,
	Repairs: {number}, Queued: {[number]: boolean}, LastHeader: number, Credit: number,
}
type Limit = {Tokens: number, Time: number}
local Transport = {}
Transport.__index = Transport
function Transport.new(remote: RemoteEvent)
	return setmetatable({
		Remote = remote, Transfers = {} :: {[Player]: Transfer},
		Limits = {} :: {[Player]: Limit}, Credit = 0, Cursor = 0,
	}, Transport)
end
export type Sender = typeof(Transport.new(nil :: any))
function Transport.Allow(self: Sender, player: Player): boolean
	local now = os.clock()
	local limit = self.Limits[player] or {Tokens = Config.RequestBurst, Time = now}
	self.Limits[player] = limit
	limit.Tokens = math.min(Config.RequestBurst, limit.Tokens + (now - limit.Time) * Config.RequestRate)
	limit.Time = now
	if limit.Tokens < 1 then return false end
	limit.Tokens -= 1
	return true
end
function Transport.Begin(self: Sender, player: Player, id: string, data: buffer)
	assert(Protocol.Id(id) and buffer.len(data) >= 40 and buffer.len(data) <= 4 * 1024 * 1024,
		"Invalid audio transfer")
	local header: Protocol.Header = {
		Token = HttpService:GenerateGUID(false), Id = id, Bytes = buffer.len(data),
		Count = math.ceil(buffer.len(data) / Config.ChunkBytes), ChunkBytes = Config.ChunkBytes,
		Checksum = buffer.readu32(data, 12), Version = buffer.readu16(data, 4),
	}
	assert(Protocol.Header(header), "Unsupported audio transport header")
	self.Transfers[player] = {
		Header = header, Data = data, Next = 1, Expires = os.clock() + Config.TransferSeconds,
		Repairs = {}, Queued = {}, LastHeader = os.clock(), Credit = 0,
	}
	self.Remote:FireClient(player, "Header", header)
end
function Transport.Repair(self: Sender, player: Player, token: any, indices: any)
	local transfer = self.Transfers[player]
	if not transfer or token ~= transfer.Header.Token or type(indices) ~= "table" then return end
	local count = 0
	for key, index in indices do
		count += 1
		if count > Config.MaxRepairIndices or not Protocol.Integer(key, 1, Config.MaxRepairIndices)
			or not Protocol.Integer(index, 1, transfer.Header.Count) then return end
	end
	for _, index in indices do
		if index < transfer.Next and #transfer.Repairs < Config.MaxRepairIndices and not transfer.Queued[index] then
			transfer.Queued[index] = true
			table.insert(transfer.Repairs, index)
		end
	end
end
function Transport.Ack(self: Sender, player: Player, token: any)
	local transfer = self.Transfers[player]
	if transfer and token == transfer.Header.Token then self.Transfers[player] = nil end
end
function Transport.Cancel(self: Sender, player: Player, id: any)
	local transfer = self.Transfers[player]
	if transfer and transfer.Header.Id == id then self.Transfers[player] = nil end
end
function Transport.Step(self: Sender, dt: number)
	if dt <= 0 or dt ~= dt or dt == math.huge then return end
	self.Credit = math.min(16, self.Credit + dt * Config.GlobalChunksPerSecond)
	-- Rotate the first player so a busy server cannot starve later entries.
	local players = {}
	for player in self.Transfers do table.insert(players, player) end
	if #players == 0 then return end
	self.Cursor = self.Cursor % #players + 1
	for offset = 0, #players - 1 do
		local player = players[(self.Cursor + offset - 1) % #players + 1]
		local transfer = self.Transfers[player]
		if not player.Parent or os.clock() >= transfer.Expires then
			self.Transfers[player] = nil
			continue
		end
		if os.clock() - transfer.LastHeader >= 3 then
			transfer.LastHeader = os.clock()
			self.Remote:FireClient(player, "Header", transfer.Header)
		end
		transfer.Credit = math.min(2, transfer.Credit + dt * Config.ChunksPerSecond)
		while self.Credit >= 1 and transfer.Credit >= 1 do
			local index = table.remove(transfer.Repairs, 1)
			if index then transfer.Queued[index] = nil
			elseif transfer.Next <= transfer.Header.Count then index = transfer.Next; transfer.Next += 1
			else break end
			local position = (index - 1) * Config.ChunkBytes
			local chunk = buffer.create(math.min(Config.ChunkBytes, transfer.Header.Bytes - position))
			buffer.copy(chunk, 0, transfer.Data, position, buffer.len(chunk))
			self.Remote:FireClient(player, "Chunk", transfer.Header.Token, index, chunk)
			self.Credit -= 1; transfer.Credit -= 1
		end
	end
end
function Transport.Remove(self: Sender, player: Player)
	self.Transfers[player] = nil; self.Limits[player] = nil
end
function Transport.Destroy(self: Sender)
	table.clear(self.Transfers); table.clear(self.Limits)
end
return Transport

