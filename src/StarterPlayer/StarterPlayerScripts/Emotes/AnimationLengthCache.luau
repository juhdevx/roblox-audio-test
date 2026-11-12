--!strict
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
--!strict
-- Manages AnimationLengthCache for client playback.
local ContentProvider = game:GetService("ContentProvider")

local CONFIG = {
	ResolveTimeout = 8,
	PollInterval = 0.05,
}

local AnimationLengthCache = {}
AnimationLengthCache.__index = AnimationLengthCache

function AnimationLengthCache.new()
	local self = setmetatable({}, AnimationLengthCache)
	self.lengths = {}
	self.container = Instance.new("Folder")
	self.container.Name = "AnimationPreload"
	self.container.Parent = workspace
	return self
end

function AnimationLengthCache:Preload(animationIds)
	local instances = {}
	for _, id in ipairs(animationIds) do
		if id and not self.lengths[id] then
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			animation.Parent = self.container
			table.insert(instances, animation)
		end
	end

	if #instances == 0 then
		return
	end

	pcall(function()
		ContentProvider:PreloadAsync(instances)
	end)

	for _, animation in ipairs(instances) do
		animation:Destroy()
	end
end

function AnimationLengthCache:Get(animationId)
	return self.lengths[animationId]
end

function AnimationLengthCache:Resolve(track, animationId)
	local cached = self.lengths[animationId]
	if cached then
		return cached
	end

	local deadline = os.clock() + CONFIG.ResolveTimeout
	local length = 0

	while os.clock() < deadline do
		local ok, currentLength = pcall(function()
			return track.Length
		end)
		if not ok then
			return nil
		end
		if currentLength > 0 then
			length = currentLength
			break
		end
		task.wait(CONFIG.PollInterval)
	end

	if length > 0 then
		self.lengths[animationId] = length
		return length
	end

	return nil
end

function AnimationLengthCache:Destroy()
	table.clear(self.lengths)
	if self.container then
		self.container:Destroy()
		self.container = nil
	end
end

return AnimationLengthCache
