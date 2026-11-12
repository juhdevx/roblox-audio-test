--!strict
-- Owns immutable client setting snapshots and debounced server updates.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Validator = require(Shared.Utils.SettingsValidator)
local Signal = require(Shared.Utils.Signal)
local Scope = require(Shared.Utils.Scope)
local Controller = {Changed=Signal.new()}
local snapshot = table.freeze(Validator.Clean(nil))
local scope = Scope.new()
local pending: {[string]: thread} = {}
local ready = false
local editedBeforeReady: {[string]: boolean} = {}
local function assign(key: string, value: any)
    local copy = table.clone(snapshot); copy[key] = value; snapshot = table.freeze(copy)
    Controller.Changed:Fire(key,value)
end
function Controller.Init(_dependencies: any) end
function Controller.Get(key: string): any return snapshot[key] end
function Controller.GetSnapshot(): {[string]: any} return snapshot end
function Controller.IsReady(): boolean return ready end
function Controller.Set(key: string, value: any): boolean
    if not Validator.Validate(key,value) then return false end
    if not ready then editedBeforeReady[key] = true end
    if ready and snapshot[key] == value then return true end
    assign(key,value)
    if pending[key] then pcall(task.cancel,pending[key]) end
    pending[key] = scope:Delay(0.6,function()
        pending[key] = nil
        ReplicatedStorage.Remotes.Settings.SetSetting:FireServer(key,value)
    end)
    return true
end
function Controller.Start()
    local ok,data=pcall(function() return ReplicatedStorage.Remotes.Settings.GetAllSettings:InvokeServer() end)
    if ok and type(data)=="table" then
        local loaded = Validator.Clean(data)
        for key in pairs(editedBeforeReady) do loaded[key] = snapshot[key] end
        snapshot = table.freeze(loaded)
    end
    table.clear(editedBeforeReady)
    ready=true
    for key,value in pairs(snapshot) do Controller.Changed:Fire(key,value) end
end
function Controller.Destroy()
    for key in pairs(pending) do ReplicatedStorage.Remotes.Settings.SetSetting:FireServer(key,snapshot[key]) end
    scope:Destroy(); Controller.Changed:Destroy()
end
return Controller
