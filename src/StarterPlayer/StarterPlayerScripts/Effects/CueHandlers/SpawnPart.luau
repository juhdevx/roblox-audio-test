--!strict
-- Implements SpawnPart through explicit effect dependencies.
return function(context: any)
local WHITE=context.WHITE
local beatHit=context.beatHit
local explodeAt=context.explodeAt
local fadeParts=context.fadeParts
local getRoot=context.getRoot
local getScale=context.getScale
local handlers=context.handlers
local newPart=context.newPart
local rigKick=context.rigKick
local scope=context.scope
local spawnDome=context.spawnDome
local spawnMeteor=context.spawnMeteor
local spawnRing=context.spawnRing
local vfxHidden=context.vfxHidden
return function(session, cue)
	if vfxHidden() then return end
	local root = getRoot(session)
	if not root then return end

	local scale = getScale(session.Character)
	local kind = cue.Kind
	local color = cue.Color or WHITE
	local radius = cue.Radius or 30
	local duration = cue.Duration or 1.5
	local feet = root.Position - Vector3.new(0, 3 * scale, 0)

	if kind == "Ring" or kind == "Shockwave" then
		spawnDome(feet, color, radius * scale * 0.7, duration)
		spawnRing(feet, color, radius * scale, duration)
		rigKick(kind == "Shockwave" and 8 or 4, 0, kind == "Shockwave" and 0.5 or 0.2, 5)
		beatHit(kind == "Shockwave" and 1.2 or 0.6)
	elseif kind == "Explosion" then
		explodeAt(session, root.Position, color, radius * scale)
	elseif kind == "Meteor" then
		spawnMeteor(session, cue)
	elseif kind == "Stars" or kind == "Planets" then
		local parts = {}
		local isStars = kind == "Stars"
		for _ = 1, isStars and 40 or 6 do
			local size = (isStars and 0.5 or math.random(6, 22)) * scale
			local part = newPart(Vector3.one * size, isStars and color or Color3.fromHSV(math.random(), 0.5, 1), 1)
			part.Shape = Enum.PartType.Ball
			if not isStars then part.Material = Enum.Material.SmoothPlastic end
			local offset = Vector3.new(math.random(-100, 100), math.random(-40, 100), math.random(-100, 100)).Unit * radius * (0.5 + math.random() * 0.5)
			part.Position = root.Position + offset
			table.insert(parts, part)
		end
		fadeParts(session, parts, duration, isStars and 0.1 or 0.35)
	end
end


end
