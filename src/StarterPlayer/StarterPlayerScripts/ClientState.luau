--!strict
-- Stores observable client interaction state through a small explicit API.
local Signal = require(game:GetService("ReplicatedStorage").Shared.Utils.Signal)
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local platform = if GuiService:IsTenFootInterface() then "Console" elseif UserInputService.TouchEnabled and not (UserInputService.KeyboardEnabled or UserInputService.MouseEnabled or UserInputService.GamepadEnabled) then "Mobile" elseif game:GetService("VRService").VREnabled then "VR" else "Computer"
local values: {[string]: any} = {platform=platform, shiftlock=true, preventLockChange=false, preventLockToken=0, mouseUnlocked=false, preventMouseUnlock=false, preventMouseUnlockToken=0, inBooth=false, emoting=false, emoteWheelOpen=false, videoFullscreen=false}
local State = {Changed=Signal.new()}
function State.Get(key: string): any return values[key] end
function State.Set(key: string, value: any)
    if values[key] == value then return end
    values[key] = value
    State.Changed:Fire(key,value)
end
return State
