--!strict
-- Cmdr type "rankName": user, moderator or staff (parsed to the numeric tier).
local RANKS = {user = 0, moderator = 1, staff = 2}
return function(registry)
	registry:RegisterType("rankName", {
		DisplayName = "Cargo",
		Transform = function(text) return string.lower(text or "") end,
		Validate = function(text)
			if RANKS[text] then return true end
			return false, "Cargo inválido. Use: user, moderator ou staff."
		end,
		Autocomplete = function() return {"moderator", "staff", "user"} end,
		Parse = function(text) return RANKS[text] end,
	})
end
