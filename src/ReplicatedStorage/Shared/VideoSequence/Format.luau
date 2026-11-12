--!strict
-- Keeps existing RVF1 clips compatible while routing modern RVF2 frames to the native decompressor.
local Legacy = require(script.Parent.CodecV1)
local Modern = require(script.Parent.CodecV2)
local Format = {MAGIC = Legacy.MAGIC, HEADER_BYTES = 64, MAX_BYTES = Modern.MAX_BYTES}
export type Header = Legacy.Header
export type Job = {Header: any, Inner: any, Codec: any}
local function codecFor(data: buffer): any?
	if buffer.len(data) < 4 then return nil end
	local magic = buffer.readu32(data, 0)
	return if magic == Legacy.MAGIC then Legacy elseif magic == Modern.MAGIC then Modern else nil
end
function Format.Header(data: buffer): (any?, string?)
	local codec = codecFor(data)
	if not codec then return nil, "Unsupported video format" end
	return codec.Header(data)
end
function Format.Begin(data: buffer): (Job?, string?)
	local codec = codecFor(data)
	if not codec then return nil, "Unsupported video format" end
	local inner, reason = codec.Begin(data)
	if not inner then return nil, reason end
	return {Header = inner.Header, Inner = inner, Codec = codec}, nil
end
function Format.Step(job: Job): (boolean, string?)
	return job.Codec.Step(job.Inner)
end
function Format.Validate(data: buffer): (boolean, string?)
	local job, reason = Format.Begin(data)
	if not job then return false, reason end
	while true do
		local deadline = os.clock() + 0.002
		repeat
			local done, problem = Format.Step(job)
			if done then return problem == nil, problem end
		until os.clock() >= deadline
		task.wait()
	end
end
function Format.Prepare(encoding: number, budgetMs: number?, header: any?): boolean
	if encoding ~= 2 then return true end
	return if header then Modern.PrepareFor(header, budgetMs) else Modern.Prepare(budgetMs)
end
Format.Decoder = {new = function(data: buffer): any
	local codec = codecFor(data)
	assert(codec, "Unsupported video format")
	return codec.Decoder.new(data)
end}
return Format
