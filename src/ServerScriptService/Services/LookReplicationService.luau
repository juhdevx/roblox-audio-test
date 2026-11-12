--!strict
-- Validates finite R6 joint poses and relays them at a bounded rate.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote: RemoteEvent
local Maid = require(ReplicatedStorage.Shared.Utils.Maid)
local maid = Maid.new()
local Service = {}


local MAX_RATE = 1 / 25
local MAX_C0_MAGNITUDE = 15

local lastUpdate: { [Player]: number } = {}

local function isFiniteNumber(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isValidCFrame(cf: any): boolean
	if typeof(cf) ~= "CFrame" then return false end
	for _, component in {cf:GetComponents()} do if not isFiniteNumber(component) then return false end end
	return true
end

function Service.Init(dependencies: any) remote = dependencies.RemoteService.Get("Player", "R6LookReplication") end
function Service.Start()
maid:Add(remote.OnServerEvent:Connect(function(player: Player, data: any)
	local now = os.clock()
	if lastUpdate[player] and now - lastUpdate[player] < MAX_RATE then return end
	lastUpdate[player] = now

	if type(data) ~= "table" then return end

	local char = player.Character
	if not char or not char.Parent then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 then return end

	local safe: { [string]: CFrame } = {}
	for _, key in ipairs({ "Neck", "RootJoint", "LeftHip", "RightHip" }) do
		local cf = data[key]
		if cf ~= nil then
			if not isValidCFrame(cf) then return end
			if cf.Position.Magnitude > MAX_C0_MAGNITUDE then return end
			safe[key] = cf
		end
	end

	if next(safe) == nil then return end

	-- Relay para todos MENOS o remetente
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			remote:FireClient(other, player, safe)
		end
	end
end))

maid:Add(Players.PlayerRemoving:Connect(function(player: Player)
	lastUpdate[player] = nil
end))
end
function Service.Destroy() maid:Destroy(); table.clear(lastUpdate) end
return Service
