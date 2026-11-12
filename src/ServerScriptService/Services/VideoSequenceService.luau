--!strict
-- Serves validated external video segments without accepting client URLs or Roblox video assets.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Protocol = require(Shared.AudioSequence.Protocol)
local Format = require(Shared.VideoSequence.Format)
local Catalog = require(script.Parent.Parent.VideoSequence.VideoCatalog)
local Downloads = require(script.Parent.Parent.VideoSequence.Downloads)
local Transport = require(script.Parent.Parent.VideoSequence.Transport)
local Service = {}
local connections: {RBXScriptConnection} = {}
local downloader: any = nil
local sender: any = nil
local request: RemoteEvent
local dataRemote: RemoteEvent
local alive = false
local generation = 0
local nextRequest = 0
local loading: {[Player]: {Id: string, Token: number}} = {}
local lastLoad: {[Player]: number} = {}
local warmQueue: {string} = {}
local warmQueued: {[string]: boolean} = {}
local warming = false
local function ensure(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if child then assert(child.ClassName == className, `Wrong video instance class: {child:GetFullName()}`); return child end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end
local function validate(data: buffer, id: string): (boolean, string?)
	local valid, message = Format.Validate(data)
	if not valid then return false, message end
	local entry = Catalog.Entries[id]
	local track = entry and Catalog.Manifest[entry.Track]
	local header = Format.Header(data)
	if not entry or not track or not header then return false, "Unknown video segment metadata" end
	local first = entry.Part * track.SegmentFrames
	if header.Width ~= track.Width or header.Height ~= track.Height or header.FPS ~= track.FPS
		or header.Encoding ~= track.Encoding or header.FirstFrame ~= first or header.TotalFrames ~= track.Frames
		or header.SegmentFrames ~= track.SegmentFrames
		or header.FrameCount ~= math.min(track.SegmentFrames, track.Frames - first) then
		return false, "Video segment does not match its registry entry"
	end
	return true, nil
end
local function enqueueWarm(id: string)
	if not Catalog.Entries[id] or warmQueued[id] or #warmQueue >= 8 then return end
	warmQueued[id] = true
	table.insert(warmQueue, id)
end
local function warmNext(id: string)
	local entry = Catalog.Entries[id]
	local track = entry and Catalog.Manifest[entry.Track]
	if not entry or not track then return end
	local part = (entry.Part + 1) % track.Segments
	enqueueWarm(`{entry.Track}_{string.format("%04d", part)}`)
end
function Service.Init(_dependencies: any)
	if downloader then Service.Destroy() end
	local remotes = ensure(ReplicatedStorage, "Remotes", "Folder")
	local folder = ensure(remotes, "VideoSequence", "Folder")
	request = ensure(folder, "Request", "RemoteEvent") :: RemoteEvent
	dataRemote = ensure(folder, "Data", "RemoteEvent") :: RemoteEvent
	downloader = Downloads.new(Catalog, validate)
	sender = Transport.new(dataRemote)
end
function Service.Start()
	if alive then return end
	assert(downloader and sender, "VideoSequenceService.Init must run before Start")
	alive = true
	generation += 1
	local currentGeneration = generation
	local warmed = 0
	for name, track in Catalog.Manifest do
		if track.Preload and warmed < 2 then
			enqueueWarm(`{name}_0000`)
			if track.Segments > 1 then enqueueWarm(`{name}_0001`) end
			warmed += 1
		end
	end
	table.insert(connections, request.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
		if not sender:Allow(player) then return end
		if action == "Manifest" then
			dataRemote:FireClient(player, "Manifest", Catalog.Manifest)
		elseif action == "Ack" then sender:Ack(player, a)
		elseif action == "Repair" then sender:Repair(player, a, b)
		elseif action == "Cancel" and Protocol.Id(a) then
			local pending = loading[player]
			if pending and pending.Id == a then loading[player] = nil end
			sender:Cancel(player, a)
		elseif action == "Load" and Protocol.Id(a) then
			if not Catalog.Entries[a] then
				dataRemote:FireClient(player, "Error", a, "Unknown video segment")
				return
			end
			if loading[player] or os.clock() - (lastLoad[player] or -math.huge) < 0.3 then return end
			nextRequest += 1
			local token = nextRequest
			loading[player] = {Id = a, Token = token}
			lastLoad[player] = os.clock()
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
	table.insert(connections, RunService.Heartbeat:Connect(function(dt: number)
		sender:Step(dt)
		if warming or #warmQueue == 0 or downloader.PendingCount >= 1 then return end
		local id = table.remove(warmQueue, 1)
		warming = true
		local currentDownloader = downloader
		task.spawn(function()
			currentDownloader:Get(id)
			if generation ~= currentGeneration then return end
			warmQueued[id] = nil
			warming = false
		end)
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player: Player)
		sender:Remove(player)
		loading[player] = nil
		lastLoad[player] = nil
	end))
end
function Service.Destroy()
	alive = false
	generation += 1
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	table.clear(loading)
	table.clear(lastLoad)
	table.clear(warmQueue)
	table.clear(warmQueued)
	warming = false
	if downloader then downloader:Destroy(); downloader = nil end
	if sender then sender:Destroy(); sender = nil end
end
return Service

