--!strict
-- Decodes bounded batches inside a dedicated Actor and transfers only newly written records.
local Shared = game:GetService("ReplicatedStorage").Shared.AudioSequence
local Parser = require(Shared.Parser)
local Types = require(Shared.Types)
local Config = require(Shared.Config)
local Worker = {}
function Worker.Start(actor: Actor, output: BindableEvent): () -> ()
	local job: Types.Decoder? = nil
	local token = 0
	local connections: {RBXScriptConnection} = {}
	table.insert(connections, actor:BindToMessageParallel("Begin", function(generation: number, data: buffer)
		if generation < token then return end
		if job then Parser.Destroy(job) end
		token = generation
		local nextJob, message = Parser.Begin(data)
		job = nextJob
		task.synchronize()
		if generation ~= token then return end
		if nextJob then output:Fire(generation, "Begin", nextJob.Metadata)
		else output:Fire(generation, "Error", message) end
	end))
	table.insert(connections, actor:BindToMessageParallel("Step", function(generation: number)
		if generation ~= token or not job then return end
		local active = job
		local startIndex = active.EventIndex
		local done, problem = Parser.Step(active, Config.DecodeBatch)
		local written = active.EventIndex - startIndex
		local batch: buffer? = nil
		if not problem and written > 0 then
			batch = buffer.create(written * 40)
			buffer.copy(batch, 0, active.Events, startIndex * 40, written * 40)
		end
		local tracks = if done and not problem then active.Tracks else nil
		task.synchronize()
		if problem then output:Fire(generation, "Error", problem)
		else output:Fire(generation, "Batch", startIndex, batch, tracks) end
		if done then
			Parser.Destroy(active)
			if job == active then job = nil end
		end
	end))
	table.insert(connections, actor:BindToMessageParallel("Cancel", function(generation: number)
		if generation < token then return end
		token = generation
		if job then Parser.Destroy(job); job = nil end
	end))
	actor:SetAttribute("Ready", true)
	return function()
		for _, connection in connections do connection:Disconnect() end
		table.clear(connections)
		if job then Parser.Destroy(job); job = nil end
		actor:SetAttribute("Ready", false)
	end
end
return Worker
