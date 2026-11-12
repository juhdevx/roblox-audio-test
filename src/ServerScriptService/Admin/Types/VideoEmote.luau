--!strict
-- Cmdr type "videoEmote": only emotes that carry a video track (case-insensitive, autocomplete).
local Registry = require(game:GetService("ReplicatedStorage").Shared.Registries.EmoteRegistry)
return function(registry)
	registry:RegisterType("videoEmote", {
		DisplayName = "Vídeo",
		Transform = function(text) return Registry.ResolveName(text or "") or (text or "") end,
		Validate = function(name)
			local entry = Registry.Get(name)
			if entry and entry.Video then return true end
			return false, "Não é um emote de vídeo. Use `videos` para listar."
		end,
		Autocomplete = function() return Registry.ByCategory("video") end,
		Parse = function(name) return name end,
	})
end
