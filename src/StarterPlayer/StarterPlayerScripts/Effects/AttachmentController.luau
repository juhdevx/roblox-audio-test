--!strict
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
local Scope = require(game:GetService("ReplicatedStorage").Shared.Utils.Scope)
local ClientState = require(clientRoot.ClientState)
local Settings = require(clientRoot.Controllers.SettingsController)
local scope=Scope.new()
--!strict
-- Resolves rig attachment points and owns per-character effect attachments.
local Players = game:GetService("Players")

local AttachmentController = {}

-- ============================================================
-- MAPEAMENTO DE RIGS
-- ============================================================

local RIG_MAPPINGS = {
	[Enum.HumanoidRigType.R6] = {
		Root      = { part = "HumanoidRootPart" },
		Torso     = { part = "Torso" },
		Chest     = { part = "Torso", offset = CFrame.new(0, 1, 0) },
		Head      = { part = "Head" },


		LeftHand  = { part = "Left Arm" },
		RightHand = { part = "Right Arm" },
		LeftFoot  = { part = "Left Leg" },
		RightFoot = { part = "Right Leg" },
		LeftArm   = { part = "Left Arm" },
		RightArm  = { part = "Right Arm" },
		LeftLeg   = { part = "Left Leg" },
		RightLeg  = { part = "Right Leg" },
	},
	[Enum.HumanoidRigType.R15] = {
		Root      = { part = "HumanoidRootPart" },
		Torso     = { part = "UpperTorso" },
		Chest     = { part = "UpperTorso", offset = CFrame.new(0, 1, 0) },
		Head      = { part = "Head" },


		LeftHand  = { part = "LeftHand",     equivalent = "LeftLowerArm" },
		RightHand = { part = "RightHand",    equivalent = "RightLowerArm" },
		LeftFoot  = { part = "LeftFoot",     equivalent = "LeftLowerLeg" },
		RightFoot = { part = "RightFoot",    equivalent = "RightLowerLeg" },
		LeftArm   = { part = "LeftUpperArm", equivalent = "LeftLowerArm" },
		RightArm  = { part = "RightUpperArm",equivalent = "RightLowerArm" },
		LeftLeg   = { part = "LeftUpperLeg", equivalent = "LeftLowerLeg" },
		RightLeg  = { part = "RightUpperLeg",equivalent = "RightLowerLeg" },
	},
}

local DEFAULT_MAPPING = {
	Root      = { part = "HumanoidRootPart" },
	Torso     = { part = "UpperTorso", equivalent = "Torso" },
	Chest     = { part = "UpperTorso", equivalent = "Torso", offset = CFrame.new(0, 1, 0) },
	Head      = { part = "Head", equivalent = "UpperTorso" },

	LeftHand  = { part = "LeftHand", equivalent = "Left Arm" },
	RightHand = { part = "RightHand",equivalent = "Right Arm" },
	LeftFoot  = { part = "LeftFoot", equivalent = "Left Leg" },
	RightFoot = { part = "RightFoot",equivalent = "Right Leg" },
	LeftArm   = { part = "LeftUpperArm", equivalent = "Left Arm" },
	RightArm  = { part = "RightUpperArm",equivalent = "Right Arm" },
	LeftLeg   = { part = "LeftUpperLeg", equivalent = "Left Leg" },
	RightLeg  = { part = "RightUpperLeg",equivalent = "Right Leg" },
}

-- ============================================================
-- ESTADO INTERNO
-- ============================================================

local characterStates: { [Model]: any } = {}
local _lastRefreshCheck: { [Model]: number } = {}
local REFRESH_INTERVAL = 1.0

-- ============================================================
-- HELPERS
-- ============================================================

local function getHumanoid(character: Model): Humanoid?
	return character:FindFirstChildOfClass("Humanoid")
end

local function getRigType(character: Model): Enum.HumanoidRigType
	local humanoid = getHumanoid(character)
	if humanoid then
		return humanoid.RigType
	end

	if character:FindFirstChild("Torso") then
		return Enum.HumanoidRigType.R6
	end
	return Enum.HumanoidRigType.R15
end

local function getMapping(rigType: Enum.HumanoidRigType): { [string]: any }
	return RIG_MAPPINGS[rigType] or DEFAULT_MAPPING
end

local function getPartByName(character: Model, partName: string?): BasePart?
	if not partName then return nil end
	local part = character:FindFirstChild(partName)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function getCharacterState(character: Model): any?
	if not character then return nil end
	if not characterStates[character] then
		local rigType = getRigType(character)
		local mapping = getMapping(rigType)
		characterStates[character] = {
			rigType = rigType,
			mapping = mapping,
			parts = {} :: { [string]: BasePart },
			attachments = {} :: { [string]: { [string]: { attachment: Attachment, owner: string } } },
			effects = {} :: { [string]: { [Instance]: boolean } },
			destroyed = false,
			destroyedAt = 0,
		}
	end
	return characterStates[character]
end


local function destroyAttachmentWithChildren(attachment: Attachment)
	if not attachment or not attachment.Parent then return end
	for _, child in ipairs(attachment:GetChildren()) do
		pcall(function() child:Destroy() end)
	end
	pcall(function() attachment:Destroy() end)
end


local function refreshMapping(character: Model, state: any)
	local newRigType = getRigType(character)
	if newRigType == state.rigType then return end

	state.rigType = newRigType
	state.mapping = getMapping(newRigType)

	for pointName in pairs(state.parts) do
		state.parts[pointName] = nil
	end

	for _, sessions in pairs(state.attachments) do
		for sessionId, entry in pairs(sessions) do
			if entry.attachment then
				destroyAttachmentWithChildren(entry.attachment)
			end
			sessions[sessionId] = nil
		end
	end
end


local function refreshMappingIfNeeded(character: Model, state: any)
	local now = os.clock()
	local last = _lastRefreshCheck[character] or 0
	if now - last < REFRESH_INTERVAL then return end
	_lastRefreshCheck[character] = now
	refreshMapping(character, state)
end

local function resolvePart(
	character: Model,
	state: any,
	pointName: string,
	allowEquivalent: boolean
): BasePart?
	local mapping = state.mapping
	local entry = mapping[pointName]
	if not entry then return nil end

	local cached = state.parts[pointName]
	if cached and cached.Parent == character then
		return cached
	end

	local part = getPartByName(character, entry.part)
	if part then
		state.parts[pointName] = part
		return part
	end

	if allowEquivalent and entry.equivalent then
		part = getPartByName(character, entry.equivalent)
		if part then
			state.parts[pointName] = part
			return part
		end
	end

	return nil
end

-- ============================================================
-- LIFECYCLE
-- ============================================================

local function onCharacterRemoving(character: Model)
	local state = characterStates[character]
	if state then
		state.destroyed = true
		state.destroyedAt = os.clock()
	end
	_lastRefreshCheck[character] = nil
end

-- ============================================================
-- API PÚBLICA
-- ============================================================

function AttachmentController.GetPart(character: Model, pointName: string): BasePart?
	if not character or not character.Parent then return nil end
	local state = getCharacterState(character)
	if not state then return nil end
	refreshMappingIfNeeded(character, state)
	return resolvePart(character, state, pointName, true)
end

function AttachmentController.GetAttachment(
	character: Model,
	pointName: string,
	options: any?
): Attachment?
	if not character or not character.Parent then return nil end
	options = options or {}
	local state = getCharacterState(character)
	if not state then return nil end
	refreshMappingIfNeeded(character, state)

	local part = resolvePart(character, state, pointName, true)
	if not part then return nil end

	local sessionId = options.sessionId or "default"


	if state.attachments[pointName] and state.attachments[pointName][sessionId] then
		local existing = state.attachments[pointName][sessionId]
		if existing.attachment and existing.attachment.Parent == part then
			return existing.attachment
		end
		destroyAttachmentWithChildren(existing.attachment)
		state.attachments[pointName][sessionId] = nil
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "EffectAttachment_" .. pointName
	attachment.Parent = part

	local mapping = state.mapping[pointName]
	if mapping and mapping.offset then
		attachment.CFrame = mapping.offset
	end
	if options.offset then
		attachment.CFrame = options.offset
	end
	if options.orientation then
		attachment.CFrame = attachment.CFrame * options.orientation
	end

	if not state.attachments[pointName] then
		state.attachments[pointName] = {}
	end
	state.attachments[pointName][sessionId] = {
		attachment = attachment,
		owner = options.owner or "system",
	}

	return attachment
end

function AttachmentController.CreateEffectAttachment(
	character: Model,
	pointName: string,
	options: any?
): Attachment?
	if not character or not character.Parent then return nil end
	options = options or {}
	local state = getCharacterState(character)
	if not state then return nil end
	refreshMappingIfNeeded(character, state)

	local allowEquivalent = options.allowEquivalent ~= false
	local part = resolvePart(character, state, pointName, allowEquivalent)
	if not part then return nil end

	local attachment = Instance.new("Attachment")
	attachment.Name = "Effect_" .. pointName .. "_" .. (options.sessionId or "default")
	attachment.Parent = part

	local mapping = state.mapping[pointName]
	if mapping and mapping.offset then
		attachment.CFrame = mapping.offset
	end
	if options.offset then
		attachment.CFrame = options.offset
	end
	if options.orientation then
		attachment.CFrame = attachment.CFrame * options.orientation
	end

	local sessionId = options.sessionId or "default"
	if not state.effects[sessionId] then
		state.effects[sessionId] = {}
	end
	state.effects[sessionId][attachment] = true

	return attachment
end

function AttachmentController.RegisterEffect(
	character: Model,
	sessionId: string,
	instance: Instance
)
	if not character or not instance then return end
	local state = getCharacterState(character)
	if not state then return end
	if not state.effects[sessionId] then
		state.effects[sessionId] = {}
	end
	state.effects[sessionId][instance] = true
end

function AttachmentController.CleanupEffect(
	character: Model,
	sessionId: string,
	instance: Instance
)
	if not character or not instance then return end
	local state = characterStates[character]
	if not state or not state.effects[sessionId] then return end
	state.effects[sessionId][instance] = nil
	if instance.Parent then
		pcall(function() instance:Destroy() end)
	end
end

function AttachmentController.CleanupSession(character: Model, sessionId: string)
	if not character then return end
	local state = characterStates[character]
	if not state then return end

	local effects = state.effects[sessionId]
	if effects then
		for instance in pairs(effects) do
			if instance and instance.Parent then
				pcall(function() instance:Destroy() end)
			end
		end
		state.effects[sessionId] = nil
	end

	for _, sessions in pairs(state.attachments) do
		if sessions[sessionId] then
			local entry = sessions[sessionId]
			if entry.attachment then
				destroyAttachmentWithChildren(entry.attachment)
			end
			sessions[sessionId] = nil
		end
	end
end

function AttachmentController.CleanupCharacter(character: Model)
	if not character then return end
	local state = characterStates[character]
	if not state then return end

	for _, effects in pairs(state.effects) do
		for instance in pairs(effects) do
			if instance and instance.Parent then
				pcall(function() instance:Destroy() end)
			end
		end
	end
	state.effects = {}

	for _, sessions in pairs(state.attachments) do
		for _, entry in pairs(sessions) do
			if entry.attachment then
				destroyAttachmentWithChildren(entry.attachment)
			end
		end
	end
	state.attachments = {}

	characterStates[character] = nil
	_lastRefreshCheck[character] = nil
end

function AttachmentController.GetDebugState(character: Model): any?
	if not character then return nil end
	return characterStates[character]
end

function AttachmentController.Init(_dependencies: any) end
function AttachmentController.Start()
    local function watch(player)
        scope:Connect(player.CharacterRemoving,function(character) AttachmentController.CleanupCharacter(character) end)
    end
    for _,player in Players:GetPlayers() do watch(player) end
    scope:Connect(Players.PlayerAdded,watch)
end
function AttachmentController.Destroy()
    for character in pairs(characterStates) do AttachmentController.CleanupCharacter(character) end
    scope:Destroy()
end
return AttachmentController
