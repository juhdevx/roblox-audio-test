--!strict
-- Draws one decoded video on both faces of its world screen and synchronized partners.
local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Shared.VideoSequence.Config)
local UIControls = require(script.Parent.UIControls)
local Renderer = {}
Renderer.__index = Renderer
function Renderer.new()
	return setmetatable({Editable = nil :: EditableImage?, Width = 0, Height = 0,
		CapabilityError = nil :: string?, Destroyed = false, Visible = false, Hidden = false,
		Displayed = 0, LoadingProgress = 0, LastWriteMs = 0, Surfaces = {} :: {[BasePart]: {SurfaceGui}},
		PreviewPart = nil :: Part?, Source = nil :: any, Track = "", Title = "", LastScan = 0,
        Controls = nil :: any}, Renderer)
end
export type Display = typeof(Renderer.new())
-- Fit the camera-local preview inside both frustum axes, including portrait displays.
function Renderer.PreviewLayout(width: number, height: number, viewport: Vector2, fov: number, scale: number): (Vector3, number)
    scale = if scale == scale then math.clamp(scale, 0.75, 1.5) else 1
    local aspect = math.max(1, width) / math.max(1, height)
    local screenHeight = Config.ScreenHeight * scale
    local screenWidth = screenHeight * aspect
    local viewAspect = math.max(1, viewport.X) / math.max(1, viewport.Y)
    local halfVertical = math.tan(math.rad(math.clamp(fov, 1, 120)) / 2)
    local heightFraction = math.clamp(0.6 * scale, 0.35, 0.84)
    local widthFraction = math.clamp(0.86 * scale, 0.5, 0.94)
    local distance = math.max(1, screenHeight / (2 * halfVertical * heightFraction),
        screenWidth / (2 * halfVertical * viewAspect * widthFraction))
    return Vector3.new(screenWidth, screenHeight, 0.08), distance
end
function Renderer.UpdatePreview(self: Display)
    local part = self.PreviewPart
    local camera = workspace.CurrentCamera
    if self.Destroyed or not self.Visible or not part or not camera then return end
    local scale = if self.Controls then self.Controls:GetScale() else 1
    local size, distance = Renderer.PreviewLayout(self.Width, self.Height, camera.ViewportSize, camera.FieldOfView, scale)
    part.Size = size
    part.CFrame = camera.CFrame * CFrame.new(0, 0, -distance)
end
local function ensureControls(self: Display)
    if not self.Controls then
        self.Controls = UIControls.new(function() self:UpdatePreview() end)
        if self.Controls then self.Controls:SetImage(self.Editable, self.Title) end
    end
end
local function clearSurfaces(self: Display)
	for part, surfaces in self.Surfaces do
		for _, surface in surfaces do surface:Destroy() end
		self.Surfaces[part] = nil
	end
end
-- Only the initial load can cover the picture. Recovery continues quietly behind it.
local function refreshLoading(self: Display)
	local initial = self.Displayed == 0
	local message = if self.CapabilityError then "Video unavailable on this device" else "Loading video…"
    if self.Controls then self.Controls:SetLoading(initial, self.LoadingProgress, self.CapabilityError ~= nil) end
	for _, surfaces in self.Surfaces do
		for _, surface in surfaces do
			local label = surface:FindFirstChild("Status") :: TextLabel?
			if label then
				if label.Text ~= message then label.Text = message end
				label.Visible = initial
			end
			local picture = surface:FindFirstChild("Picture") :: ImageLabel?
			if picture then picture.Visible = not initial end
			local bar = surface:FindFirstChild("LoadingBar") :: Frame?
			if bar then
				bar.Visible = initial and self.CapabilityError == nil
				local fill = bar:FindFirstChild("Fill") :: Frame?
				if fill then fill.Size = UDim2.fromScale(self.LoadingProgress, 1) end
			end
		end
	end
end
local function attach(self: Display, part: BasePart)
	if self.Surfaces[part] then return end
	local surfaces = {}
	for _, face in {Enum.NormalId.Front, Enum.NormalId.Back} do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "VideoEmoteSurface"; gui.Adornee = part; gui.Face = face
		gui.ResetOnSpawn = false
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(self.Width, self.Height)
		gui.LightInfluence = 0; gui.Brightness = 1
        gui.AlwaysOnTop = part == self.PreviewPart
		gui.MaxDistance = Config.ScreenMaxDistance
		local image = Instance.new("ImageLabel")
		image.Name = "Picture"; image.Size = UDim2.fromScale(1, 1)
		image.BackgroundColor3 = Color3.new(0, 0, 0); image.BorderSizePixel = 0
		if self.Editable then image.ImageContent = Content.fromObject(self.Editable) end
		image.ScaleType = Enum.ScaleType.Fit
		image.Visible = self.Displayed > 0
		image.Parent = gui
		local status = Instance.new("TextLabel")
		status.Name = "Status"; status.Size = UDim2.fromScale(0.8, 0.16)
		status.Position = UDim2.fromScale(0.1, 0.42); status.BackgroundTransparency = 0.25
		status.BackgroundColor3 = Color3.new(0, 0, 0); status.TextColor3 = Color3.new(1, 1, 1)
		status.Font = Enum.Font.GothamMedium; status.TextScaled = true; status.TextWrapped = true
		status.Text = if self.CapabilityError then "Video unavailable on this device" else "Loading video…"
		status.Visible = self.Displayed == 0
		status.Parent = gui
		local bar = Instance.new("Frame")
		bar.Name = "LoadingBar"; bar.Size = UDim2.fromScale(0.5, 0.012)
		bar.Position = UDim2.fromScale(0.25, 0.61); bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.fromRGB(47, 52, 48)
		bar.Visible = self.Displayed == 0 and self.CapabilityError == nil
		bar.Parent = gui
		local fill = Instance.new("Frame")
		fill.Name = "Fill"; fill.BorderSizePixel = 0
		fill.BackgroundColor3 = Color3.fromRGB(202, 225, 180)
		fill.Size = UDim2.fromScale(self.LoadingProgress, 1); fill.Parent = bar
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
		table.insert(surfaces, gui)
	end
	self.Surfaces[part] = surfaces
end
function Renderer.SetVideo(self: Display, width: number, height: number, _title: string): boolean
	if self.Destroyed then return false end
    self.Title = _title
	if self.Width == width and self.Height == height and self.Editable then
        if self.Controls then self.Controls:SetImage(self.Editable, self.Title) end
        return true
    end
	clearSurfaces(self)
    if self.Controls then self.Controls:SetImage(nil, self.Title) end
	if self.Editable then self.Editable:Destroy(); self.Editable = nil end
	self.Width = width; self.Height = height; self.CapabilityError = nil
	self.Displayed = 0
	if self.PreviewPart then
		self.PreviewPart.Size = Vector3.new(Config.ScreenHeight * width / height, Config.ScreenHeight, 0.08)
	end
	local ok, result = pcall(function() return AssetService:CreateEditableImage({Size = Vector2.new(width, height)}) end)
	if not ok or not result then
		self.CapabilityError = if ok then "EditableImage memory allocation unavailable" else tostring(result)
		return false
	end
	self.Editable = result
    if self.Controls then self.Controls:SetImage(self.Editable, self.Title) end
	return true
end
function Renderer.SetSource(self: Display, clock: any, track: string)
	if self.Destroyed then return end
	self.Source = clock; self.Track = track
	if os.clock() - self.LastScan < 0.2 then return end
	self.LastScan = os.clock()
	local wanted: {[BasePart]: boolean} = {}
	if clock.Preview then
		if not self.PreviewPart then
			local part = Instance.new("Part")
			part.Name = "VideoEmotePreview"; part.Anchored = true
			part.CanCollide = false; part.CanTouch = false; part.CanQuery = false
			part.CastShadow = false; part.Color = Color3.new(0, 0, 0)
			part.Size = Vector3.new(Config.ScreenHeight * self.Width / self.Height, Config.ScreenHeight, 0.08)
            part.CFrame = if workspace.CurrentCamera then workspace.CurrentCamera.CFrame else CFrame.new(0, 8, 0)
			part.Parent = workspace
			self.PreviewPart = part
		end
        self:UpdatePreview()
		wanted[self.PreviewPart :: Part] = true
	else
		if self.PreviewPart then self.PreviewPart:Destroy(); self.PreviewPart = nil end
		local folder = workspace:FindFirstChild("VideoEmoteScreens")
		if folder then
			for _, part in folder:GetChildren() do
				if part:IsA("BasePart") and part:GetAttribute("VideoTrack") == track
					and math.abs((part:GetAttribute("StartTime") or -1) - clock.StartTime) < 0.05
					and math.abs((part:GetAttribute("PlaybackSpeed") or 1) - clock.Rate) < 0.001 then wanted[part] = true end
			end
		end
	end
	for part, surfaces in self.Surfaces do
		if not wanted[part] or not part.Parent then
			for _, surface in surfaces do surface:Destroy() end
			self.Surfaces[part] = nil
		end
	end
	for part in wanted do attach(self, part) end
end
function Renderer.SetVisible(self: Display, visible: boolean, reset: boolean?)
	if self.Destroyed then return end
	self.Visible = visible
    if visible then ensureControls(self) end
    if self.Controls then self.Controls:SetActive(visible) end
	if reset then
		self.Displayed = 0; self.LoadingProgress = 0; self.LastScan = 0
		refreshLoading(self)
	end
	if not visible then
		clearSurfaces(self)
		if self.PreviewPart then self.PreviewPart:Destroy(); self.PreviewPart = nil end
		self.Source = nil
	end
end
function Renderer.SetStatus(self: Display, state: string, position: number, duration: number, progress: number)
	if self.Destroyed then return end
	self.LoadingProgress = if progress == progress then math.clamp(progress, 0, 1) else 0
	for _, surfaces in self.Surfaces do
		for _, surface in surfaces do
			-- Keep diagnostics available without putting transport state over the video.
			surface:SetAttribute("State", state)
			surface:SetAttribute("Position", position)
			surface:SetAttribute("Duration", duration)
		end
	end
	refreshLoading(self)
end

function Renderer.Write(self: Display, pixels: buffer): boolean
	if self.Destroyed or not self.Editable or buffer.len(pixels) ~= self.Width * self.Height * 4 then return false end
	local began = os.clock()
	local ok, reason = pcall(function() (self.Editable :: EditableImage):WritePixelsBuffer(Vector2.zero, Vector2.new(self.Width, self.Height), pixels) end)
	self.LastWriteMs = (os.clock() - began) * 1000
	if not ok then self.CapabilityError = tostring(reason); return false end
	self.Displayed += 1
	if self.Displayed == 1 then refreshLoading(self) end
	return true
end
function Renderer.Destroy(self: Display)
	if self.Destroyed then return end
	self:SetVisible(false)
	self.Destroyed = true
    if self.Controls then self.Controls:Destroy(); self.Controls = nil end
	if self.Editable then self.Editable:Destroy(); self.Editable = nil end
end
return Renderer
