--!strict
-- Accepts only registry-defined, serializable setting values.
local definitions = require(script.Parent.Parent.Config.SettingsDefinitions)
local byId = {}
for _, tab in definitions do
    for _, definition in tab.Settings do
        assert(not byId[definition.Id], `Duplicate setting {definition.Id}`)
        byId[definition.Id] = definition
    end
end
local Validator = {}
function Validator.Validate(key: any, value: any): boolean
    if type(key) ~= "string" then return false end
    local definition = byId[key]
    if not definition then return false end
    if definition.Type == "Toggle" then return type(value) == "boolean" end
    if definition.Type == "Slider" then
        if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return false end
        if value < definition.Min or value > definition.Max then return false end
        local steps = (value - definition.Min) / definition.Step
        return math.abs(steps - math.round(steps)) < 0.001
    end
    if definition.Type == "FriendPicker" then
        return value == nil or (type(value) == "number" and value == value and value > 0 and value < 2^53 and value % 1 == 0)
    end
    return false
end
function Validator.Clean(saved: any): {[string]: any}
    local result = {}
    for key, definition in pairs(byId) do
        local value = if type(saved) == "table" then saved[key] else nil
        if value ~= nil and Validator.Validate(key, value) then result[key] = value
        else result[key] = definition.Default end
    end
    return result
end
return Validator
