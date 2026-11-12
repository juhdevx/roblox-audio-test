--!strict
-- Creates and validates project remotes before any handlers start.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local definitions = {
    SpectralAudio = {Request="RemoteEvent", Data="RemoteEvent"},
    AudioSequence = {Request="RemoteEvent", Data="RemoteEvent", State="RemoteEvent"},
    Player = {GetEmotes="RemoteFunction", StartEmote="RemoteEvent", UpdateEmoteWheel="RemoteEvent", R6LookReplication="RemoteEvent"},
    Gui = {RefreshViewport="RemoteEvent", UpdateViewport="RemoteEvent"},
    Settings = {GetSetting="RemoteFunction", GetAllSettings="RemoteFunction", SetSetting="RemoteEvent"},
    Effects = {EventShow="RemoteEvent", Lyrics="RemoteEvent"},
    Admin = {Notify="RemoteEvent"},
}
local RemoteService = {}
local root: Instance
local function ensure(parent: Instance, name: string, className: string): Instance
    local child = parent:FindFirstChild(name)
    if child then assert(child.ClassName == className, `Wrong remote class: {child:GetFullName()}`); return child end
    child = Instance.new(className)
    child.Name = name
    child.Parent = parent
    return child
end
function RemoteService.Init(_dependencies: any)
    root = ensure(ReplicatedStorage, "Remotes", "Folder")
    for group, names in pairs(definitions) do
        local folder = ensure(root, group, "Folder")
        for name, className in pairs(names) do ensure(folder, name, className) end
    end
end
function RemoteService.Get(group: string, name: string): any
    local folder = root:FindFirstChild(group)
    local remote = folder and folder:FindFirstChild(name)
    assert(remote, `Remote not registered: {group}.{name}`)
    return remote
end
function RemoteService.Start() end
function RemoteService.Destroy() end
return RemoteService

