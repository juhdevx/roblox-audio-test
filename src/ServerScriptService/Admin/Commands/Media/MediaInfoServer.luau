--!strict
-- Combines the public video manifest with the spectral audio catalog for one entry.
local ServerScriptService = game:GetService("ServerScriptService")
local Registry = require(game:GetService("ReplicatedStorage").Shared.Registries.EmoteRegistry)
local Videos = require(ServerScriptService.VideoSequence.VideoCatalog)
return function(_context, name: string)
	local entry = Registry.Get(name)
	local song = entry.Song
	local track = Videos.Manifest[song.Video]
	if not track then return "Faixa de vídeo '" .. tostring(song.Video) .. "' não existe no servidor." end
	local lines = {
		string.format("%s (ordem %d)%s", name, entry.Order, if entry.Exclusive then " · exclusivo" else ""),
		string.format("Vídeo: %dx%d · %d FPS · %d quadros · %.1f s · RVF%d · %d partes de %d quadros", track.Width, track.Height, track.FPS, track.Frames, track.Frames / track.FPS, track.Encoding, track.Segments, track.SegmentFrames),
		string.format("Áudio: %s · faixa %s · volume %.2f · velocidade %.2f", tostring(song.Backend), tostring(song.Track), song.Volume or 1, song.PlaybackSpeed or 1),
	}
	local ok, audio = pcall(function() return require(ServerScriptService.AudioSequence.SpectralTracks)[song.Track] end)
	if ok and type(audio) == "table" then
		table.insert(lines, string.format("Espectral: %d vozes · %d FPS · %d bandas de ruído · %d partes", audio.Voices or 0, audio.FPS or 0, audio.NoiseBands or 0, audio.Segments or 0))
	end
	table.insert(lines, "Modelo: " .. tostring(entry.Loop) .. (if entry.DisableEmoteCamera then " · câmera de emote desligada" else ""))
	return table.concat(lines, "\n")
end
