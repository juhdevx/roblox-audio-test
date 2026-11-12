--!strict
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
--!strict
-- Manages EmotePreloader for client playback.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AnimationLengthCache = require(clientRoot.Emotes.AnimationLengthCache)

local EmotePreloader = {}
EmotePreloader.__index = EmotePreloader

function EmotePreloader.new(lengthCache, soundFolder)
	local self = setmetatable({}, EmotePreloader)
	self.lengthCache = lengthCache or AnimationLengthCache.new()
	self.soundFolder = soundFolder or ReplicatedStorage.Assets.Sounds
	self.container = Instance.new("Folder")
	self.container.Name = "EmotePreload"
	self.container.Parent = Workspace
	return self
end

function EmotePreloader:PreloadAll(inventory)
	local animIds = {}
	local toPreload = {}

	for _, data in ipairs(inventory) do
		if data.Loop then
			table.insert(animIds, data.Loop)
		end
		if not data.Song and self.soundFolder then
			local folder = self.soundFolder:FindFirstChild(data.Name)
			if folder then
				local sound = folder:FindFirstChildWhichIsA("Sound")
				if sound then
					if not sound.IsLoaded then
						table.insert(toPreload, sound)
					end
				end
			end
		elseif data.Song and data.Song.SoundId then
			local temp = Instance.new("Sound")
			temp.SoundId = data.Song.SoundId
			temp.Parent = self.container
			table.insert(toPreload, temp)
		end
	end

	if #animIds > 0 then
		self.lengthCache:Preload(animIds)
	end

	if #toPreload > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(toPreload)
		end)
		for _, obj in ipairs(toPreload) do
			if obj:IsDescendantOf(self.container) then
				obj:Destroy()
			end
		end
	end
end

function EmotePreloader:Destroy()
	table.clear(self)
	if self.container then
		self.container:Destroy()
		self.container = nil
	end
end

return EmotePreloader
