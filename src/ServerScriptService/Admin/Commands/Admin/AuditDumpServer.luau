--!strict
-- Defines the AuditDumpServer admin command.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AuditLog = require(game:GetService("ServerScriptService").Admin.Modules.AuditLog)

return function(context, count)
	return AuditLog.dump(count)
end
