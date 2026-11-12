--!strict
-- Initializes persistent client modules before starting their event subscriptions.
local root=script.Parent
local paths={
    {"Controllers","SettingsController"},
    {"Emotes","SoundVolume"},
    {"Controllers","SpectralAudioController"},
    {"Controllers","VideoSequenceController"},
    {"Controllers","MediaPreparationController"},
    {"UI","AvatarPreview"},
    {"Effects","AttachmentController"},
    {"Controllers","EmoteController"},
    {"Controllers","ShiftLockController"},
    {"Character","ProceduralAnimation"},
    {"Controllers","LookReplicationController"},
    {"Controllers","EventEffectsController"},
    {"Controllers","LyricEffectsController"},
    {"Controllers","BarsEffectsController"},
    {"Controllers","AdminController"},
    {"Controllers","ScreenController"},
    {"Controllers","AudioSequenceController"},
}
local modules={}
local dependencies={}
for _,path in paths do
    local folder=root:WaitForChild(path[1],10)
    assert(folder,"Missing client folder "..path[1])
    local source=folder:WaitForChild(path[2],10)
    assert(source,"Missing client module "..path[2])
    local module=require(source)
    modules[#modules+1]=module; dependencies[path[2]]=module
end
for _,module in modules do if module.Init then module.Init(dependencies) end end
for _,module in modules do if module.Start then module.Start() end end
script.Destroying:Once(function()
    for index=#modules,1,-1 do local module=modules[index]; if module.Destroy then module.Destroy() end end
end)

