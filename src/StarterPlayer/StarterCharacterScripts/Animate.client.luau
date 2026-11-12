--!strict
-- Boots animation behavior for this character using the existing animation children.
local playerScripts = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts",10)
assert(playerScripts,"PlayerScripts missing")
local runtime = require(playerScripts:WaitForChild("Character",10).CharacterAnimator).Start(script.Parent,script)
script.Destroying:Once(function() runtime:Destroy() end)
