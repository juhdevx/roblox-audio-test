--!strict
-- Implements the AttachHands server effect and its cleanup contract.
local ServerStorage = game:GetService("ServerStorage")

local CONFIG = {
	TemplatesFolderName = "HandTemplates",
	RightTemplateName = "RightHand",
	LeftTemplateName = "LeftHand",
	RightHandMotorName = "Hand.R",
	LeftHandMotorName = "Hand.L",
	HandC0 = CFrame.new(0, -0.753, 0) * CFrame.Angles(0, math.rad(180), 0),
	HandC1 = CFrame.new(0, 0.1, 0),
}

local AttachHands = {}

local templatesFolder = ServerStorage.Assets.EmoteEffects:FindFirstChild(CONFIG.TemplatesFolderName)
local defaultRightTemplate = templatesFolder and templatesFolder:FindFirstChild(CONFIG.RightTemplateName)
local defaultLeftTemplate = templatesFolder and templatesFolder:FindFirstChild(CONFIG.LeftTemplateName)

-- ============================================================
-- attachHand (mantido + validações)
-- ============================================================

local function attachHand(arm: BasePart, handTemplate: Instance, motorName: string, c0: CFrame, c1: CFrame)
	-- NOVO: valida que o template é clonável
	if not handTemplate or not handTemplate:IsA("Model") and not handTemplate:IsA("BasePart") then
		warn(`[AttachHands] Template inválido para {motorName}`)
		return nil, nil
	end

	-- NOVO: valida que arm é BasePart
	if not arm:IsA("BasePart") then
		warn(`[AttachHands] {motorName}: arm não é BasePart`)
		return nil, nil
	end

	-- Remove motor antigo se existir (idempotente)
	for _, child in ipairs(arm:GetChildren()) do
		if child.Name == motorName then
			child:Destroy()
		end
	end

	-- NOVO: pcall no Clone (templates podem falhar se estiverem sendo usados)
	local ok, hand = pcall(function() return handTemplate:Clone() end)
	if not ok or not hand then
		warn(`[AttachHands] Falha ao clonar template: {tostring(hand)}`)
		return nil, nil
	end
	hand.Name = motorName

	local rootPart = hand:FindFirstChild(motorName)
	if not rootPart or not rootPart:IsA("BasePart") then
		warn(`[AttachHands] Template "{handTemplate.Name}" não tem BasePart chamada "{motorName}"`)
		hand:Destroy()
		return nil, nil
	end

	-- NOVO: aplica ScaleTo pra acompanhar o tamanho do character
	local armParent = arm.Parent
	if armParent and armParent:IsA("Model") then
		local charScale = armParent:GetScale()
		if charScale ~= 1 and hand:IsA("Model") then
			pcall(function() hand:ScaleTo(charScale) end)
		end
	end

	-- Aplica propriedades visuais + física das parts
	for _, part in ipairs(hand:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Color = arm.Color
			part.Material = arm.Material
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
	end

	hand.Parent = arm

	-- NOVO: pcall na criação do Motor6D (Part0/Part1 podem ter sumido)
	local motorOk, motor = pcall(function()
		local m = Instance.new("Motor6D")
		m.Name = motorName
		m.Part0 = arm
		m.Part1 = rootPart
		m.C0 = c0
		m.C1 = c1
		m.Parent = arm
		return m
	end)

	if not motorOk or not motor then
		warn(`[AttachHands] Falha ao criar Motor6D {motorName}`)
		hand:Destroy()
		return nil, nil
	end

	return hand, motor
end

-- ============================================================
-- API pública (idêntica ao original)
-- ============================================================

function AttachHands.Start(player: Player, character: Model, params: any)
	-- NOVO: valida params
	params = params or {}
	if type(params) ~= "table" then
		warn("[AttachHands] params inválido")
		return nil
	end

	if not templatesFolder then
		warn(`[AttachHands] ServerStorage.{CONFIG.TemplatesFolderName} não encontrado`)
		return nil
	end

	-- Resolve templates (com fallback pros default)
	local rightTemplate = defaultRightTemplate
	local leftTemplate = defaultLeftTemplate

	if params.RightTemplate then
		rightTemplate = templatesFolder:FindFirstChild(params.RightTemplate) or rightTemplate
	end
	if params.LeftTemplate then
		leftTemplate = templatesFolder:FindFirstChild(params.LeftTemplate) or leftTemplate
	end

	if not rightTemplate or not leftTemplate then
		warn(`[AttachHands] Templates faltando (Right={tostring(rightTemplate)}, Left={tostring(leftTemplate)})`)
		return nil
	end

	local rightArm = character:FindFirstChild("Right Arm")
	local leftArm = character:FindFirstChild("Left Arm")
	if not rightArm or not leftArm then
		warn(`[AttachHands] "{character.Name}" não tem Right Arm / Left Arm (é R15?)`)
		return nil
	end

	local rightHand, rightMotor = attachHand(
		rightArm, rightTemplate, CONFIG.RightHandMotorName, CONFIG.HandC0, CONFIG.HandC1
	)
	local leftHand, leftMotor = attachHand(
		leftArm, leftTemplate, CONFIG.LeftHandMotorName, CONFIG.HandC0, CONFIG.HandC1
	)

	local state = {
		RightHand = rightHand,
		RightMotor = rightMotor,
		LeftHand = leftHand,
		LeftMotor = leftMotor,
		_destroyed = false,  -- NOVO: idempotência
	}

	-- NOVO: guard no delay do Duration
	if params.Duration then
		task.delay(params.Duration, function()
			if not state._destroyed then
				AttachHands.Stop(state)
			end
		end)
	end

	return state
end

function AttachHands.Stop(state: any)
	if not state then return end
	-- NOVO: guard contra Stop duplo
	if state._destroyed then return end
	state._destroyed = true

	-- NOVO: pcall em cada Destroy (algum pode já ter sido destruído)
	if state.RightMotor then pcall(function() state.RightMotor:Destroy() end) end
	if state.RightHand then pcall(function() state.RightHand:Destroy() end) end
	if state.LeftMotor then pcall(function() state.LeftMotor:Destroy() end) end
	if state.LeftHand then pcall(function() state.LeftHand:Destroy() end) end
end

return AttachHands
