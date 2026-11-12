--!strict
-- Owns shift-lock and its connections for one client lifetime.
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


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")



local LocalPlayer = Players.LocalPlayer

local CONFIG = require(ReplicatedStorage.Shared.Config.ShiftLockConfig)


local NO_ROTATE_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
}

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local characterConnections: { RBXScriptConnection } = {}

local userLocked = ClientState.Get("shiftlock") == true 
local shiftLocked = false 
local wheelOpen = ClientState.Get("emoteWheelOpen") == true or ClientState.Get("settingsOpen") == true or ClientState.Get("videoFullscreen") == true
local dead = false
local mouseHeld = false 
local offsetScale = 0
local autoRotateManaged = false
local toggleBlockedUntil = 0

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.RespectCanCollide = true

local function debugLog(...: any)
	if CONFIG.Debug then
		print("[Shiftlock]", ...)
	end
end


local function isForced(): boolean
	return character ~= nil and character:GetAttribute("ForceShiftlock") == true
end


local function isSuspended(): boolean
	return wheelOpen
		or ClientState.Get("emoting") == true
		or ClientState.Get("emoteWheelOpen") == true
		or ClientState.Get("emoting") == true
end

local function wantsShiftlock(): boolean
	if UserInputService.VREnabled or wheelOpen or dead then return false end
	return userLocked or isForced()
end

local function releaseAutoRotate()
	local hum = humanoid
	if autoRotateManaged and hum and hum.Parent then
		hum.AutoRotate = true
	end
	autoRotateManaged = false
end


local function updateMouse()
	local lock = shiftLocked and ClientState.Get("mouseUnlocked") ~= true and not dead
	if lock and GuiService.MenuIsOpen then lock = false end
	if lock and CONFIG.UnlockWhileTyping and UserInputService:GetFocusedTextBox() ~= nil then lock = false end

	if lock then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
		mouseHeld = true
	elseif mouseHeld then
		mouseHeld = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

local function refreshState(force: boolean?)
	local wanted = wantsShiftlock()
	if wanted == shiftLocked and not force then return end

	shiftLocked = wanted
	ClientState.Set("shiftlock", wanted)
	ClientState.Set("mouseUnlocked", not wanted)
	if not wanted then releaseAutoRotate() end
	updateMouse()
	debugLog("shiftLocked =", wanted)
end


local function getFlatYaw(cf: CFrame): number?
	local look = cf.LookVector
	if look.X * look.X + look.Z * look.Z < CONFIG.MinFlatLook ^ 2 then return nil end
	return math.atan2(-look.X, -look.Z)
end

local function updateRotation(dt: number, camera: Camera, hum: Humanoid, root: BasePart, char: Model, suspended: boolean)
	local blocked = suspended
		or not shiftLocked
		or hum.Sit
		or root.Anchored
		or hum:GetAttribute("ragdolled") == true
		or char:GetAttribute("Syncing") == true
		or NO_ROTATE_STATES[hum:GetState()] == true

	if blocked then
		releaseAutoRotate()
		return
	end

	autoRotateManaged = true
	if hum.AutoRotate then hum.AutoRotate = false end

	local targetYaw = getFlatYaw(camera.CFrame)
	if not targetYaw then return end
	local currentYaw = getFlatYaw(root.CFrame) or targetYaw

	-- menor caminho até o alvo (nunca passa pelo ponto ambíguo de 180°)
	local diff = (targetYaw - currentYaw + math.pi) % (2 * math.pi) - math.pi
	if math.abs(diff) < 0.0005 then return end

	local speed = CONFIG.RotationSpeed * ((char:GetAttribute("aiming") == true) and CONFIG.AimRotationMultiplier or 1)
	local alpha = 1 - math.exp(-speed * dt)
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, currentYaw + diff * alpha, 0)
end

local function updateCameraOffset(dt: number, camera: Camera, hum: Humanoid, suspended: boolean)
	local target = 0
	if shiftLocked and not suspended and camera.CameraSubject == hum then
		local distance = (camera.Focus.Position - camera.CFrame.Position).Magnitude
		target = math.clamp((distance - CONFIG.FirstPersonDistance) / CONFIG.OffsetFadeDistance, 0, 1)
	end

	offsetScale += (target - offsetScale) * (1 - math.exp(-CONFIG.OffsetSmoothing * dt))
	if offsetScale < 0.001 then
		offsetScale = 0
		return
	end

	local cf = camera.CFrame
	local desired = cf:PointToWorldSpace(CONFIG.CameraOffset * offsetScale)
	local delta = desired - cf.Position


	local result = workspace:Raycast(cf.Position, delta, raycastParams)
	if result then
		desired = cf.Position + delta.Unit * math.max(result.Distance - CONFIG.OffsetWallPadding, 0)
	end

	camera.CFrame = cf + (desired - cf.Position)
end


local function onRenderStep(dt: number)

	if ClientState.Get("shiftlock") ~= shiftLocked then
		userLocked = ClientState.Get("shiftlock") == true
		refreshState(true)
	end

	updateMouse()

	local camera = workspace.CurrentCamera
	local hum, root, char = humanoid, rootPart, character
	if not camera or not hum or not root or not char then return end
	if not hum:IsDescendantOf(workspace) or not root:IsDescendantOf(workspace) then return end

	local suspended = isSuspended()
	updateRotation(dt, camera, hum, root, char, suspended)
	updateCameraOffset(dt, camera, hum, suspended)
end


local function toggleShiftlock()
	if wheelOpen or dead or isForced() then return end
	if ClientState.Get("emoting") == true or ClientState.Get("preventLockChange") == true then return end


	local now = os.clock()
	if now < toggleBlockedUntil then return end
	toggleBlockedUntil = now + CONFIG.ToggleDebounce

	userLocked = not userLocked
	refreshState()
end

local function onShiftlockAction(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if ClientState.Get("preventLockChange") == true or wheelOpen or ClientState.Get("emoting") == true then
		return Enum.ContextActionResult.Pass
	end
	if inputState == Enum.UserInputState.Begin then
		toggleShiftlock()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end


local function onInputBegan(input: InputObject, processed: boolean)
	if processed or input.KeyCode ~= Enum.KeyCode.V then return end
	if not shiftLocked or ClientState.Get("preventMouseUnlock") == true then return end

	ClientState.Set("mouseUnlocked", not ClientState.Get("mouseUnlocked"))
	updateMouse()
end


scope:Connect(ClientState.Changed,function(key,value)
    if key == "emoteWheelOpen" or key == "settingsOpen" or key == "videoFullscreen" then
        wheelOpen = ClientState.Get("emoteWheelOpen") == true or ClientState.Get("settingsOpen") == true or ClientState.Get("videoFullscreen") == true
        refreshState(true)
    end
end)
local function setBackpackEnabled(enabled: boolean)
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, enabled)
end

local function clearCharacterConnections()
	for _, connection in ipairs(characterConnections) do connection:Disconnect() end
	table.clear(characterConnections)
end

local function onCharacterAdded(newCharacter: Model)
	clearCharacterConnections()
	releaseAutoRotate()

	local newHumanoid = newCharacter:WaitForChild("Humanoid", 10)
	local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 10)
	if not newHumanoid or not newHumanoid:IsA("Humanoid") then return end
	if not newRoot or not newRoot:IsA("BasePart") then return end
	if LocalPlayer.Character ~= newCharacter then return end

	character, humanoid, rootPart = newCharacter, newHumanoid, newRoot
	dead = false
	autoRotateManaged = false
	offsetScale = 0
	raycastParams.FilterDescendantsInstances = { newCharacter }

	local camera = workspace.CurrentCamera
	if camera then camera.CameraSubject = newHumanoid end

	UserInputService.MouseIcon = "" 
	setBackpackEnabled(newHumanoid:GetAttribute("HidingBackpack") ~= true)

	table.insert(characterConnections, scope:Connect(newHumanoid:GetAttributeChangedSignal("HidingBackpack"), function()
		setBackpackEnabled(newHumanoid:GetAttribute("HidingBackpack") ~= true)
	end))

	table.insert(characterConnections, scope:Connect(newCharacter:GetAttributeChangedSignal("ForceShiftlock"), function()
		refreshState(true)
	end))


	table.insert(characterConnections, scope:Connect(newHumanoid.Died, function()
		dead = true
		refreshState(true)
	end))

	refreshState(true)
end



refreshState(true)

pcall(function() RunService:UnbindFromRenderStep("ShiftlockUpdate") end)
RunService:BindToRenderStep("ShiftlockUpdate", Enum.RenderPriority.Camera.Value + 1, onRenderStep)

pcall(function() ContextActionService:UnbindAction("ShiftlockAction") end)
ContextActionService:BindActionAtPriority(
	"ShiftlockAction",
	onShiftlockAction,
	CONFIG.MobileButton,
	Enum.ContextActionPriority.Medium.Value,
	Enum.KeyCode.LeftShift,
	Enum.KeyCode.RightShift,
	Enum.KeyCode.ButtonL1
)

scope:Connect(UserInputService.InputBegan, onInputBegan)
scope:Connect(LocalPlayer.CharacterAdded, onCharacterAdded)
if LocalPlayer.Character then
	scope:Spawn(onCharacterAdded, LocalPlayer.Character)
end





scope:Spawn(function()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false) then break end
		task.wait(0.5)
	end
end)
scope:Add(function()
clearCharacterConnections()
releaseAutoRotate()
RunService:UnbindFromRenderStep("ShiftlockUpdate")
ContextActionService:UnbindAction("ShiftlockAction")
UserInputService.MouseBehavior=Enum.MouseBehavior.Default
UserInputService.MouseIconEnabled=true
pcall(StarterGui.SetCore,StarterGui,"ResetButtonCallback",true)

end)
end
function Module.Destroy() if active then active:Destroy(); active=nil end end
return Module
