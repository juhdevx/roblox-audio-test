--!strict
-- Enforces server-side command/group permissions and per-player request limits.
local Config = require(game:GetService("ServerStorage").Config.PermissionConfig)
local Permissions = require(script.Parent.Parent.Modules.Permissions)
local RateLimiter = require(game:GetService("ReplicatedStorage").Shared.Utils.RateLimiter)
local limiter = RateLimiter.new(15, 3)
local Security = {}
function Security.Register(registry: any)
    registry:RegisterHook("BeforeRun", function(context)
        local minimum = Config.GroupMinimumTier[context.Group]
        if minimum == nil then return "Command group has no permission rule." end
        minimum = math.max(minimum, Config.CommandMinimumTier[context.Name] or 0)
        if not Permissions.atLeast(context.Executor, minimum) then return "Insufficient permissions." end
        if not limiter:Allow(context.Executor, context.Name) then return "Rate limited." end
        return nil
    end, 0)
end
function Security.Remove(player: Player) limiter:Remove(player) end
function Security.Destroy() limiter:Destroy() end
return Security
