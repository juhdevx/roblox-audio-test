--!strict
-- Buffers one completed-command record and appends batches atomically by day.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local AuditLog = {}
local STORE_NAME = "CmdrAudit_v1"
local MAX_RETAIN = 500
local buffer = {}
local pending = {}
local store: any
local saving = false
local scheduled: thread? = nil
local alive = true
local function dayKey(timestamp: number): string return "Day_" .. os.date("%Y-%m-%d", timestamp) end
function AuditLog.Init(_dependencies: any) store = DataStoreService:GetDataStore(STORE_NAME) end
function AuditLog.flushNow(): boolean
    if saving then return false end
    if #pending == 0 then return true end
    saving = true
    local batch = pending; pending = {}
    local byDay = {}
    for _, entry in batch do
        local key = dayKey(entry.t)
        byDay[key] = byDay[key] or {}; table.insert(byDay[key], entry)
    end
    local allSaved = true
    for key, entries in pairs(byDay) do
        local ok, err = pcall(function()
            store:UpdateAsync(key, function(existing)
                local list = if type(existing) == "table" then existing else {}
                local ids = {}
                for _, entry in list do if type(entry) == "table" and entry.id then ids[entry.id] = true end end
                for _, entry in entries do if not ids[entry.id] then table.insert(list, entry) end end
                while #list > MAX_RETAIN do table.remove(list, 1) end
                return list
            end)
        end)
        if not ok then
            allSaved = false; warn("[AuditLog]", err)
            for _, entry in entries do table.insert(pending, entry) end
        end
    end
    saving = false
    return allSaved
end
local function schedule()
    if scheduled or not alive then return end
    scheduled = task.delay(5, function()
        scheduled = nil
        AuditLog.flushNow()
        if #pending > 0 then schedule() end
    end)
end
function AuditLog.record(context: any)
    local entry = {id=HttpService:GenerateGUID(false), t=os.time(), executor=context.Executor.UserId,
        executorName=context.Executor.Name, command=context.Name, raw=context.RawText,
        response=tostring(context.Response or ""), group=context.Group, phase="Completed"}
    table.insert(buffer, entry); table.insert(pending, entry)
    if #buffer > MAX_RETAIN then table.remove(buffer, 1) end
    schedule()
end
function AuditLog.recent(count: number?): {any}
    local result = {}
    for index=math.max(1,#buffer-math.clamp(count or 25,0,MAX_RETAIN)+1),#buffer do table.insert(result,buffer[index]) end
    return result
end
function AuditLog.dump(count: number?): string
    local lines = {}
    for _, entry in AuditLog.recent(count) do
        table.insert(lines, string.format("[%s] %s (%d) ran '%s'", os.date("%H:%M:%S",entry.t), entry.executorName, entry.executor, entry.raw or entry.command))
    end
    return if #lines == 0 then "No recent activity." else table.concat(lines,"\n")
end
function AuditLog.Destroy()
    alive = false
    if scheduled then pcall(task.cancel, scheduled); scheduled = nil end
    local deadline = os.clock()+15
    while saving and os.clock()<deadline do task.wait(0.05) end
    AuditLog.flushNow()
end
return AuditLog
