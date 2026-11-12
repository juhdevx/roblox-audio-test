--!strict
-- Starts the emote through EmoteService.ForcePlay (server authority, no ownership check).
local EmoteService = require(game:GetService("ServerScriptService").Services.EmoteService)
return function(_context, targets: {Player}, name: string)
	local ok, failed = {}, {}
	for _, target in targets do
		table.insert(if EmoteService.ForcePlay(target, name) then ok else failed, target.Name)
	end
	local text = if #ok > 0 then "Tocando '" .. name .. "' em: " .. table.concat(ok, ", ") else "Ninguém pôde tocar '" .. name .. "'."
	if #failed > 0 then text ..= "\nFalhou (sem personagem vivo?): " .. table.concat(failed, ", ") end
	return text
end
