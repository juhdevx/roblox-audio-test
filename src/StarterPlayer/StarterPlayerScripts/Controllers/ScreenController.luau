--!strict
-- Discovers screen modules and mounts one lifecycle per matching PlayerGui child.
local Players=game:GetService("Players")
local Scope=require(game:GetService("ReplicatedStorage").Shared.Utils.Scope)
local root=script.Parent.Parent
local Controller={}
local scope=Scope.new()
local registry={}
local mounted={}
local pending={}
function Controller.Init(_dependencies: any)
    for _,module in root.UI.Screens:GetChildren() do
        if module:IsA("ModuleScript") then
            local screen=require(module)
            assert(type(screen.Name)=="string" and type(screen.GuiName)=="string" and type(screen.Mount)=="function","Invalid screen "..module.Name)
            assert(not registry[screen.GuiName],"Duplicate screen GUI "..screen.GuiName)
            registry[screen.GuiName]=screen
        end
    end
end
function Controller.CloseOthers(name: string)
    for _,entry in pairs(mounted) do if entry.Name~=name then entry.Runtime.Close() end end
end
local function mount(gui: Instance)
    local screen=registry[gui.Name]
    if not screen or mounted[gui] or pending[gui] then return end
    pending[gui]=true
    scope:Spawn(function()
        local ok,runtime=pcall(screen.Mount,gui,Controller)
        pending[gui]=nil
        if not ok then warn("Screen "..screen.Name..": "..tostring(runtime)); return end
        if not gui.Parent or not scope:IsAlive() then runtime.Destroy(); return end
        mounted[gui]={Name=screen.Name,Runtime=runtime}
    end)
end
function Controller.Start()
    local gui=Players.LocalPlayer:WaitForChild("PlayerGui",10)
    assert(gui,"PlayerGui missing")
    scope:Connect(gui.ChildAdded,mount)
    scope:Connect(gui.ChildRemoved,function(child)
        local entry=mounted[child]; mounted[child]=nil
        if entry then entry.Runtime.Destroy() end
    end)
    for _,child in gui:GetChildren() do mount(child) end
end
function Controller.Destroy()
    for _,entry in pairs(mounted) do entry.Runtime.Destroy() end
    table.clear(mounted); scope:Destroy()
end
return Controller
