--!strict
-- Dispatches local events while preserving argument identity across services.
local Signal = {}
Signal.__index = Signal
function Signal.new()
    return setmetatable({ _listeners = {}, _waiters = {}, _destroyed = false }, Signal)
end
function Signal:Connect(callback: (...any) -> ())
    assert(not self._destroyed, "Signal destroyed")
    local listeners=self._listeners
    local connection={Connected=true,Callback=callback}
    function connection:Disconnect() self.Connected=false; listeners[self]=nil end
    listeners[connection]=true
    return connection
end
function Signal:Once(callback: (...any) -> ())
    local connection=self:Connect(callback)
    connection.Once=true
    return connection
end
function Signal:Fire(...: any)
    if self._destroyed then return end
    local listeners={}
    for connection in pairs(self._listeners) do table.insert(listeners,connection) end
    for _,connection in listeners do
        if connection.Connected then
            if connection.Once then connection:Disconnect() end
            task.spawn(connection.Callback,...)
        end
    end
end
function Signal:Wait(): ...any
    local waiting=coroutine.running()
    self._waiters[waiting]=true
    self:Once(function(...)
        self._waiters[waiting]=nil
        if coroutine.status(waiting)=="suspended" then task.spawn(waiting,...) end
    end)
    return coroutine.yield()
end
function Signal:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    for connection in pairs(self._listeners) do connection:Disconnect() end
    for waiting in pairs(self._waiters) do if waiting~=coroutine.running() then pcall(task.cancel,waiting) end end
    table.clear(self._waiters)
end
return Signal
