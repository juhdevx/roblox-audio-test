--!strict
-- Listener controls shared by native emote sounds and the spectral renderer.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Settings = require(script.Parent.Parent.Controllers.SettingsController)
local LocalPlayer = Players.LocalPlayer
local multiplier = 1
local tracked: {[Sound]: any} = {}
local connections: {RBXScriptConnection} = {}
local Module = {}

local function bounded(value: any, fallback: number): number
	return if type(value) == "number" and value == value then math.clamp(value, 0, 1) else fallback
end
function Module.Get(): number return multiplier end
function Module.GetMediaVolume(): number return bounded(Settings.Get("MediaVolume"), 1) end
function Module.ClearDialogue(): boolean return Settings.Get("MediaClearDialogue") == true end
local function isOther(sound: Sound): boolean
	return sound:IsDescendantOf(workspace)
		and not (LocalPlayer.Character and sound:IsDescendantOf(LocalPlayer.Character))
end
local function apply(sound: Sound, record: any)
	if record.Applying then return end
	record.Applying = true
	local base = sound:GetAttribute("Volume")
	if type(base) ~= "number" or base ~= base then base = record.Base end
	sound.Volume = math.clamp(base, 0, 10) * Module.GetMediaVolume() * (if isOther(sound) then multiplier else 1)
	record.EQ.Enabled = Module.ClearDialogue()
	record.Applying = false
end
local function untrack(sound: Sound)
	local record = tracked[sound]
	if not record then return end
	tracked[sound] = nil
	for _, connection in record.Connections do connection:Disconnect() end
	if sound.Parent then
		local base = sound:GetAttribute("Volume")
		sound.Volume = if type(base) == "number" then base else record.Base
	end
	record.EQ:Destroy()
end
local function track(instance: Instance)
	if not instance:IsA("Sound") or tracked[instance] then return end
	local sound = instance :: Sound
	local eq = Instance.new("EqualizerSoundEffect")
	eq.Name = "MediaDialogue"
	eq.LowGain = -4; eq.MidGain = 2; eq.HighGain = -1
	eq.Enabled = false; eq.Parent = sound
	local record = {Base = sound.Volume, Applying = false, EQ = eq, Connections = {}}
	tracked[sound] = record
	table.insert(record.Connections, sound:GetAttributeChangedSignal("Volume"):Connect(function() apply(sound, record) end))
	table.insert(record.Connections, sound:GetPropertyChangedSignal("Volume"):Connect(function() apply(sound, record) end))
	table.insert(record.Connections, sound.AncestryChanged:Connect(function() apply(sound, record) end))
	table.insert(record.Connections, sound.Destroying:Connect(function() untrack(sound) end))
	apply(sound, record)
end
local function refresh()
	for sound, record in tracked do apply(sound, record) end
end
setmetatable(Module, {__call = function(_, value: number, cleanup: boolean?)
	if cleanup then Module.Destroy(); return end
	multiplier = bounded(value, 1); refresh()
end})
function Module.Init(_dependencies: any) end
function Module.Start()
	if #connections > 0 then return end
	multiplier = bounded(Settings.Get("OtherPlayersVolume"), 1)
	for _, sound in CollectionService:GetTagged("EmoteSound") do track(sound) end
	table.insert(connections, CollectionService:GetInstanceAddedSignal("EmoteSound"):Connect(track))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal("EmoteSound"):Connect(untrack))
	table.insert(connections, Settings.Changed:Connect(function(key, value)
		-- EmoteController owns the effective other-player gain, including temporary ducking.
		if key == "MediaVolume" or key == "MediaClearDialogue" then refresh() end
	end))
end
function Module.Destroy()
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	local sounds = {}; for sound in tracked do table.insert(sounds, sound) end
	for _, sound in sounds do untrack(sound) end
end
return Module
