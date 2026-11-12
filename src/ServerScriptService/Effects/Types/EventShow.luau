--!strict
-- Implements the EventShow server effect and its cleanup contract.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local remote: RemoteEvent
local getAudience = require(script.Parent.Parent.Audience)

local SCALE_STEP = 1 / 30
local SCALE_EPSILON = 0.001

local nextId = 0
local exclusiveCount = 0
local activeStates = {}

local EventShow = {}
local readyConnection: RBXScriptConnection? = nil



local function sortedByTime(list)
	local copy = {}
	for _, item in ipairs(list or {}) do
		if type(item) == "table" and type(item.Time) == "number" then
			table.insert(copy, item)
		end
	end
	table.sort(copy, function(a, b) return a.Time < b.Time end)
	return copy
end



local function buildScaleCues(params)
	local list = {}
	if params.BaseScale and params.BaseScale ~= 1 then
		local grow = params.Grow or {}
		table.insert(list, {
			Time = grow.Time or 0,
			Value = params.BaseScale,
			Duration = grow.Duration or 2.5,
		})
	end
	for _, cue in ipairs(params.Cues or {}) do
		if cue.Action == "Scale" and type(cue.Time) == "number" then
			table.insert(list, cue)
		end
	end
	return sortedByTime(list)
end

local function cleanup(state)
	if not state.active then return end
	state.active = false
	activeStates[state.id] = nil

	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end

	for _, viewer in ipairs(state.audience) do
		if viewer.Parent then
			remote:FireClient(viewer, "End", state.id)
		end
	end

	local character = state.character
	if state.exclusive then
		exclusiveCount = math.max(exclusiveCount - 1, 0)
		if exclusiveCount == 0 then
			-- ✅ MANTIDO: outros scripts dependem disso
			workspace:SetAttribute("EmoteShowActive", nil)
		end
		if character then
			character:SetAttribute("EmoteShowHost", nil)
		end
	end

	if character and character.Parent and math.abs(character:GetScale() - state.baseScale) > 0.001 then
		task.spawn(function()
			local from = character:GetScale()
			for i = 1, 14 do
				if not character.Parent then return end
				pcall(function()
					character:ScaleTo(from + (state.baseScale - from) * (i / 14))
				end)
				task.wait(SCALE_STEP)
			end
		end)
	end
end

local function runScaleTimeline(state, scaleCues, showLength, startTime)
	if #scaleCues == 0 then return end

	task.spawn(function()
		local character = state.character
		local last = -1
		local activeTween = nil
		local applied = state.scale

		while state.active and character.Parent do
			local t = (workspace:GetServerTimeNow() - startTime) % showLength
			local ranges = (t >= last)
				and { { last, t } }
				or { { last, showLength }, { -1, t } }

			for _, range in ipairs(ranges) do
				for _, cue in ipairs(scaleCues) do
					if cue.Time > range[1] and cue.Time <= range[2] then
						activeTween = {
							from = state.scale,
							to = state.baseScale * (cue.Value or 1),
							t0 = os.clock(),
							duration = math.max(cue.Duration or 0.5, 0.01),
						}
					end
				end
			end
			last = t

			if activeTween then
				local alpha = math.clamp((os.clock() - activeTween.t0) / activeTween.duration, 0, 1)
				local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				state.scale = activeTween.from + (activeTween.to - activeTween.from) * eased
				if alpha >= 1 then activeTween = nil end
			end

			-- ✅ ÚNICO fix de performance: só chama ScaleTo se mudou
			if math.abs(state.scale - applied) > SCALE_EPSILON then
				pcall(function() character:ScaleTo(state.scale) end)
				applied = state.scale
			end

			task.wait(SCALE_STEP)
		end
	end)
end

function EventShow.Start(player, character, params)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	nextId += 1
	local showLength = params.ShowLength or 560
	local startTime = workspace:GetServerTimeNow()

	local state = {
		id = nextId,
		active = true,
		character = character,
		audience = getAudience(player, character, params),
		baseScale = character:GetScale(),
		scale = character:GetScale(),
		connections = {},
		exclusive = false,
		joinable = (params.Scope or "All") == "All",
	}

	if state.joinable and params.ExclusiveAudio ~= false then
		state.exclusive = true
		exclusiveCount += 1
		character:SetAttribute("EmoteShowHost", true)
		-- ✅ MANTIDO: outros scripts dependem disso
		workspace:SetAttribute("EmoteShowActive", true)
	end

	state.payload = {
		Id = state.id,
		Character = character,
		HostUserId = player.UserId,
		StartTime = startTime,
		ShowLength = showLength,
		Fit = params.Fit ~= false,
		Lookahead = params.Lookahead or 0.04,
		Scenes = sortedByTime(params.Scenes),
		Cues = sortedByTime(params.Cues),
		Gravity = sortedByTime(params.Gravity),
		FadeOut = params.FadeOut or 2,
		Exclusive = state.exclusive,
		Zoom = params.CameraZoom ~= false,
		Debug = params.Debug == true,
	}

	activeStates[state.id] = state

	for _, viewer in ipairs(state.audience) do
		remote:FireClient(viewer, "Begin", state.payload)
	end

	runScaleTimeline(state, buildScaleCues(params), showLength, startTime)

	table.insert(state.connections, character:GetAttributeChangedSignal("Emoting"):Connect(function()
		if not character:GetAttribute("Emoting") then cleanup(state) end
	end))
	table.insert(state.connections, humanoid.Died:Connect(function() cleanup(state) end))
	table.insert(state.connections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then cleanup(state) end
	end))

	return state
end

function EventShow.Stop(state)
	cleanup(state)
end

function EventShow.Init(dependencies: any)
    remote = dependencies.RemoteService.Get("Effects", "EventShow")
    readyConnection = remote.OnServerEvent:Connect(function(player, action)
	if action ~= "Ready" then return end
	for _, state in pairs(activeStates) do
		if state.active and state.joinable and not table.find(state.audience, player) then
			table.insert(state.audience, player)
			remote:FireClient(player, "Begin", state.payload)
		end
	end
end)
end
function EventShow.Destroy()
    if readyConnection then readyConnection:Disconnect() end
    for _, state in pairs(activeStates) do cleanup(state) end
end

return EventShow
