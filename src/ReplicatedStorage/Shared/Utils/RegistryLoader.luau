--!strict
-- Loads only explicitly scoped plugin folders and rejects duplicate keys.
local RegistryLoader = {}
function RegistryLoader.Load(folder: Instance, keyField: string?): {[string]: any}
    local result = {}
    for _, child in folder:GetChildren() do
        if child:IsA("ModuleScript") then
            local entry = require(child)
            assert(type(entry) == "table", `Invalid registry entry {child:GetFullName()}`)
            local key = if keyField then entry[keyField] else child.Name
            assert(type(key) == "string" and key ~= "", `Missing registry key: {child.Name}`)
            assert(result[key] == nil, `Duplicate registry key {key}`)
            result[key] = entry
        end
    end
    return result
end
return RegistryLoader
