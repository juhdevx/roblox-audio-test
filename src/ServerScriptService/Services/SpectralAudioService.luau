--!strict
-- Serves validated spectral segments through the existing bounded download and transport layers.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage").Shared
local Protocol = require(Shared.AudioSequence.Protocol)
local Format = require(Shared.SpectralAudio.Format)
local Downloads = require(script.Parent.Parent.AudioSequence.Downloads)
local Transport = require(script.Parent.Parent.AudioSequence.Transport)
local Catalog = require(script.Parent.Parent.AudioSequence.SpectralCatalog)
local SpectralConfig = require(Shared.SpectralAudio.Config)
local LRU = require(Shared.AudioSequence.LRU)
local Service = {}
local connections: {RBXScriptConnection} = {}
local downloader: any
local sender: any
local request: RemoteEvent
local dataRemote: RemoteEvent
local alive = false
local loading: {[Player]: {Id: string, Token: number}} = {}
local nextRequest = 0
local lastLoad: {[Player]: number} = {}
local warmQueue: {string} = {}
local warmQueued: {[string]: boolean} = {}
local warming = false
local generation = 0
local function enqueueWarm(id: string)
	if not Catalog.Entries[id] or warmQueued[id] or #warmQueue >= 32 then return end
	warmQueued[id] = true; table.insert(warmQueue, id)
end
local function warmNext(id: string)
	local name, suffix = id:match("^(.*)_(%d%d%d)$")
	local track = name and Catalog.Manifest[name]
	if not track or not suffix then return end
	local nextPart = (tonumber(suffix) + 1) % track.Segments
	enqueueWarm(`{name}_{string.format("%03d", nextPart)}`)
end
function Service.Init(dependencies: any)
	request = dependencies.RemoteService.Get("SpectralAudio", "Request")
	dataRemote = dependencies.RemoteService.Get("SpectralAudio", "Data")
	downloader = Downloads.new(nil, Catalog, Format.Validate)
	downloader.Cache:Destroy()
	downloader.Cache = LRU.new(SpectralConfig.ServerCacheBytes)
	sender = Transport.new(dataRemote)
end
function Service.Start()
	if alive then return end
	alive = true
	generation += 1
	local currentGeneration = generation
	local warmed = 0
	for name, track in Catalog.Manifest do
		if track.Preload and warmed < 8 then enqueueWarm(`{name}_000`); warmed += 1 end
	end
	table.insert(connections, request.OnServerEvent:Connect(function(player, action: any, a: any, b: any)
		if not sender:Allow(player) then return end
		if action == "Manifest" then dataRemote:FireClient(player, "Manifest", Catalog.Manifest)
		elseif action == "Ack" then sender:Ack(player, a)
		elseif action == "Repair" then sender:Repair(player, a, b)
		elseif action == "Cancel" and Protocol.Id(a) then
			local pending = loading[player]
			if pending and pending.Id == a then loading[player] = nil end
			sender:Cancel(player, a)
		elseif action == "Load" and Protocol.Id(a) and Catalog.Entries[a] then
			if loading[player] or os.clock() - (lastLoad[player] or -math.huge) < 0.3 then return end
			nextRequest += 1
			local token = nextRequest
			loading[player] = {Id = a, Token = token}; lastLoad[player] = os.clock()
			local currentDownloader = downloader
			task.spawn(function()
				local data, message = currentDownloader:Get(a)
				local pending = loading[player]
				if generation ~= currentGeneration or not pending or pending.Token ~= token then return end
				loading[player] = nil
				if not alive or not player.Parent then return end
				if data then sender:Begin(player, a, data); warmNext(a)
				else dataRemote:FireClient(player, "Error", a, message) end
			end)
		end
	end))
	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		sender:Step(dt)
		-- One speculative HTTP job leaves capacity for player-triggered downloads.
		if warming or #warmQueue == 0 or downloader.PendingCount >= 2 then return end
		local id = table.remove(warmQueue, 1)
		warming = true
		local currentDownloader = downloader
		task.spawn(function()
			currentDownloader:Get(id)
			if generation ~= currentGeneration then return end
			warmQueued[id] = nil; warming = false
		end)
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		sender:Remove(player); loading[player] = nil; lastLoad[player] = nil
	end))
end
function Service.Destroy()
	alive = false
	generation += 1
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections); table.clear(loading); table.clear(lastLoad)
	table.clear(warmQueue); table.clear(warmQueued); warming = false
	downloader:Destroy(); sender:Destroy()
end
return Service

