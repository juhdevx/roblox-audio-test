--!strict
-- Builds one slider control from its setting definition.
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
local Scope = require(game:GetService("ReplicatedStorage").Shared.Utils.Scope)
local ClientState = require(clientRoot.ClientState)
local Settings = require(clientRoot.Controllers.SettingsController)
local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
return function(context: any, parentScope: any)
local CONFIG=context.CONFIG
local settingsCache=context.settingsCache
local rowRefs=context.rowRefs
local applySetting=context.applySetting
local playTween=context.playTween
local modifyColor=context.modifyColor
local bindInteractiveScale=context.bindInteractiveScale
local openFriendBrowser=context.openFriendBrowser
return function(row: any, def: any)
local scope=Scope.new()
parentScope:Add(scope)
row.Destroying:Once(function() scope:Destroy() end)
	local group = row:FindFirstChildOfClass("CanvasGroup") or row
	local track = group:WaitForChild("Track",10)
	local fill = track:WaitForChild("Fill",10)
	local knob = track:WaitForChild("Knob",10)
	local valueLabel = knob:WaitForChild("ValueLabel",10)
	local nameLabel = group:WaitForChild("Name",10)
	local descLabel = group:FindFirstChild("Desc")

	nameLabel.Text = def.Name
	if descLabel and def.Description then
		descLabel.Text = def.Description
	end

	local min = def.Min or 0
	local max = def.Max or 1
	local step = def.Step or 0.01
    local currentValue = min
    track.Selectable = true
    track.Active = true
    track.NextSelectionLeft = track
    track.NextSelectionRight = track

	local knobScale = Instance.new("UIScale")
	knobScale.Parent = knob
	knobScale.Scale = 1

	-- NOVO: guarda tweens pra cancelar antes de recriar
	local fillTween: Tween? = nil
	local knobTween: Tween? = nil

	local function setAlpha(alpha: number, fireChange: boolean)
		alpha = math.clamp(alpha, 0, 1)
		local rawValue = min + (max - min) * alpha
		local steppedValue = math.clamp(math.floor(rawValue / step + 0.5) * step, min, max)
		local displayAlpha = (steppedValue - min) / (max - min)
        currentValue = steppedValue

		-- NOVO: cancela tween antigo antes de criar novo (evita acumular)
		if fillTween then fillTween:Cancel() end
		if knobTween then knobTween:Cancel() end

		fillTween = scope:Tween(fill, CONFIG.sliderTween, { Size = UDim2.new(displayAlpha, 0, 1, 0) })
		knobTween = scope:Tween(knob, CONFIG.sliderTween, {
			Position = UDim2.new(displayAlpha, 0, knob.Position.Y.Scale, knob.Position.Y.Offset),
		})
		fillTween:Play()
		knobTween:Play()

		if max > 1 then
			valueLabel.Text = string.format("%.0f", steppedValue)
		else
			valueLabel.Text = string.format("%.0f%%", displayAlpha * 100)
		end

		if fireChange then
			applySetting(def.Id, steppedValue)
		end
	end

	local dragging = false
    local dragInput: InputObject? = nil

	local function updateFromInput(inputPosition: Vector3)
        if track.AbsoluteSize.X <= 0 then return end
		local relative = (inputPosition.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
		setAlpha(relative, true)
	end

	-- NOVO: as 3 conexões abaixo são LOCAIS ao slider, mas o InputChanged/InputEnded
	-- global dispara pra TODO slider. Solução: checar "dragging" antes de processar
	-- (já estava assim, mas agora cancelamos tweens antigos — o leak real era tween)
	scope:Connect(track.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
            dragInput = input
			playTween(knobScale, CONFIG.hoverTween, { Scale = 1.3 })
			updateFromInput(input.Position)
		end
	end)

	scope:Connect(track.MouseEnter, function()
		if not dragging then
			playTween(knobScale, CONFIG.hoverTween, { Scale = 1.15 })
		end
	end)

	scope:Connect(track.MouseLeave, function()
		if not dragging then
			playTween(knobScale, CONFIG.hoverTween, { Scale = 1 })
		end
	end)

	-- NOVO: conexão global rastreada por slider, com limpeza quando o slider morre
	local inputChangedConn = scope:Connect(UserInputService.InputChanged, function(input)
		if dragging and dragInput and (input == dragInput
            or (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
			updateFromInput(input.Position)
		end
	end)

	local inputEndedConn = scope:Connect(UserInputService.InputEnded, function(input)
		if dragging and dragInput and (input == dragInput
            or (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
			dragging = false
            dragInput = nil
			playTween(knobScale, CONFIG.hoverTween, { Scale = 1 })
		end
	end)

    scope:Connect(UserInputService.InputBegan, function(input, processed)
        if GuiService.SelectedObject ~= track or UserInputService:GetFocusedTextBox() then return end
        local key = input.KeyCode
        local delta = if key == Enum.KeyCode.Left or key == Enum.KeyCode.DPadLeft then -step
            elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.DPadRight then step else 0
        if delta ~= 0 then setAlpha((currentValue + delta - min) / (max - min), true) end
    end)

	-- NOVO: auto-limpa conexões quando o row é destruído (clearRows)
	scope:Connect(row.Destroying, function()
		inputChangedConn:Disconnect()
		inputEndedConn:Disconnect()
	end)

	local initialValue = settingsCache[def.Id]
	if initialValue == nil then initialValue = def.Default end
	setAlpha((initialValue - min) / (max - min), false)

	rowRefs[def.Id] = {
		refresh = function(value: number)
			setAlpha((value - min) / (max - min), false)
		end,
	}
end

-- ============================================================
-- Toggle
-- ============================================================


end
