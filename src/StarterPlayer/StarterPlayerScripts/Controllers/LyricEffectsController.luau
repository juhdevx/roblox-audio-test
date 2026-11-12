--!strict
-- Owns LyricEffectsController and its connections for one client lifetime.
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
-- Owns LyricEffectsController visual sessions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local remote = ReplicatedStorage.Remotes.Effects.Lyrics

local okVfx, GetVFXFolder = pcall(function()
	return require(ReplicatedStorage.Shared.Utils.GetVFXFolder)
end)

local sessions = {}

local REVEAL_TIME = 0.38
local LATE_LIMIT = 0.75

local ASSET_ROTATION = CFrame.Angles(0, 0, 0)

local function vfxParent()
	if okVfx and type(GetVFXFolder) == "function" then
		local ok, folder = pcall(GetVFXFolder)
		if ok and folder then return folder end
	end
	return workspace
end

local function vfxHidden()
	local settings = Settings.GetSnapshot()
	return settings and settings.HideEmoteVFX or false
end

-- FIX #1: cache de splitChars
local splitCache: { [string]: { string } } = {}
local splitCacheCount = 0
local SPLIT_CACHE_MAX = 200

local function splitChars(text: string): { string }
	local cached = splitCache[text]
	if cached then return cached end

	local chars = {}
	local ok = pcall(function()
		for _, code in utf8.codes(text) do
			table.insert(chars, utf8.char(code))
		end
	end)
	if not ok then
		for i = 1, #text do
			table.insert(chars, text:sub(i, i))
		end
	end

	-- Cache com cap
	if splitCacheCount >= SPLIT_CACHE_MAX then
		table.clear(splitCache)
		splitCacheCount = 0
	end
	splitCache[text] = chars
	splitCacheCount += 1
	return chars
end

local function isBasePart(object)
	return object and object:IsA("BasePart")
end

local function isModel(object)
	return object and object:IsA("Model")
end

local function getAsset(char)
	local asset = ReplicatedStorage.Assets.LyricGlyphs:FindFirstChild(char)
	if asset then return asset end
	local upper = char:upper()
	if upper ~= char then
		asset = ReplicatedStorage.Assets.LyricGlyphs:FindFirstChild(upper)
		if asset then return asset end
	end
	return nil
end

local function getAssetSize(asset)
	if isBasePart(asset) then return asset.Size end
	if isModel(asset) then
		local _, size = asset:GetBoundingBox()
		return size
	end
	return Vector3.zero
end

local function getAssetPivot(asset)
	if isBasePart(asset) then return asset.CFrame end
	if isModel(asset) then return asset:GetPivot() end
	return CFrame.identity
end

local function setAssetPivot(asset, cf)
	if isBasePart(asset) then asset.CFrame = cf
	elseif isModel(asset) then asset:PivotTo(cf) end
end

local function tweenAssetPivot(asset, targetCF, duration, easingStyle, easingDirection)
	if isBasePart(asset) then
		return TweenService:Create(asset, TweenInfo.new(duration, easingStyle, easingDirection), {CFrame = targetCF})
	end
	if isModel(asset) then
		local value = Instance.new("CFrameValue")
		value.Value = asset:GetPivot()
		local connection
		connection = scope:Connect(value:GetPropertyChangedSignal("Value"), function()
			if asset.Parent then asset:PivotTo(value.Value) end
		end)
		local tween = TweenService:Create(value, TweenInfo.new(duration, easingStyle, easingDirection), {Value = targetCF})
		scope:Connect(tween.Completed, function()
			if connection then connection:Disconnect() end
			value:Destroy()
		end)
		return tween
	end
	return nil
end

local function getParts(asset)
	local parts = {}
	if isBasePart(asset) then table.insert(parts, asset)
	else
		for _, object in ipairs(asset:GetDescendants()) do
			if object:IsA("BasePart") then table.insert(parts, object) end
		end
	end
	return parts
end

local function prepareAsset(asset)
	for _, part in ipairs(getParts(asset)) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
	end
end

local function setTransparency(asset, value)
	for _, part in ipairs(getParts(asset)) do part.Transparency = value end
end

local function scaleAsset(asset, scale)
	if isBasePart(asset) then asset.Size *= scale
	elseif isModel(asset) then pcall(function() asset:ScaleTo(scale) end) end
end

-- FIX #4: guard em getCharacterScale
local function getCharacterScale(character)
	if not character then return 1 end
	local ok, scale = pcall(function() return character:GetScale() end)
	if ok and type(scale) == "number" and scale > 0 then return scale end
	return 1
end

local function getBehindPosition(character, distance, height)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local scale = getCharacterScale(character)
	distance *= scale
	height *= scale
	return root.Position - root.CFrame.LookVector * distance + Vector3.new(0, height, 0)
end

local function getBehindBasis(character, position)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local forward = root.CFrame.LookVector
	local flatForward = Vector3.new(forward.X, 0, forward.Z)
	if flatForward.Magnitude <= 0.001 then flatForward = Vector3.new(0, 0, -1)
	else flatForward = flatForward.Unit end
	return CFrame.lookAt(position, position + flatForward, Vector3.yAxis)
end

local function createLetter(container, char, position, basis, scale, style)
	local source = getAsset(char)
	if not source then return nil end
	local asset = source:Clone()
	asset.Name = "Letter_" .. char
	asset.Parent = container
	prepareAsset(asset)
	local originalSize = getAssetSize(asset)
	if originalSize.Magnitude <= 0 then asset:Destroy(); return nil end
	scaleAsset(asset, scale)
	local scaledSize = getAssetSize(asset)
	local targetCF = CFrame.lookAt(position, position + basis.LookVector, Vector3.yAxis) * ASSET_ROTATION
	setAssetPivot(asset, targetCF)
	setTransparency(asset, 1)
	local parts = getParts(asset)
	for _, part in ipairs(parts) do part:SetAttribute("LyricOriginalTransparency", 0) end
	return { Asset = asset, Parts = parts, Width = scaledSize.X, Height = scaledSize.Y, Depth = scaledSize.Z, Target = targetCF }
end

local function revealLetter(letter, delayTime, style, revealTime)
	if not letter or not letter.Asset then return end
	local asset = letter.Asset
	local targetCF = letter.Target
	local duration = revealTime or REVEAL_TIME
	local startCF = targetCF
		* CFrame.new(0, -(letter.Height * 0.9), 0)
		* CFrame.Angles(
			math.rad(math.random(-12, 12)),
			math.rad(math.random(-12, 12)),
			math.rad(math.random(-12, 12))
		)
	setAssetPivot(asset, startCF)
	setTransparency(asset, 1)

	scope:Delay(delayTime, function()
		-- FIX #3: pcall
		local ok = pcall(function()
			if not asset.Parent then return end
			local effectStyle = style or {}
			local easingStyle = effectStyle.RevealEasingStyle or Enum.EasingStyle.Back
			local easingDirection = effectStyle.RevealEasingDirection or Enum.EasingDirection.Out
			local pivotTween = tweenAssetPivot(asset, targetCF, duration, easingStyle, easingDirection)
			if pivotTween then pivotTween:Play() end
			local transparencyTime = effectStyle.TransparencyTime or duration * 0.8
			for _, part in ipairs(letter.Parts) do
				if part.Parent then
					TweenService:Create(part, TweenInfo.new(transparencyTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0 }):Play()
				end
			end
		end)
		if not ok then warn("[EmoteLyricClient] revealLetter erro") end
	end)
end

local function dropLine(session, line)
	if not line or line.Dropping then return end
	line.Dropping = true
	if session.Current == line then session.Current = nil end
	local effect = line.Effect or {}
	local dropTime = effect.DropTime or 0.6
	local dropDelay = effect.DropDelay or session.Style.FallDelay
	local dropTransparencyTime = effect.DropTransparencyTime or dropTime * 0.75

	for index, letter in ipairs(line.Letters) do
		local asset = letter.Asset
		if asset and asset.Parent then
			scope:Delay((index - 1) * dropDelay, function()
				-- FIX #3: pcall
				pcall(function()
					if not asset.Parent then return end
					local current = getAssetPivot(asset)
					local offset = Vector3.new(
						(math.random() - 0.5) * 0.8,
						-2.5 - math.random() * 2,
						(math.random() - 0.5) * 0.5
					)
					local target = current
						* CFrame.new(offset)
						* CFrame.Angles(
							math.rad(math.random(-120, 120)),
							math.rad(math.random(-120, 120)),
							math.rad(math.random(-120, 120))
						)
					local pivotTween = tweenAssetPivot(asset, target, dropTime,
						effect.DropEasingStyle or Enum.EasingStyle.Quad,
						effect.DropEasingDirection or Enum.EasingDirection.In)
					if pivotTween then pivotTween:Play() end
					for _, part in ipairs(letter.Parts) do
						if part.Parent then
							TweenService:Create(part, TweenInfo.new(dropTransparencyTime), { Transparency = 1 }):Play()
						end
					end
				end)
			end)
		end
	end

	scope:Delay((dropDelay * math.max(0, #line.Letters - 1)) + dropTime + 0.15, function()
		if line.Model and line.Model.Parent then line.Model:Destroy() end
	end)
end

local function showLine(session, data)
	if vfxHidden() then return end
	local character = session.Character
	if not character or not character.Parent then return end
	if type(data.Text) ~= "string" then return end
	if session.Current then dropLine(session, session.Current) end

	-- FIX #1: usa splitChars cacheado
	local chars = splitChars(data.Text)
	if #chars == 0 then return end

	local style = session.Style
	local effect = data.Effect or {}
	local revealTime = effect.RevealTime or REVEAL_TIME
	local letterDelay = effect.LetterDelay or style.LetterDelay or 0.055
	local hold = effect.Hold or data.Hold or style.Hold or 1.2
	local scale = getCharacterScale(character)
	local letterScale = (style.LetterSize or 1) * scale
	local distance = (style.Distance or 4) * scale
	local height = (style.Height or 2) * scale
	local position = getBehindPosition(character, distance, height)
	if not position then return end
	local basis = getBehindBasis(character, position)
	if not basis then return end

	local container = Instance.new("Model")
	container.Name = "Lyric3D"
	container.Parent = vfxParent()

	local line = { Model = container, Letters = {}, Dropping = false, Effect = effect }
	session.Current = line

	local spacing = (style.LetterSpacing or 0.08) * scale
	local entries = {}
	local totalWidth = 0

	for _, char in ipairs(chars) do
		if char == " " then
			local spaceWidth = (style.SpaceWidth or 0.45) * letterScale
			table.insert(entries, { Character = char, Width = spaceWidth })
			totalWidth += spaceWidth
		else
			local source = getAsset(char)
			if source then
				local sourceSize = getAssetSize(source)
				local width = sourceSize.X * letterScale
				table.insert(entries, { Character = char, Width = width })
				totalWidth += width
			end
		end
	end

	if #entries == 0 then
		container:Destroy()
		session.Current = nil
		return
	end

	totalWidth += math.max(0, #entries - 1) * spacing
	local cursor = -totalWidth / 2

	for index, entry in ipairs(entries) do
		local centerX = cursor + entry.Width / 2
		if entry.Character ~= " " then
			local letterPosition = position - basis.RightVector * centerX
			local letter = createLetter(container, entry.Character, letterPosition, basis, letterScale, style)
			if letter then
				table.insert(line.Letters, letter)
				local delayTime = (index - 1) * letterDelay
				revealLetter(letter, delayTime, style, revealTime)
			end
		end
		cursor += entry.Width + spacing
	end

	local revealDuration = (#entries - 1) * letterDelay + revealTime
	scope:Delay(revealDuration + hold, function()
		if line.Model and line.Model.Parent then dropLine(session, line) end
	end)
end

local function findFirstLoopIndex(lines, loopStart)
	for index, data in ipairs(lines) do
		if data.time >= loopStart then return index end
	end
	return #lines + 1
end

-- FIX #2: early-return no step
local function step(session)
	if session.Ended then return end
	local lines = session.Lines
	if #lines == 0 then return end

	local elapsed = workspace:GetServerTimeNow() - session.StartTime
	local loopStart = session.LoopStart
	local loopEnd = session.LoopEnd

	if not loopStart or not loopEnd then
		while true do
			local data = lines[session.Index]
			if not data then return end
			if elapsed < data.time then return end
			session.Index += 1
			if elapsed - data.time <= LATE_LIMIT then showLine(session, data) end
		end
	end

	if elapsed < loopStart then
		while true do
			local data = lines[session.Index]
			if not data then return end
			if data.time >= loopStart then return end
			if elapsed < data.time then return end
			session.Index += 1
			if elapsed - data.time <= LATE_LIMIT then showLine(session, data) end
		end
	end

	local loopLength = loopEnd - loopStart
	if loopLength <= 0 then return end

	local cycle = math.floor((elapsed - loopStart) / loopLength)
	local cycleElapsed = (elapsed - loopStart) % loopLength

	if cycle ~= session.Cycle then
		session.Cycle = cycle
		session.LoopIndex = findFirstLoopIndex(lines, loopStart)
		if session.Current then dropLine(session, session.Current) end
	end

	local firstLoopLineTime = 14.44
	local targetTime = loopStart + cycleElapsed
	if cycle > 0 then targetTime = firstLoopLineTime + cycleElapsed end

	while true do
		local data = lines[session.LoopIndex]
		if not data then return end
		if data.time < loopStart then session.LoopIndex += 1
		elseif data.time >= loopEnd then return
		elseif targetTime >= data.time then
			session.LoopIndex += 1
			if targetTime - data.time <= LATE_LIMIT then showLine(session, data) end
		else return end
	end
end

local function finish(id)
	local session = sessions[id]
	if not session then return end
	session.Ended = true
	if session.Connection then session.Connection:Disconnect(); session.Connection = nil end
	if session.Current then dropLine(session, session.Current) end
	sessions[id] = nil
end

local function begin(data)
	if type(data) ~= "table" then return end
	if not data.Id then return end
	if sessions[data.Id] then return end

	local style = data.Style or {}
	style.LetterDelay = style.LetterDelay or 0.055
	style.FallDelay = style.FallDelay or 0.025
	style.LetterSpacing = style.LetterSpacing or 0.08
	style.Distance = style.Distance or 4
	style.Height = style.Height or 2
	style.LetterSize = style.LetterSize or 1
	style.Hold = style.Hold or 0.8

	local session = {
		Id = data.Id,
		Character = data.Character,
		StartTime = data.StartTime or workspace:GetServerTimeNow(),
		Lines = data.Lines or {},
		LoopStart = data.LoopStart,
		LoopEnd = data.LoopEnd,
		Style = style,
		Index = 1,
		LoopIndex = 1,
		Cycle = -1,
		Current = nil,
		Ended = false,
	}

	sessions[data.Id] = session
	session.Connection = scope:Connect(RunService.Heartbeat, function() step(session) end)
end

scope:Connect(remote.OnClientEvent, function(action, data)
	if action == "Begin" then begin(data)
	elseif action == "End" then finish(data) end
end)
scope:Add(function()
for id in pairs(sessions) do finish(id) end
end)
end
function Module.Destroy() if active then active:Destroy(); active=nil end end
return Module
