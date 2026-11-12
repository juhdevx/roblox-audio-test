--!strict
-- Implements the BarsMeter server effect and its cleanup contract.
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local TAG = "EmoteBarsMeter"
local MODEL_NAME = "EmoteBarsMeter"
local MAX_TEMPLATE_PARTS = 100  -- NOVO: cap de segurança

local BarsMeter = {}

-- ============================================================
-- Cleanup (mantido + limpa connections)
-- ============================================================

local function cleanup(state: any)
	if not state.active then return end
	state.active = false

	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end
	-- NOVO: limpa a lista de conexões
	table.clear(state.connections)

	local model = state.model
	if model and model.Parent then
		model:SetAttribute("Closing", true)
		task.delay(0.5, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end
end

-- ============================================================
-- Start (mantido + validações)
-- ============================================================

function BarsMeter.Start(player: Player, character: Model, params: any)
	-- NOVO: valida que params é tabela
	if type(params) ~= "table" then
		warn("[BarsMeter] params precisa ser uma tabela")
		return nil
	end

	-- NOVO: AnimationId é essencial pro cliente sincronizar
	if not params.AnimationId then
		warn("[BarsMeter] params.AnimationId é obrigatório (cliente usa pra sincronizar)")
		return nil
	end

	local template = ServerStorage.Assets.EmoteEffects:FindFirstChild(params.Model or "Bars")
	if not template then
		warn(`[BarsMeter] "{params.Model or "Bars"}" não existe no ServerStorage`)
		return nil
	end

	-- NOVO: cap no tamanho do template
	local partCount = 0
	for _, d in ipairs(template:GetDescendants()) do
		if d:IsA("BasePart") then
			partCount += 1
			if partCount > MAX_TEMPLATE_PARTS then
				warn(`[BarsMeter] Template tem mais de {MAX_TEMPLATE_PARTS} parts, abortando`)
				return nil
			end
		end
	end

	local attachPart = character:FindFirstChild(params.AttachTo or "HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not attachPart or not humanoid then return nil end

	-- Remove BarsMeter anterior se existir
	local previous = character:FindFirstChild(MODEL_NAME)
	if previous then previous:Destroy() end

	local model = template:Clone()
	model.Name = MODEL_NAME

	local handle = model:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		warn("[BarsMeter] O model precisa de uma Part chamada Handle direto dentro dele")
		model:Destroy()
		return nil
	end
	model.PrimaryPart = handle

	-- Remove soldas do template (vamos soldar com Motor6D a partir do Handle)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") or descendant:IsA("ManualWeld")
			or descendant:IsA("Motor6D") or descendant:IsA("Snap")
		then
			descendant:Destroy()
		end
	end

	-- Escala pra bater com o character
	local scale = character:GetScale()
	if scale ~= 1 then
		-- NOVO: pcall no ScaleTo
		pcall(function() model:ScaleTo(scale) end)
	end

	-- Configura as parts (física desligada, sem colisão)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end

	-- Posiciona em relação ao character
	local offset = params.Offset or CFrame.new(0, 5.5, 0)
	local orientation = params.Orientation or Vector3.zero
	local rotation = CFrame.Angles(
		math.rad(orientation.X),
		math.rad(orientation.Y),
		math.rad(orientation.Z)
	)
	offset = CFrame.new(offset.Position * scale) * offset.Rotation * rotation

	handle.Anchored = false
	-- NOVO: pcall no PivotTo
	local pivotOk = pcall(function() model:PivotTo(attachPart.CFrame * offset) end)
	if not pivotOk then
		warn("[BarsMeter] Falha ao posicionar o model")
		model:Destroy()
		return nil
	end

	-- Solda todas as parts no Handle (o cliente anima via Motor6D.C0)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= handle then
			local joint = Instance.new("Motor6D")
			joint.Name = "BarJoint"
			joint.Part0 = handle
			joint.Part1 = part
			joint.C0 = handle.CFrame:ToObjectSpace(part.CFrame)
			joint.C1 = CFrame.new()
			joint.Parent = part
		end
	end

	-- Solda o Handle no character
	local attach = Instance.new("Motor6D")
	attach.Name = "BarsAttach"
	attach.Part0 = attachPart
	attach.Part1 = handle
	attach.C0 = offset
	attach.C1 = CFrame.new()
	attach.Parent = handle

	-- Config serializado pro cliente (MANTIDO como JSON attribute)
	local config = {
		AnimationId = params.AnimationId,
		TotalFrames = params.TotalFrames or 224,
		Cycles = params.Cycles or 2,
		Fps = params.Fps or 30,
		Speed = params.Speed or 1,
		TimeOffset = params.TimeOffset or 0,
		Hits = params.Hits or {},
		Reset = params.Reset or { Frame = 100, Frames = 12 },
		Anger = params.Anger or {},
		Calm = params.Calm or {},
		Bounce = params.Bounce or {},
		MinFill = params.MinFill or 0.03,
	}

	-- MANTIDO: JSON attribute (o BarsMeterClient lê isso)
	model:SetAttribute("Config", HttpService:JSONEncode(config))
	model:SetAttribute("StartTime", workspace:GetServerTimeNow())
	CollectionService:AddTag(model, TAG)
	model.Parent = character

	local state = {
		active = true,
		model = model,
		connections = {},
	}

	table.insert(state.connections, character:GetAttributeChangedSignal("Emoting"):Connect(function()
		if not character:GetAttribute("Emoting") then
			cleanup(state)
		end
	end))

	table.insert(state.connections, humanoid.Died:Connect(function()
		cleanup(state)
	end))

	table.insert(state.connections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanup(state)
		end
	end))

	return state
end

function BarsMeter.Stop(state: any)
	cleanup(state)
end

return BarsMeter
