--!strict
-- Builds one toggle control from its setting definition.
local clientRoot = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", 10)
local Scope = require(game:GetService("ReplicatedStorage").Shared.Utils.Scope)
local ClientState = require(clientRoot.ClientState)
local Settings = require(clientRoot.Controllers.SettingsController)
local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
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
	local switchButton = group:WaitForChild("Switch",10)
	local nameLabel = group:WaitForChild("Name",10)
	local descLabel = group:FindFirstChild("Desc")
	local knob = switchButton:FindFirstChild("Knob")

	nameLabel.Text = def.Name
	if descLabel and def.Description then
		descLabel.Text = def.Description
	end

	bindInteractiveScale(switchButton, 1.05, 0.94)

	local currentState = settingsCache[def.Id]
	if currentState == nil then currentState = def.Default end

	local function setState(state: boolean, fireChange: boolean)
		switchButton:SetAttribute("On", state)

		if knob then
			local targetX = state and CONFIG.ToggleMaxX or CONFIG.ToggleMinX
			playTween(knob, CONFIG.switchTween, {
				Position = UDim2.new(targetX, 0, knob.Position.Y.Scale, knob.Position.Y.Offset),
			})
		end

		playTween(switchButton, CONFIG.switchTween, {
			BackgroundColor3 = state and CONFIG.AccentColor or CONFIG.InactiveColor,
		})

		if fireChange then
			applySetting(def.Id, state)
		end
	end

	scope:Connect(switchButton.MouseButton1Click, function()
		currentState = not currentState
		setState(currentState, true)
	end)

	scope:Connect(switchButton.MouseEnter, function()
		local baseColor = currentState and CONFIG.AccentColor or CONFIG.InactiveColor
		playTween(switchButton, CONFIG.hoverTween, {
			BackgroundColor3 = modifyColor(baseColor, CONFIG.HoverColorModifier),
		})
	end)

	scope:Connect(switchButton.MouseLeave, function()
		local baseColor = currentState and CONFIG.AccentColor or CONFIG.InactiveColor
		playTween(switchButton, CONFIG.hoverTween, { BackgroundColor3 = baseColor })
	end)

	setState(currentState, false)

	rowRefs[def.Id] = {
		refresh = function(value: boolean)
			currentState = value
			setState(value, false)
		end,
	}
end

-- ============================================================
-- FriendPicker
-- ============================================================


end
