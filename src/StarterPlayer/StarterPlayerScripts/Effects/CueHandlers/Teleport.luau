--!strict
-- Implements Teleport through explicit effect dependencies.
return function(context: any)
local SPARK_TEXTURE=context.SPARK_TEXTURE
local addFx=context.addFx
local beatHit=context.beatHit
local emitBurst=context.emitBurst
local getRoot=context.getRoot
local getScale=context.getScale
local handlers=context.handlers
local rigKick=context.rigKick
local scope=context.scope
local setGhost=context.setGhost
local spawnDome=context.spawnDome
local vfxHidden=context.vfxHidden
return function(session, cue)
	if vfxHidden() then return end
	local character, root = session.Character, getRoot(session)
	if not root then return end

	local color = cue.Color or Color3.fromRGB(170, 130, 240)
	local scale = getScale(character)
	local hold = cue.Hold or 0.3
	local t0 = os.clock()
	local arrived = false

	spawnDome(root.Position - Vector3.new(0, 3 * scale, 0), color, 12 * scale, 0.5)
	emitBurst(root, color, 80, 22, 0.7, 0.9 * scale, SPARK_TEXTURE)
	rigKick(6, 3, 0.35, 8)
	beatHit(0.9)

	addFx(session, {
		update = function()
			if not root.Parent then return false end
			local t = os.clock() - t0
			if t < 0.24 then
				setGhost(character, (math.floor(t / 0.04) % 2 == 0) and 0.35 or 0.85)
			elseif t < 0.24 + hold then
				setGhost(character, 1)
			else
				if not arrived then
					arrived = true
					spawnDome(root.Position - Vector3.new(0, 3 * scale, 0), color, 16 * scale, 0.6)
					emitBurst(root, color, 60, 28, 0.7, 0.8 * scale, SPARK_TEXTURE)
					rigKick(8, -3, 0.5, 7)
				end
				local k = (t - 0.24 - hold) / 0.4
				setGhost(character, math.clamp(1 - k, 0, 1))
				if k >= 1 then return false end
			end
			return true
		end,
		destroy = function() setGhost(character, 0) end,
	})
end

end
