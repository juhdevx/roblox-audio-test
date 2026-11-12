--!strict
-- Copies plain nested data so callers cannot mutate another system's state.
local TableUtils = {}
function TableUtils.Copy(value: any): any
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = TableUtils.Copy(item) end
    return copy
end
function TableUtils.Freeze(value: any): any
    if type(value) ~= "table" or table.isfrozen(value) then return value end
    for _, item in pairs(value) do TableUtils.Freeze(item) end
    return table.freeze(value)
end
return TableUtils
