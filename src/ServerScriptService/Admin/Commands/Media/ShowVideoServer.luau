--!strict
-- Force-plays the video emote; VideoWorldService then replaces the avatar with the replicated screen.
local ServerScriptService = game:GetService("ServerScriptService")
local EmoteService = require(ServerScriptService.Services.EmoteService)
local Catalog = require(ServerScriptService.VideoSequence.VideoCatalog)
local Registry = require(game:GetService("ReplicatedStorage").Shared.Registries.EmoteRegistry)
local Notify = require(ServerScriptService.Admin.Modules.Notify)
return function(_context, targets: {Player}, name: string)
	local entry = Registry.Get(name)
	local track = entry and entry.Song and Catalog.Manifest[entry.Song.Video]
	if not track then return "Vídeo '" .. tostring(name) .. "' não está no catálogo do servidor." end
	local ok, failed = {}, {}
	for _, target in targets do
		if EmoteService.ForcePlay(target, name) then
			table.insert(ok, target.Name)
			Notify.send(target, "Exibindo vídeo: " .. (track.Title or name), "info")
		else table.insert(failed, target.Name) end
	end
	local info = string.format("%s · %dx%d · %d FPS · %.0f s", track.Title or name, track.Width, track.Height, track.FPS, track.Frames / track.FPS)
	local text = if #ok > 0 then "Mostrando " .. info .. "\nEm: " .. table.concat(ok, ", ") else "Ninguém pôde exibir " .. info
	if #failed > 0 then text ..= "\nFalhou (sem personagem vivo?): " .. table.concat(failed, ", ") end
	return text
end
