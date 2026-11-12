--!strict
-- Implements the LyricText server effect and its cleanup contract.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote: RemoteEvent
local getAudience = require(script.Parent.Parent.Audience)

-- NOVO: caps de segurança
local MAX_LINES = 200
local MAX_LINE_LENGTH = 120

local nextId = 0
local LyricText = {}

-- ============================================================
-- Helpers (mantidos do original)
-- ============================================================

local function buildLines(params: any)
	local secondsPerBeat = 60 / (params.Bpm or 120)
	local offset = params.Offset or 0
	local lines = {}

	for _, line in ipairs(params.Lines or {}) do
		-- NOVO: cap no número de linhas
		if #lines >= MAX_LINES then
			warn(`[LyricText] Cap de {MAX_LINES} linhas atingido, ignorando o resto`)
			break
		end

		if type(line.Text) == "string" and line.Text ~= "" then
			-- NOVO: cap no tamanho do texto
			if #line.Text > MAX_LINE_LENGTH then
				warn(`[LyricText] Linha muito longa ({#line.Text} chars), ignorada`)
			else
				local copy = table.clone(line)
				if line.Time ~= nil then
					copy.time = line.Time + offset
				else
					copy.time = ((line.Beat or 0) * secondsPerBeat) + offset
				end
				table.insert(lines, copy)
			end
		end
	end

	table.sort(lines, function(a, b) return a.time < b.time end)

	local loopStart = nil
	local loopEnd = nil
	local loopLength = nil

	if params.LoopStartTime ~= nil then
		loopStart = params.LoopStartTime + offset
	end

	if params.LoopEndTime ~= nil then
		loopEnd = params.LoopEndTime + offset
	end

	if loopStart ~= nil and loopEnd ~= nil then
		loopLength = loopEnd - loopStart
		if loopLength <= 0 then
			warn("LyricText: LoopEndTime precisa ser maior que LoopStartTime")
			loopStart, loopEnd, loopLength = nil, nil, nil
		end
	elseif params.LoopBeats ~= nil then
		loopLength = params.LoopBeats * secondsPerBeat
		if loopStart ~= nil then
			loopEnd = loopStart + loopLength
		end
	end

	return lines, loopStart, loopEnd, loopLength
end

local function buildStyle(params: any)
	return {
		Color = params.Color or Color3.fromRGB(255, 255, 255),
		GlowColor = params.GlowColor or Color3.fromRGB(120, 200, 255),
		Font = params.Font or Enum.Font.GothamBlack,
		LetterSize = params.LetterSize or 3.2,
		Distance = params.Distance or 7,
		Height = params.Height or 3,
		LetterDelay = params.LetterDelay or 0.08,
		FallDelay = params.FallDelay or 0.05,
		Hold = params.Hold or 2.5,
		GlowThickness = params.GlowThickness or 3,
	}
end



local function cleanup(state: any)
	if not state.active then return end
	state.active = false

	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end

	for _, viewer in ipairs(state.audience) do
		if viewer.Parent then
			remote:FireClient(viewer, "End", state.id)
		end
	end
end

-- ============================================================
-- API pública (idêntica ao original)
-- ============================================================

function LyricText.Start(player: Player, character: Model, params: any)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	-- NOVO: validação de tipo
	if type(params) ~= "table" then return nil end

	local lines, loopStart, loopEnd, loopLength = buildLines(params)

	if #lines == 0 then
		warn("LyricText: nenhuma linha válida em Params.Lines")
		return nil
	end

	nextId += 1

	local state = {
		id = nextId,
		active = true,
		audience = getAudience(player, character, params),
		connections = {},
	}

	for _, viewer in ipairs(state.audience) do
		remote:FireClient(viewer, "Begin", {
			Id = state.id,
			Character = character,
			StartTime = workspace:GetServerTimeNow(),
			Lines = lines,
			LoopStart = loopStart,
			LoopEnd = loopEnd,
			LoopLength = loopLength,
			Style = buildStyle(params),
		})
	end

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

function LyricText.Stop(state: any)
	cleanup(state)
end

function LyricText.Init(dependencies: any)
    remote = dependencies.RemoteService.Get("Effects", "Lyrics")
end

return LyricText
