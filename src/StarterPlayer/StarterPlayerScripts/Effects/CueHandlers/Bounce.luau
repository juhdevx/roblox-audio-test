--!strict
-- Implements Bounce through explicit effect dependencies.
return function(context: any)
local ClientState=context.ClientState
local LocalPlayer=context.LocalPlayer
local addFx=context.addFx
local handlers=context.handlers
local scope=context.scope
return function(session, cue)
	local height = cue.Height or 5
	local accentHeight = cue.AccentHeight or 11
	local duration = cue.Duration or 30

	local function hook(char)
		if char ~= "K" and char ~= "X" then return end
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or humanoid.Health <= 0 or humanoid.Sit or ClientState.Get("emoting") then return end
		if humanoid.FloorMaterial == Enum.Material.Air then return end

		local speed = math.sqrt(2 * workspace.Gravity * (char == "X" and accentHeight or height))
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, speed, velocity.Z)
	end

	table.insert(session.Hooks, hook)
	local t0 = os.clock()
	addFx(session, {
		update = function() return os.clock() - t0 < duration end,
		destroy = function()
			local index = table.find(session.Hooks, hook)
			if index then table.remove(session.Hooks, index) end
		end,
	})
end

end
