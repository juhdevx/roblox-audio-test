--!strict
-- Owns event callbacks and scheduled work for a controller, screen, or effect.
local Maid = require(script.Parent.Maid)
local Scope = {}
Scope.__index = Scope
function Scope.new() return setmetatable({_maid=Maid.new(), _alive=true, _running={}},Scope) end
function Scope:Add(resource: any): any return self._maid:Add(resource) end
function Scope:Tween(instance: Instance, info: TweenInfo, properties: any): Tween
    local tween=game:GetService("TweenService"):Create(instance,info,properties)
    local id=self._maid:GiveTask(function() tween:Cancel(); tween:Destroy() end)
    tween.Completed:Once(function() self._maid:Remove(id) end)
    return tween
end
function Scope:_invoke(callback: (...any)->(), ...: any)
    if not self._alive then return end
    local running = coroutine.running()
    self._running[running] = true
    local ok, err = pcall(callback, ...)
    self._running[running] = nil
    if not ok then warn(err) end
end
function Scope:Connect(signal: any, callback: (...any)->()): any
    return self:Add(signal:Connect(function(...) self:_invoke(callback, ...) end))
end
function Scope:Once(signal: any, callback: (...any)->()): any
    return self:Add(signal:Once(function(...) self:_invoke(callback, ...) end))
end
function Scope:Spawn(callback: (...any)->(), ...: any): thread
    local arguments = table.pack(...)
    local id: number
    local job = coroutine.create(function()
        self:_invoke(callback, table.unpack(arguments,1,arguments.n))
        self._maid:Remove(id)
    end)
    id = self._maid:GiveTask(job)
    if self._alive then task.spawn(job) end
    return job
end
function Scope:Defer(callback: (...any)->(), ...: any): thread
    local arguments = table.pack(...)
    local id: number
    local job = coroutine.create(function()
        self:_invoke(callback, table.unpack(arguments,1,arguments.n))
        self._maid:Remove(id)
    end)
    id = self._maid:GiveTask(job)
    if self._alive then task.defer(job) end
    return job
end
function Scope:Delay(seconds: number, callback: (...any)->(), ...: any): thread
    local arguments = table.pack(...)
    local id: number
    local job = task.delay(seconds, function()
        self:_invoke(callback, table.unpack(arguments,1,arguments.n))
        self._maid:Remove(id)
    end)
    id = self._maid:GiveTask(job)
    return job
end
function Scope:IsAlive(): boolean return self._alive end
function Scope:Destroy()
    if not self._alive then return end
    self._alive = false
    self._maid:Destroy()
    for job in pairs(self._running) do
        if job ~= coroutine.running() and coroutine.status(job) ~= "dead" then pcall(task.cancel,job) end
    end
    table.clear(self._running)
end
return Scope
