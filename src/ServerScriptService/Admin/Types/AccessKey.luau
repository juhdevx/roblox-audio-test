--!strict
-- Supplies registry-backed Cmdr autocomplete and validation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")


return function(registry)
	local function loadEmoteData()
        return require(ReplicatedStorage.Shared.Registries.EmoteRegistry).All()
    end

	local function collectKeys()
		local set = {}
		local data = loadEmoteData()
		if not data then return set end
		for _, emote in ipairs(data) do
			if emote.Exclusive then
				set[string.lower(emote.AccessKey or emote.Name)] = true
			end
		end
		return set
	end

	registry:RegisterType("accessKey", {
		DisplayName = "AccessKey",
		Transform = function(text) return string.lower(text or "") end,
		Validate = function(text)
			if text == "" then return false, "Empty access key." end
			local keys = collectKeys()
			if next(keys) == nil then return true end
			if not keys[text] then return false, "Unknown access key." end
			return true
		end,
		Autocomplete = function()
			local keys = collectKeys()
			local out = {}
			for key in pairs(keys) do table.insert(out, key) end
			table.sort(out)
			return out
		end,
		Parse = function(text) return text end,
	})
end
