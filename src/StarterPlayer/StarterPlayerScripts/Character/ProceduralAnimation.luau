--!strict
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
local Scope = require(game:GetService("ReplicatedStorage").Shared.Utils.Scope)
local ClientState = require(clientRoot.ClientState)
local Settings = require(clientRoot.Controllers.SettingsController)
local scope = Scope.new()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local remote = ReplicatedStorage.Remotes.Player:WaitForChild("R6LookReplication")

local player = Players.LocalPlayer

local ProceduralAnimation = {}
ProceduralAnimation.__index = ProceduralAnimation

local BIND_NAME = "ProceduralAnimationUpdate"

local config = table.clone(require(ReplicatedStorage.Shared.Config.ProceduralConfig))

local jointData = nil
local lastSend = 0
local sendDelay = 1 / config.sendRate
local bound = false
local started = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function getJointBase(char)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	local torso = char:FindFirstChild("Torso")

	if not humanoid or not root or not torso then return nil end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then return nil end

	local neck = torso:FindFirstChild("Neck")
	local rootJoint = root:FindFirstChild("RootJoint")
	local leftHip = torso:FindFirstChild("Left Hip")
	local rightHip = torso:FindFirstChild("Right Hip")

	if not neck or not rootJoint or not leftHip or not rightHip then return nil end

	local base = {
		neckC0 = neck.C0,
		rootJointC0 = rootJoint.C0,
		leftHipC0 = leftHip.C0,
		rightHipC0 = rightHip.C0,
	}

	return {
		humanoid = humanoid,
		root = root,
		torso = torso,
		neck = neck,
		rootJoint = rootJoint,
		leftHip = leftHip,
		rightHip = rightHip,

		-- C0 originais (na escala do spawn) e os C0 de trabalho (escalados pela escala atual)
		base = base,
		baseScale = char:GetScale(),
		factor = 1,
		neckC0 = base.neckC0,
		rootJointC0 = base.rootJointC0,
		leftHipC0 = base.leftHipC0,
		rightHipC0 = base.rightHipC0,
	}
end

local function scaleCFrame(cf, factor)
	return CFrame.new(cf.Position * factor) * (cf - cf.Position)
end

-- Quando o personagem muda de tamanho (ScaleTo), os C0 de referência acompanham
local function refreshScale(char)
	local factor = char:GetScale() / jointData.baseScale
	if math.abs(factor - jointData.factor) < 0.0001 then return end

	jointData.factor = factor
	for key, cf in pairs(jointData.base) do
		jointData[key] = scaleCFrame(cf, factor)
	end
end

local function groundCast(pos)
	local origin = pos + Vector3.new(0, config.rayHeight, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -config.rayLength, 0), rayParams)
	return result and result.Position or nil
end

local function getGround(basePos, side, forward, right)
	local footSpread = config.footSpread
	local footForward = config.footForward

	local a = groundCast(basePos + forward * footForward)
	local b = groundCast(basePos + forward * footForward - right * (footSpread * side))
	local c = groundCast(basePos + forward * footForward + right * (footSpread * side))

	local hits = {}
	if a then hits[#hits + 1] = a end
	if b then hits[#hits + 1] = b end
	if c then hits[#hits + 1] = c end

	if #hits < 2 then return nil end

	local bestY, bestCount = nil, 0
	for i = 1, #hits do
		local y = hits[i].Y
		local count = 0
		for j = 1, #hits do
			if math.abs(hits[j].Y - y) <= config.supportTolerance then
				count += 1
			end
		end
		if count > bestCount then
			bestCount = count
			bestY = y
		end
	end
	return bestY
end

local function getLegHeight(hip, side, torso)
	local hipWorld = torso.CFrame * hip.C0
	local groundY = getGround(hipWorld.Position, side, torso.CFrame.LookVector, torso.CFrame.RightVector)
	if not groundY then return nil, nil end
	return groundY, math.abs(hipWorld.Position.Y - groundY)
end

-- 1 = câmera atrás/lado (cabeça acompanha), 0 = câmera de frente (cabeça no centro)
local function getFrontWeight(rawYaw)
	local a, b = config.frontFadeStart, config.frontFadeEnd
	local t = math.clamp((math.abs(rawYaw) - a) / (b - a), 0, 1)
	return 1 - t * t * (3 - 2 * t)
end

local function resetJoints(alpha)
	jointData.neck.C0 = jointData.neck.C0:Lerp(jointData.neckC0, alpha)
	jointData.rootJoint.C0 = jointData.rootJoint.C0:Lerp(jointData.rootJointC0, alpha)
	jointData.leftHip.C0 = jointData.leftHip.C0:Lerp(jointData.leftHipC0, alpha)
	jointData.rightHip.C0 = jointData.rightHip.C0:Lerp(jointData.rightHipC0, alpha)
end

local function updateLocal(dt)
	if not config.enabled or not jointData then return end
	if not jointData.torso.Parent then return end

	local humanoid = jointData.humanoid
	local root = jointData.root
	local torso = jointData.torso
	local char = torso.Parent

	refreshScale(char)

	if ClientState.Get("emoteWheelOpen") then
		jointData.neck.C0 = jointData.neckC0
		jointData.rootJoint.C0 = jointData.rootJointC0
		jointData.leftHip.C0 = jointData.leftHipC0
		jointData.rightHip.C0 = jointData.rightHipC0
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	local alpha = 1 - math.exp(-config.smoothness * dt)

	if humanoid.Health <= 0 then
		resetJoints(alpha)
		return
	end

	rayParams.FilterDescendantsInstances = { char }

	-- Direção da câmera relativa ao corpo, com giro suave para zero quando a câmera está de frente
	local look = root.CFrame:VectorToObjectSpace(camera.CFrame.LookVector)
	local rawYaw = math.atan2(look.X, -look.Z)
	local weight = getFrontWeight(rawYaw)

	local yaw = math.clamp(rawYaw, -1, 1) * weight
	local pitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), -1, 1) * weight

	local torsoTurn = yaw * config.torsoTurnAmount
	local torsoPitch = -pitch * config.torsoPitchAmount
	local headYaw = -yaw * config.headYawAmount
	local headPitch = -pitch * config.headPitchAmount

	local moveDir = humanoid.MoveDirection
	local localMove = root.CFrame:VectorToObjectSpace(moveDir)
	local velocity = root.AssemblyLinearVelocity
	local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = moveDir.Magnitude > 0.05 and humanoid.FloorMaterial ~= Enum.Material.Air
	local speedFactor = math.clamp(flatSpeed / math.max(humanoid.WalkSpeed, 0.01), 0, 1.4)

	local bob = 0
	local tilt = 0
	if moving then
		bob = math.abs(math.sin(time() * 8)) * config.bobAmount * speedFactor * jointData.factor
		tilt = -math.clamp(localMove.X, -1, 1) * config.tiltAmount
	end

	local torsoRoll = -torsoTurn + tilt
	local legRoll = moving and tilt or 0

	local centerGround = getGround(root.Position, 0, torso.CFrame.LookVector, torso.CFrame.RightVector)

	local leftLift, leftForward, leftSide = 0, 0, 0
	local rightLift, rightForward, rightSide = 0, 0, 0

	if centerGround then
		local leftY, leftDist = getLegHeight(jointData.leftHip, -1, torso)
		local rightY, rightDist = getLegHeight(jointData.rightHip, 1, torso)

		if leftY and leftDist and leftDist <= config.maxFootDistance then
			local diff = math.clamp(leftY - centerGround, 0, config.maxLegRaise)
			if math.abs(diff) <= config.maxGroundDiff then
				leftLift = diff
				if diff > 0 then
					leftForward = config.raisedForward
					leftSide = -config.raisedSide
				end
			end
		end
		if rightY and rightDist and rightDist <= config.maxFootDistance then
			local diff = math.clamp(rightY - centerGround, 0, config.maxLegRaise)
			if math.abs(diff) <= config.maxGroundDiff then
				rightLift = diff
				if diff > 0 then
					rightForward = config.raisedForward
					rightSide = config.raisedSide
				end
			end
		end
	end

	local strafe = moving and math.clamp(localMove.X, -1, 1) or 0

	local leftTarget = jointData.leftHipC0
		* CFrame.Angles(0, 0, -legRoll)
		* CFrame.new(leftSide, leftLift, leftForward)
		* CFrame.Angles(0, -strafe * config.legSideAmount, strafe * config.legSideAmount)

	local rightTarget = jointData.rightHipC0
		* CFrame.Angles(0, 0, -legRoll)
		* CFrame.new(rightSide, rightLift, rightForward)
		* CFrame.Angles(0, -strafe * config.legSideAmount, strafe * config.legSideAmount)

	local rootTarget = jointData.rootJointC0
		* CFrame.new(0, bob, 0)
		* CFrame.Angles(torsoPitch, 0, torsoRoll)

	local neckTarget = jointData.neckC0
	if not ClientState.Get("emoting") then
		neckTarget = jointData.neckC0 * CFrame.Angles(headPitch, 0, headYaw)
	end

	jointData.rootJoint.C0 = jointData.rootJoint.C0:Lerp(rootTarget, alpha)
	jointData.neck.C0 = jointData.neck.C0:Lerp(neckTarget, alpha)
	jointData.leftHip.C0 = jointData.leftHip.C0:Lerp(leftTarget, alpha)
	jointData.rightHip.C0 = jointData.rightHip.C0:Lerp(rightTarget, alpha)

	local now = time()
	if now - lastSend >= sendDelay then
		lastSend = now
		remote:FireServer({
			Neck = jointData.neck.C0,
			RootJoint = jointData.rootJoint.C0,
			LeftHip = jointData.leftHip.C0,
			RightHip = jointData.rightHip.C0,
		})
	end
end

local function bindUpdate()
	if bound then return end
	bound = true

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, updateLocal)
end

local function unbindUpdate()
	if not bound then return end
	bound = false
	RunService:UnbindFromRenderStep(BIND_NAME)
end

local function onCharacterAdded(char)
	char:WaitForChild("Humanoid",10)
	char:WaitForChild("Torso",10)
	if player.Character ~= char then return end
	unbindUpdate()
	jointData = getJointBase(char)
	if not jointData then return end
	bindUpdate()
end

function ProceduralAnimation.Start()
	if started then return end
	started = true

	sendDelay = 1 / config.sendRate
	scope:Connect(player.CharacterAdded, onCharacterAdded)
	scope:Connect(player.CharacterRemoving, function()
		unbindUpdate()
		jointData = nil
	end)
	if player.Character then onCharacterAdded(player.Character) end
end

function ProceduralAnimation.SetConfig(newConfig)
	for k, v in pairs(newConfig) do config[k] = v end
	sendDelay = 1 / config.sendRate
end

function ProceduralAnimation.Init(_dependencies: any) end
function ProceduralAnimation.Destroy()
    scope:Destroy(); unbindUpdate()
    if jointData and jointData.torso.Parent then resetJoints(1) end
    jointData=nil; started=false
end
return ProceduralAnimation
