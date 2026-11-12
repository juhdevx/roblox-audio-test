--!strict
-- Initializes Cmdr and registers only public definitions for client replication.
local Players = game:GetService("Players")
local Maid = require(game:GetService("ReplicatedStorage").Shared.Utils.Maid)
local root = script.Parent.Parent.Admin
local Notify = require(root.Modules.Notify)
local AuditLog = require(root.Modules.AuditLog)
local Security = require(root.Hooks.Security)
local Logging = require(root.Hooks.Logging)
local Service = {}
local maid = Maid.new()
function Service.Init(dependencies: any)
    Notify.Init(dependencies); AuditLog.Init(dependencies)
end
function Service.Start()
    local cmdr = require(game:GetService("ServerStorage").Packages.Cmdr)
    Security.Register(cmdr.Registry)
    Logging(cmdr.Registry)
    cmdr.Registry:RegisterDefaultCommands()
    cmdr.Registry:RegisterTypesIn(root.Types)
    cmdr.Registry:RegisterCommandsIn(root.Commands)
    maid:Add(Players.PlayerRemoving:Connect(Security.Remove))
    game:BindToClose(AuditLog.Destroy)
end
function Service.Destroy() maid:Destroy(); Security.Destroy(); AuditLog.Destroy() end
return Service
