--!strict
-- A view of the renderer's existing EditableImage; no second decoder or pixel buffer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Scope = require(ReplicatedStorage.Shared.Utils.Scope)
local Controls = {}
Controls.__index = Controls
local nextId = 0

local function round(object: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius); corner.Parent = object
end

local function button(name: string, text: string, parent: Instance): TextButton
	local result = Instance.new("TextButton")
	result.Name = name; result.Text = text
	result.BackgroundColor3 = Color3.fromRGB(19, 24, 22)
	result.BackgroundTransparency = 0.15
	result.TextColor3 = Color3.fromRGB(239, 244, 235)
	result.Font = Enum.Font.GothamMedium; result.TextSize = 16
	result.BorderSizePixel = 0; result.Selectable = true
	result.AutoButtonColor = true; result.Parent = parent
	round(result, 10)
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(108, 124, 111); outline.Transparency = 0.4
	outline.Parent = result
	return result
end

function Controls.new(onRender: (() -> ())?)
	local player = Players.LocalPlayer
	if not player then return nil end
	local playerGui = player:WaitForChild("PlayerGui", 10)
	local root = player:WaitForChild("PlayerScripts", 10)
	if not playerGui or not root then return nil end
	local State = require(root.ClientState)
	local Settings = require(root.Controllers.SettingsController)
	nextId += 1
	local self: any = setmetatable({Scope = Scope.new(), State = State, Settings = Settings,
		Active = false, Fullscreen = false, Destroyed = false, PreviousSelection = nil,
		Action = "VideoViewer" .. tostring(nextId), ImageObject = nil}, Controls)
	local gui = self.Scope:Add(Instance.new("ScreenGui"))
	gui.Name = "VideoEmoteViewer"; gui.ResetOnSpawn = false
	gui.DisplayOrder = 80; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Enabled = false; gui.Parent = playerGui
	self.Gui = gui
	local expand = button("Expand", "Full screen", gui)
	expand.AnchorPoint = Vector2.new(1, 1)
	expand.Position = UDim2.new(1, -18, 1, -18); expand.Size = UDim2.fromOffset(146, 42)
	self.Expand = expand
	local viewer = Instance.new("Frame")
	viewer.Name = "Fullscreen"; viewer.Size = UDim2.fromScale(1, 1)
	viewer.BackgroundColor3 = Color3.new(0, 0, 0); viewer.BorderSizePixel = 0
	viewer.Active = true; viewer.Visible = false; viewer.Parent = gui
	self.Viewer = viewer
	local image = Instance.new("ImageLabel")
	image.Name = "Picture"; image.Size = UDim2.fromScale(1, 1)
	image.BackgroundColor3 = Color3.new(0, 0, 0); image.BorderSizePixel = 0
	image.ScaleType = Enum.ScaleType.Fit; image.Parent = viewer
	self.Picture = image
	local status = Instance.new("TextLabel")
	status.Name = "InitialLoading"; status.AnchorPoint = Vector2.new(0.5, 0.5)
	status.Position = UDim2.fromScale(0.5, 0.5); status.Size = UDim2.new(0.8, 0, 0, 48)
	status.BackgroundTransparency = 1; status.TextColor3 = expand.TextColor3
	status.Font = Enum.Font.GothamMedium; status.TextSize = 20; status.TextWrapped = true
	status.Text = "Loading video…"; status.Parent = viewer
	self.Status = status
	local bar = Instance.new("Frame")
	bar.Name = "InitialProgress"; bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0.5, 34); bar.Size = UDim2.new(0.4, 0, 0, 3)
	bar.BorderSizePixel = 0; bar.BackgroundColor3 = Color3.fromRGB(45, 53, 46)
	bar.Parent = viewer; self.Bar = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"; fill.Size = UDim2.fromScale(0, 1); fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.fromRGB(202, 225, 180); fill.Parent = bar
	self.Fill = fill
	local close = button("Close", "Back  ×", viewer)
	close.Position = UDim2.fromOffset(16, 16); close.Size = UDim2.fromOffset(114, 42)
	close.Modal = true; close.ZIndex = 3; self.Close = close
	local title = Instance.new("TextLabel")
	title.Name = "Title"; title.Position = UDim2.fromOffset(146, 16)
	title.Size = UDim2.new(1, -162, 0, 42); title.BackgroundTransparency = 1
	title.TextColor3 = expand.TextColor3; title.TextStrokeTransparency = 0.4
	title.Font = Enum.Font.GothamMedium; title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left; title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 3; title.Parent = viewer; self.Title = title
	self.Scope:Connect(expand.Activated, function() self:SetFullscreen(true) end)
	self.Scope:Connect(close.Activated, function() self:SetFullscreen(false) end)
	self.Scope:Connect(State.Changed, function(key: string)
		if key == "settingsOpen" then
			if State.Get(key) then self:SetFullscreen(false) end
			expand.Visible = self.Active and not self.Fullscreen and not State.Get("settingsOpen")
		end
	end)
	self.Scope:Connect(player.CharacterRemoving, function() self:SetFullscreen(false) end)
	self.Scope:Connect(GuiService.MenuOpened, function() self:SetFullscreen(false) end)
	if onRender then self.Scope:Connect(RunService.PreRender, function() if self.Active then onRender() end end) end
	ContextActionService:BindActionAtPriority(self.Action .. "Toggle", function(_, inputState)
		if not self.Active or State.Get("settingsOpen") or UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then self:SetFullscreen(not self.Fullscreen) end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.F)
	self.Scope:Add(function()
		ContextActionService:UnbindAction(self.Action .. "Toggle")
		ContextActionService:UnbindAction(self.Action .. "Close")
		ContextActionService:UnbindAction(self.Action .. "Movement")
		RunService:UnbindFromRenderStep(self.Action .. "Freeze")
	end)
	return self
end

function Controls.GetScale(self: any): number
	local value = self.Settings.Get("VideoScreenScale")
	return if type(value) == "number" and value == value then math.clamp(value, 0.75, 1.5) else 1
end

function Controls.SetImage(self: any, image: EditableImage?, title: string)
	self.ImageObject = image
	if image then self.Picture.ImageContent = Content.fromObject(image) else self.Picture.Image = "" end
	self.Title.Text = title
end

function Controls.SetLoading(self: any, initial: boolean, progress: number, unavailable: boolean)
	self.Picture.Visible = not initial
	self.Status.Visible = initial
	self.Status.Text = if unavailable then "Video unavailable on this device" else "Loading video…"
	self.Bar.Visible = initial and not unavailable
	self.Fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
end

function Controls.SetFullscreen(self: any, open: boolean)
	if self.Destroyed or self.Fullscreen == open then return end
	if open and (not self.Active or self.State.Get("settingsOpen")) then return end
	self.Fullscreen = open
	self.Viewer.Visible = open
	self.Expand.Visible = self.Active and not open and not self.State.Get("settingsOpen")
	self.Gui:SetAttribute("Fullscreen", open)
	if open then
		self.PreviousSelection = GuiService.SelectedObject
		if UserInputService.GamepadEnabled then GuiService.SelectedObject = self.Close end
		ContextActionService:BindActionAtPriority(self.Action .. "Close", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then self:SetFullscreen(false) end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
		ContextActionService:BindActionAtPriority(self.Action .. "Movement", function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 1,
			Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward,
			Enum.PlayerActions.CharacterLeft, Enum.PlayerActions.CharacterRight, Enum.PlayerActions.CharacterJump,
			Enum.KeyCode.Thumbstick1, Enum.KeyCode.Thumbstick2, Enum.KeyCode.B, Enum.KeyCode.V,
			Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseWheel)
		RunService:BindToRenderStep(self.Action .. "Freeze", Enum.RenderPriority.Last.Value, function()
			local character = Players.LocalPlayer and Players.LocalPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then humanoid:Move(Vector3.zero); humanoid.Jump = false end
		end)
	else
		ContextActionService:UnbindAction(self.Action .. "Close")
		ContextActionService:UnbindAction(self.Action .. "Movement")
		RunService:UnbindFromRenderStep(self.Action .. "Freeze")
		if self.PreviousSelection and self.PreviousSelection.Parent then
			GuiService.SelectedObject = self.PreviousSelection
		elseif GuiService.SelectedObject == self.Close then GuiService.SelectedObject = nil end
		self.PreviousSelection = nil
	end
	self.State.Set("videoFullscreen", open)
end

function Controls.SetActive(self: any, active: boolean)
	if self.Destroyed then return end
	if not active then self:SetFullscreen(false) end
	self.Active = active; self.Gui.Enabled = active
	self.Expand.Visible = active and not self.Fullscreen and not self.State.Get("settingsOpen")
end

function Controls.Destroy(self: any)
	if self.Destroyed then return end
	self:SetFullscreen(false); self.Destroyed = true
	self.Scope:Destroy(); self.ImageObject = nil
end

return Controls

