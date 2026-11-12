--!strict
-- Records each completed server command once.
local AuditLog = require(script.Parent.Parent.Modules.AuditLog)
return function(registry: any)
    registry:RegisterHook("AfterRun", function(context) AuditLog.record(context); return nil end)
end
