--!strict
-- Exposes server-authoritative sequence transport and playback controls.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage").Shared.AudioSequence
local Protocol = require(Shared.Protocol)
local Downloads = require(script.Parent.Parent.AudioSequence.Downloads)
local Transport = require(script.Parent.Parent.AudioSequence.Transport)
export type State = {
	Revision: number, Id: string, Tick: number, Epoch: number, Playing: boolean,
	BPM: number, Loop: boolean, Duration: number, PPQ: number,
}
local Service = {}
local connections: {RBXScriptConnection} = {}
local downloader: Downloads.Downloader
local sender: Transport.Sender
local request: RemoteEvent
local stateRemote: RemoteEvent
local alive = false
local loading: {[Player]: {Id: string, Token: number}} = {}
local generation = 0
local nextRequest = 0
local lastLoad: {[Player]: number} = {}
local playGeneration = 0
local state: State = {Revision = 0, Id = "", Tick = 0, Epoch = 0,
	Playing = false, BPM = 120, Loop = false, Duration = 1, PPQ = 480}
local function position(): number
	local tick = state.Tick
	if state.Playing then tick += (workspace:GetServerTimeNow() - state.Epoch) * state.BPM * state.PPQ / 60 end
	return if state.Loop then tick % state.Duration else math.min(tick, state.Duration)
end
local function broadcast()
	state.Revision += 1
	state.Epoch = workspace:GetServerTimeNow()
	stateRemote:FireAllClients(state)
end
local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end
function Service.Init(dependencies: any)
	request = dependencies.RemoteService.Get("AudioSequence", "Request")
	stateRemote = dependencies.RemoteService.Get("AudioSequence", "State")
	downloader = Downloads.new()
	sender = Transport.new(dependencies.RemoteService.Get("AudioSequence", "Data"))
end
function Service.Start()
	if alive then return end
	alive = true
	generation += 1
	local currentGeneration = generation
	table.insert(connections, request.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
		if not sender:Allow(player) then return end
		if action == "Status" then stateRemote:FireClient(player, state)
		elseif action == "Ack" then sender:Ack(player, a)
		elseif action == "Repair" then sender:Repair(player, a, b)
		elseif action == "Cancel" and Protocol.Id(a) then
			local pending = loading[player]
			if pending and pending.Id == a then loading[player] = nil end
			sender:Cancel(player, a)
		elseif action == "Load" and Protocol.Id(a) then
			if loading[player] or os.clock() - (lastLoad[player] or -math.huge) < 2 then return end
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
				if data then sender:Begin(player, a, data)
				else sender.Remote:FireClient(player, "Error", a, message) end
			end)
		end
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		sender:Remove(player); loading[player] = nil; lastLoad[player] = nil
	end))
	table.insert(connections, RunService.Heartbeat:Connect(function(dt) sender:Step(dt) end))
end
-- Only trusted server code can change shared playback.
function Service.Play(id: string): (boolean, string?)
	assert(alive, "AudioSequenceService is not started")
	playGeneration += 1
	local generation = playGeneration
	local data, message = downloader:Get(id)
	if generation ~= playGeneration or not alive then return false, "Superseded" end
	if not data then return false, message end
	state.Id = id; state.Tick = 0; state.Playing = true
	state.BPM = buffer.readf32(data, 20)
	state.Duration = buffer.readu32(data, 28); state.PPQ = buffer.readu16(data, 18)
	broadcast()
	return true, nil
end
function Service.Pause()
	playGeneration += 1; state.Tick = position(); state.Playing = false; broadcast()
end
function Service.Resume()
	if state.Id == "" then return end
	state.Tick = position(); state.Playing = true; broadcast()
end
function Service.Stop()
	playGeneration += 1; state.Tick = 0; state.Playing = false; broadcast()
end
function Service.Seek(tick: number)
	assert(finite(tick), "Invalid tick")
	state.Tick = math.clamp(tick, 0, state.Duration); broadcast()
end
function Service.SetBPM(bpm: number)
	assert(finite(bpm) and bpm >= 20 and bpm <= 400, "BPM must be between 20 and 400")
	state.Tick = position(); state.BPM = bpm; broadcast()
end
function Service.SetLoop(looped: boolean)
	state.Tick = position(); state.Loop = looped; broadcast()
end
function Service.GetState(): State
	return table.clone(state)
end
function Service.Destroy()
	alive = false; playGeneration += 1; generation += 1
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections); table.clear(loading); table.clear(lastLoad)
	downloader:Destroy(); sender:Destroy()
end
return Service
