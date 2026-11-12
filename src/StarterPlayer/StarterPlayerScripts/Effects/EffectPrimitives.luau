--!strict
-- Implements EffectPrimitives through explicit effect dependencies.
return function(context: any)
local AttachmentController=context.AttachmentController
local Debris=context.Debris
local FIRE_TEXTURE=context.FIRE_TEXTURE
local SPARK_TEXTURE=context.SPARK_TEXTURE
local TweenService=context.TweenService
local WHITE=context.WHITE
local addFx=context.addFx
local beatHit=context.beatHit
local getScale=context.getScale
local handlers=context.handlers
local rigKick=context.rigKick
local scope=context.scope
local vfxParent=context.vfxParent
local visualState=context.visualState
local function newPart(size, color, transparency, material)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = material or Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.Transparency = transparency or 0
	part.Parent = vfxParent()
	return part
end

local function anchorPart(position: Vector3): Part
	local part = newPart(Vector3.one * 0.2, WHITE, 1)
	part.Position = position
	return part
end

local function anchorToRig(session: any, pointName: string, options: any?): Attachment?
	options = options or {}
	local character = session.Character
	if not character then return nil end
	return AttachmentController.CreateEffectAttachment(character, pointName, {
		sessionId = session.Id,
		offset = options.offset,
		orientation = options.orientation,
		allowEquivalent = options.allowEquivalent,
	})
end

local function newAttachment(part, position)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	if position then attachment.WorldPosition = position end
	return attachment
end

local function newBeam(parent, a0, a1, color, width0, width1, transparency)
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Color = ColorSequence.new(color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0, beam.Width1 = width0, width1
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Transparency = NumberSequence.new(transparency)
	beam.Parent = parent
	return beam
end

local function spawnRing(position, color, radius, duration, thickness)
	local ring = newPart(Vector3.new(thickness or 0.2, 1, 1), color, 0.3)
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	scope:Tween(ring, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, radius, radius),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, duration + 0.2)
end

local function spawnDome(position, color, radius, duration)
	local dome = newPart(Vector3.one, color, 0.35, Enum.Material.ForceField)
	dome.Shape = Enum.PartType.Ball
	dome.Position = position
	scope:Tween(dome, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(dome, duration + 0.2)
end

local function emitBurst(parent, color, count, speed, lifetime, size, texture)
	local emitter = Instance.new("ParticleEmitter")
	if texture then emitter.Texture = texture end
	emitter.Color = ColorSequence.new(color, color:Lerp(Color3.new(0, 0, 0), 0.5))
	emitter.LightEmission = 0.8
	emitter.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 1.5) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Rate = 0
	emitter.Parent = parent
	emitter:Emit(count)
	Debris:AddItem(emitter, lifetime + 0.3)
end

local function explodeAt(session, position, color, radius)
	local scale = getScale(session.Character)
	spawnDome(position, color, radius, 1.1)
	spawnRing(position, color, radius * 1.2, 1.0, 0.3)
	local anchor = anchorPart(position)
	emitBurst(anchor, color, 120, radius * 0.5, 1.6, 6 * scale, FIRE_TEXTURE)
	emitBurst(anchor, WHITE, 40, radius * 0.8, 1.0, 1.6 * scale, SPARK_TEXTURE)
	Debris:AddItem(anchor, 3)
	handlers.Flash(session, { Color = color:Lerp(WHITE, 0.5), Intensity = 0.9, Duration = 0.7 })
	rigKick(10, 2, 0.8, 4)
	beatHit(1.3)
end

local ghostOriginal = {}
local function setGhost(character, value)
	if not character then return end
	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart") then
			object.LocalTransparencyModifier = value
		elseif object:IsA("Decal") then
			ghostOriginal[object] = ghostOriginal[object] or object.Transparency
			local original = ghostOriginal[object]
			object.Transparency = original + (1 - original) * value
		end
	end
	if value == 0 then table.clear(ghostOriginal) end
end

local function fadeParts(session, parts, duration, targetTransparency)
	local t0 = os.clock()
	addFx(session, {
		update = function()
			local t = os.clock() - t0
			if t > duration + 1 then return false end
			local alpha = math.clamp(t / 0.6, 0, 1) * math.clamp((duration + 1 - t) / 1, 0, 1)
			for _, part in ipairs(parts) do
				part.Transparency = 1 - (1 - (targetTransparency or 0.2)) * alpha
			end
			return true
		end,
		destroy = function()
			for _, part in ipairs(parts) do part:Destroy() end
		end,
	})
end

local function clearLetterbox(duration)
	if not visualState.letterbox then return end
	local gui = visualState.letterbox
	visualState.letterbox = nil
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for _, name in ipairs({ "Top", "Bottom" }) do
		local frame = gui:FindFirstChild(name)
		if frame then scope:Tween(frame, info, { Size = UDim2.fromScale(1, 0) }):Play() end
	end
	scope:Delay(duration + 0.1, function() gui:Destroy() end)
end

-- ════════════════════════════════════════════════════════════
-- HANDLERS
-- ════════════════════════════════════════════════════════════


return {newPart=newPart,anchorPart=anchorPart,anchorToRig=anchorToRig,newAttachment=newAttachment,newBeam=newBeam,spawnRing=spawnRing,spawnDome=spawnDome,emitBurst=emitBurst,explodeAt=explodeAt,setGhost=setGhost,fadeParts=fadeParts,clearLetterbox=clearLetterbox}
end
