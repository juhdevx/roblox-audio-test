--!strict
-- Checks spectral segments in bounded parallel Actor messages.
local Format = require(game:GetService("ReplicatedStorage").Shared.SpectralAudio.Format)
local Worker = {}
function Worker.Start(actor: Actor, output: BindableEvent): () -> ()
	local token = 0
	local job: Format.Job? = nil
	local connections: {RBXScriptConnection} = {}
	table.insert(connections, actor:BindToMessageParallel("Begin", function(generation: number, data: buffer)
		if generation < token then return end
		token = generation
		local nextJob, problem = Format.Begin(data)
		job = nextJob
		task.synchronize()
		if token == generation then output:Fire(generation, if problem then "Error" else "Ready", problem) end
	end))
	table.insert(connections, actor:BindToMessageParallel("Step", function(generation: number)
		if token ~= generation or not job then return end
		local active = job
		local done, problem = Format.Step(active)
		if done then job = nil end
		task.synchronize()
		if token ~= generation then return end
		if done then output:Fire(generation, if problem then "Error" else "Complete", problem or active.Header)
		else output:Fire(generation, "Ready") end
	end))
	table.insert(connections, actor:BindToMessageParallel("Cancel", function(generation: number)
		if generation >= token then token = generation; job = nil end
	end))
	actor:SetAttribute("Ready", true)
	return function()
		for _, connection in connections do connection:Disconnect() end
		table.clear(connections); job = nil; actor:SetAttribute("Ready", false)
	end
end
return Worker

