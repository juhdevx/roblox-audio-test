--!strict
-- Validates untrusted transport fields before indexing or allocating buffers.
local Config = require(script.Parent.Config)
local Protocol = {}
export type Header = {
	Token: string, Id: string, Bytes: number, Count: number,
	Checksum: number, Version: number, ChunkBytes: number,
}
function Protocol.Integer(value: any, minimum: number, maximum: number): boolean
	return type(value) == "number" and value == value and value >= minimum
		and value <= maximum and value % 1 == 0
end
function Protocol.Id(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= 64
		and value:match("^[%w_%-]+$") ~= nil
end
function Protocol.Header(value: any): boolean
	return type(value) == "table" and Protocol.Id(value.Token) and Protocol.Id(value.Id)
		and Protocol.Integer(value.Bytes, 40, 4 * 1024 * 1024)
		and value.ChunkBytes == Config.ChunkBytes and value.Version == 1
		and Protocol.Integer(value.Checksum, 0, 4294967295)
		and value.Count == math.ceil(value.Bytes / Config.ChunkBytes)
end
function Protocol.Key(header: Header): string
	return `{header.Id}:{header.Version}:{header.Checksum}:{header.Bytes}`
end
return Protocol
