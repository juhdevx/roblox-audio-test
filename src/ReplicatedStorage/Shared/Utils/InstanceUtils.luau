--!strict
-- Resolves required instances with a bounded wait and descriptive errors.
local InstanceUtils = {}
function InstanceUtils.Wait(parent: Instance, name: string, className: string?): Instance
    local child = parent:WaitForChild(name, 10)
    assert(child, `Missing {parent:GetFullName()}.{name}`)
    assert(not className or child:IsA(className), `Wrong class for {child:GetFullName()}`)
    return child
end
return InstanceUtils
