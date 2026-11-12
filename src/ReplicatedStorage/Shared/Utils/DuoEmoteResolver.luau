--!strict
-- Provides the existing DuoEmoteResolver behavior.
local Players = game:GetService("Players")

local DuoEmoteResolver = {}

local lastLoopByPlayer = {}

function DuoEmoteResolver.ResolveSoloLoop(player, emoteData)
	local last = lastLoopByPlayer[player]
	local useLoop2 = (last == 1)
	lastLoopByPlayer[player] = useLoop2 and 2 or 1
	return useLoop2 and emoteData.Loop2 or emoteData.Loop1
end

function DuoEmoteResolver.GetOppositeLoop(currentLoop, emoteData)
	if currentLoop == emoteData.Loop1 then
		return emoteData.Loop2
	end
	return emoteData.Loop1
end

Players.PlayerRemoving:Connect(function(player)
	lastLoopByPlayer[player] = nil
end)

return DuoEmoteResolver
