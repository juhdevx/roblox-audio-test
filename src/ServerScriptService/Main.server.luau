--!strict
-- Initializes dependencies before starting the project's server services.
local folder = script.Parent.Services
local names = {"RemoteService", "PlayerDataService", "EmoteInventoryService", "SettingsService", "EmoteSyncService", "EmoteService", "EmoteEffectsService", "CollisionService", "LookReplicationService", "CharacterService", "AdminService", "AudioSequenceService", "SpectralAudioService", "VideoSequenceService", "VideoWorldService"}
local services = {}
for _, name in names do services[name] = require(folder:WaitForChild(name, 10)) end
for _, name in names do services[name].Init(services) end
for _, name in names do services[name].Start() end
script.Destroying:Once(function()
	services.VideoWorldService.Destroy()
	services.VideoSequenceService.Destroy()
    services.SpectralAudioService.Destroy()
    services.AudioSequenceService.Destroy()
end)

