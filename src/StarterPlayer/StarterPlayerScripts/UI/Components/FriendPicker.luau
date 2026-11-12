--!strict
-- Builds one friendpicker control from its setting definition.
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
	local chooseButton = group:WaitForChild("ChooseButton",10)
	local currentValueLabel = group:WaitForChild("CurrentValue",10)
	local nameLabel = group:WaitForChild("Name",10)

	nameLabel.Text = def.Name

	bindInteractiveScale(chooseButton, 1.05, 0.95)

    local refreshToken = 0
	local function refresh(value: number?)
        refreshToken += 1
        local token = refreshToken
		if not value then
			currentValueLabel.Text = "Random"
			return
		end
		currentValueLabel.Text = "Loading..."
		scope:Spawn(function()
			local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, value)
            if not scope:IsAlive() or token ~= refreshToken then return end
			currentValueLabel.Text = ok and name or ("User " .. tostring(value))
		end)
	end

	scope:Connect(chooseButton.MouseButton1Click, function()
		openFriendBrowser(def)
	end)

	refresh(settingsCache[def.Id])
	rowRefs[def.Id] = { refresh = refresh }
end

-- ============================================================
-- Render / Tabs
-- ============================================================


end
