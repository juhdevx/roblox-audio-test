--!strict
-- Selects an effect audience consistently for Self, Near, and All scopes.
local Players = game:GetService("Players")
return function(player: Player, character: Model, params: any): {Player}
    if params.Scope == "Self" then return {player} end
    if params.Scope ~= "Near" then return Players:GetPlayers() end
    local root = character:FindFirstChild("HumanoidRootPart")
    local result = {}
    for _, other in Players:GetPlayers() do
        local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
        if other == player or (root and otherRoot and root:IsA("BasePart") and otherRoot:IsA("BasePart") and (root.Position-otherRoot.Position).Magnitude <= (params.NearRadius or 120)) then
            table.insert(result, other)
        end
    end
    return result
end
