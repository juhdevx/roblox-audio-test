--!strict
-- Owns remote joint interpolation and its connections for one client lifetime.
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
local Scope = require(game:GetService("ReplicatedStorage").Shared.Utils.Scope)
local ClientState = require(clientRoot.ClientState)
local Settings = require(clientRoot.Controllers.SettingsController)
local Module = {}
local active: any
function Module.Init(_dependencies: any) end
function Module.Start()
    if active then return end
    local scope = Scope.new(); active = scope
--!strict
-- Interpolates server-relayed R6 joint poses.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage.Remotes.Player:WaitForChild("R6LookReplication")
local player = Players.LocalPlayer

-- ============================================================
-- Config
-- ============================================================

local INTERPOLATION_DELAY = 0.1   -- 100ms de buffer (agride jitter de rede)
local MAX_BUFFER = 6              -- guarda ~300ms de histórico por junta
local JOINTS = { "Neck", "RootJoint", "LeftHip", "RightHip" }

-- ============================================================
-- Estrutura
-- ============================================================

type JointBuffer = {
	cframes: { CFrame },
	times: { number },
}

type PlayerInfo = {
	char: Model,
	joints: { [string]: Motor6D },
	buffer: { [string]: JointBuffer },
}

local otherPlayers: { [Player]: PlayerInfo } = {}

-- ============================================================
-- Buffer helpers
-- ============================================================

local function initBuffer(): JointBuffer
	return { cframes = {}, times = {} }
end

local function pushSample(buffer: JointBuffer, cf: CFrame, t: number)
	table.insert(buffer.cframes, cf)
	table.insert(buffer.times, t)
	while #buffer.cframes > MAX_BUFFER do
		table.remove(buffer.cframes, 1)
		table.remove(buffer.times, 1)
	end
end

-- Interpola entre dois samples ao redor de renderTime
local function sampleAt(buffer: JointBuffer, renderTime: number): CFrame?
	local n = #buffer.cframes
	if n == 0 then return nil end
	if n == 1 then return buffer.cframes[1] end

	for i = n, 2, -1 do
		local t1, t2 = buffer.times[i - 1], buffer.times[i]
		if renderTime >= t1 and renderTime <= t2 then
			local span = t2 - t1
			if span <= 0 then return buffer.cframes[i] end
			local alpha = (renderTime - t1) / span
			return buffer.cframes[i - 1]:Lerp(buffer.cframes[i], alpha)
		end
	end

	if renderTime < buffer.times[1] then return buffer.cframes[1] end
	return buffer.cframes[n]
end

-- ============================================================
-- Ciclo de vida dos outros players
-- ============================================================

local function addPlayer(plr: Player, char: Model)
	if plr == player then return end
	local humanoid = char:WaitForChild("Humanoid",10)
	char:WaitForChild("Torso",10)
	if plr.Character ~= char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	local torso = char:FindFirstChild("Torso")
	if not humanoid or not root or not torso then return end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then return end

	local neck = torso:FindFirstChild("Neck")
	local rootJoint = root:FindFirstChild("RootJoint")
	local leftHip = torso:FindFirstChild("Left Hip")
	local rightHip = torso:FindFirstChild("Right Hip")
	if not neck or not rootJoint or not leftHip or not rightHip then return end

	otherPlayers[plr] = {
		char = char,
		joints = {
			Neck = neck,
			RootJoint = rootJoint,
			LeftHip = leftHip,
			RightHip = rightHip,
		},
		buffer = {
			Neck = initBuffer(),
			RootJoint = initBuffer(),
			LeftHip = initBuffer(),
			RightHip = initBuffer(),
		},
	}
end

local function removePlayer(plr: Player)
	otherPlayers[plr] = nil
end

-- ============================================================
-- Recebimento
-- ============================================================

scope:Connect(remote.OnClientEvent, function(fromPlayer: Player, data: any)
	if fromPlayer == player then return end
	local info = otherPlayers[fromPlayer]
	if not info then return end
	if type(data) ~= "table" then return end

	local now = os.clock()
	for _, key in ipairs(JOINTS) do
		local cf = data[key]
		if typeof(cf) == "CFrame" then
			pushSample(info.buffer[key], cf, now)
		end
	end
end)

-- ============================================================
-- Bind jogadores existentes e futuros
-- ============================================================

for _, plr in ipairs(Players:GetPlayers()) do
	if plr ~= player and plr.Character then addPlayer(plr, plr.Character) end
	scope:Connect(plr.CharacterAdded, function(char) addPlayer(plr, char) end)
	scope:Connect(plr.CharacterRemoving, function() removePlayer(plr) end)
end

scope:Connect(Players.PlayerAdded, function(plr)
	scope:Connect(plr.CharacterAdded, function(char) addPlayer(plr, char) end)
	scope:Connect(plr.CharacterRemoving, function() removePlayer(plr) end)
end)
scope:Connect(Players.PlayerRemoving, removePlayer)

-- ============================================================
-- Loop de render — amostra e aplica (sem dt, sem lerp perseguidor)
-- ============================================================

scope:Connect(RunService.RenderStepped, function()
	local renderTime = os.clock() - INTERPOLATION_DELAY

	for plr, info in pairs(otherPlayers) do
		if not info.char or not info.char.Parent then
			otherPlayers[plr] = nil
		else
			for key, joint in pairs(info.joints) do
				local cf = sampleAt(info.buffer[key], renderTime)
				if cf then joint.C0 = cf end
			end
		end
	end
end)


scope:Add(function()
table.clear(otherPlayers)
end)
end
function Module.Destroy() if active then active:Destroy(); active=nil end end
return Module
