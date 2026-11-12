--!strict
-- Configures Cmdr and presents server-issued administration notifications.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Scope=require(ReplicatedStorage.Shared.Utils.Scope)
local scope=Scope.new()
local Controller={}
function Controller.Init(_dependencies: any) end
function Controller.Start()
    local module=ReplicatedStorage:WaitForChild("CmdrClient",15)
    assert(module,"CmdrClient did not initialize")
    local Cmdr=require(module)
    Cmdr:SetActivationKeys({Enum.KeyCode.F2})
    Cmdr:SetPlaceName("Uh's... Modded Emotes")
    Cmdr:SetActivationUnlocksMouse(true)
    Cmdr:SetHideOnLostFocus(true)
    scope:Connect(ReplicatedStorage.Remotes.Admin.Notify.OnClientEvent,function(message)
        local text=if type(message)=="table" then tostring(message.text or message.Text or message.Message or "") else tostring(message)
        pcall(function() game:GetService("StarterGui"):SetCore("SendNotification",{Title="Emotes",Text=text,Duration=5}) end)
    end)
end
function Controller.Destroy() scope:Destroy() end
return Controller
