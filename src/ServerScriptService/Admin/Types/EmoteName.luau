--!strict
-- Supplies registry-backed Cmdr autocomplete and validation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(registry)
	local function loadEmoteData()
        return require(ReplicatedStorage.Shared.Registries.EmoteRegistry).All()
    end

	local function names()
		local data = loadEmoteData()
		local out = {}
		if not data then return out end
		for _, emote in ipairs(data) do
			table.insert(out, emote.Name)
		end
		table.sort(out)
		return out
	end

	registry:RegisterType("emoteName", {
		DisplayName = "EmoteName",
		-- Case-insensitive: "larprooms" resolves to "Larprooms".
		Transform = function(text)
			local Registry = require(ReplicatedStorage.Shared.Registries.EmoteRegistry)
			return Registry.ResolveName(text or "") or (text or "")
		end,
		Validate = function(text)
			if text == "" then return false, "Nome de emote vazio." end
			local list = names()
			if #list == 0 then return true end
			if not table.find(list, text) then return false, "Emote desconhecido." end
			return true
		end,
		Autocomplete = function() return names() end,
		Parse = function(text) return text end,
	})
end
