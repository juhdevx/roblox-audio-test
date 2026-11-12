--!strict
-- Defines the WhoAmIServer admin command.
local Permissions = require(game:GetService("ServerScriptService").Admin.Modules.Permissions)

return function(context)
	local tier = Permissions.getTier(context.Executor)
	return string.format("Você é %s (ID %d) · cargo %s (nível %d)", context.Executor.Name, context.Executor.UserId, Permissions.tierName(tier), tier)
end
