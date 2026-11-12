--!strict
-- Reads the video catalog manifest and the inventory of the optional target.
local ServerScriptService = game:GetService("ServerScriptService")
local Registry = require(game:GetService("ReplicatedStorage").Shared.Registries.EmoteRegistry)
local Catalog = require(ServerScriptService.VideoSequence.VideoCatalog)
local Inventory = require(ServerScriptService.Services.EmoteInventoryService)
return function(_context, target: Player?)
	local lines = {}
	for _, name in Registry.ByCategory("video") do
		local entry = Registry.Get(name)
		local track = Catalog.Manifest[entry.Song.Video]
		local detail = if track then string.format("%dx%d · %d FPS · %.0f s · %d partes", track.Width, track.Height, track.FPS, track.Frames / track.FPS, track.Segments) else "(sem faixa no servidor)"
		local owned = if target then (if Inventory.Owns(target, name) then " · ✔ tem" else " · ✖ não tem") else ""
		table.insert(lines, string.format("%s — %s%s%s", name, detail, if entry.Exclusive then " · exclusivo" else "", owned))
	end
	if #lines == 0 then return "Nenhum emote de vídeo registrado." end
	table.insert(lines, 1, string.format("%d vídeo(s)%s:", #lines, if target then " · " .. target.Name else ""))
	return table.concat(lines, "\n")
end
