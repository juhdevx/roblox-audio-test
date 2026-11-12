--!strict
-- Owns disposable resources; Clean is reusable and Destroy is idempotent.
local Maid = {}
Maid.__index = Maid
export type Maid = typeof(setmetatable({ _tasks = {} :: {[number]: any}, _next = 0, _destroyed = false }, Maid))

local function dispose(resource: any)
    local kind = typeof(resource)
    if kind == "RBXScriptConnection" then resource:Disconnect()
    elseif kind == "thread" then
        if resource ~= coroutine.running() and coroutine.status(resource) ~= "dead" then task.cancel(resource) end
    elseif kind == "Instance" then
        if resource:IsA("Tween") then resource:Cancel() end
        resource:Destroy()
    elseif kind == "function" then resource()
    elseif kind == "table" and type(resource.Destroy) == "function" then resource:Destroy()
    elseif kind == "table" and type(resource.Disconnect) == "function" then resource:Disconnect()
    end
end

function Maid.new(): Maid
    return setmetatable({ _tasks = {}, _next = 0, _destroyed = false }, Maid)
end
function Maid:GiveTask(resource: any): number
    assert(resource ~= nil, "Cannot track nil")
    self._next += 1
    if self._destroyed then
        local ok, err = pcall(dispose, resource)
        if not ok then warn(err) end
    else self._tasks[self._next] = resource end
    return self._next
end
function Maid:Add<T>(resource: T): T
    self:GiveTask(resource)
    return resource
end
function Maid:Remove(id: number)
    self._tasks[id] = nil
end
function Maid:Clean()
    local pending = self._tasks
    self._tasks = {}
    for _, resource in pairs(pending) do
        if typeof(resource) == "RBXScriptConnection" then resource:Disconnect() end
    end
    for _, resource in pairs(pending) do
        local ok, err = pcall(dispose, resource)
        if not ok then warn("[Maid]", err) end
    end
end
function Maid:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    self:Clean()
end
Maid.DoCleaning = Maid.Clean
function Maid.isMaid(value: any): boolean
    return getmetatable(value) == Maid
end
return Maid
