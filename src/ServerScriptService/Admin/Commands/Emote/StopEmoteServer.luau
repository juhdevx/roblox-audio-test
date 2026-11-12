--!strict
-- Stops the active session of each target through EmoteService.
local EmoteService = require(game:GetService("ServerScriptService").Services.EmoteService)
return function(_context, targets: {Player})
	local stopped = {}
	for _, target in targets do
		if EmoteService.GetSession(target) then EmoteService.Stop(target); table.insert(stopped, target.Name) end
	end
	return if #stopped > 0 then "Parado: " .. table.concat(stopped, ", ") else "Ninguém estava tocando emote."
end
