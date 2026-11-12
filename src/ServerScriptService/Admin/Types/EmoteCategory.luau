--!strict
-- Cmdr type "emoteCategory": all, default, exclusive, video, special, gamepass, syncable, traversal.
local Registry = require(game:GetService("ReplicatedStorage").Shared.Registries.EmoteRegistry)
return function(registry)
	registry:RegisterType("emoteCategory", {
		DisplayName = "Categoria",
		Transform = function(text) return string.lower(text or "") end,
		Validate = function(text)
			if table.find(Registry.Categories(), text) then return true end
			return false, "Categoria desconhecida. Use: " .. table.concat(Registry.Categories(), ", ")
		end,
		Autocomplete = function() return Registry.Categories() end,
		Parse = function(text) return text end,
		Default = function() return "exclusive" end,
	})
end
