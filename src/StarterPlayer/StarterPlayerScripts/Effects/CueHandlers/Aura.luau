--!strict
-- Implements Aura through explicit effect dependencies.
return function(context: any)
local AttachmentController=context.AttachmentController
local addFx=context.addFx
local getRoot=context.getRoot
local getScale=context.getScale
local handlers=context.handlers
local rig=context.rig
local scope=context.scope
local vfxHidden=context.vfxHidden
return function(session, cue)
	if vfxHidden() then return end
	local character = session.Character
	if not character then return end

	local attachment = AttachmentController.GetAttachment(character, "Chest", {
		sessionId = session.Id,
		offset = cue.Offset or CFrame.new(0, 0, 0),
	})

	if not attachment then
		local root = getRoot(session)
		if not root then return end
		if session.aura and session.aura.Parent then session.aura:Destroy() end
		local light = Instance.new("PointLight")
		light.Color = cue.Color or Color3.fromRGB(255, 120, 60)
		light.Range = math.min((cue.Range or 40) * getScale(character), 60)
		light.Brightness = cue.Base or 2
		light.Shadows = false
		light.Parent = root
		session.aura = light
		addFx(session, {
			update = function()
				light.Brightness = (cue.Base or 2) + math.min(rig.pulse, 1.2) * ((cue.Peak or 8) - (cue.Base or 2))
				return root.Parent ~= nil
			end,
			destroy = function()
				light:Destroy()
				if session.aura == light then session.aura = nil end
			end,
		})
		return
	end

	if session.aura and session.aura.Parent then
		session.aura:Destroy()
	end

	local light = Instance.new("PointLight")
	light.Name = "AuraLight"
	light.Color = cue.Color or Color3.fromRGB(255, 120, 60)
	light.Range = math.min((cue.Range or 40) * getScale(character), 60)
	light.Brightness = cue.Base or 2
	light.Shadows = false
	light.Parent = attachment

	session.aura = light

	addFx(session, {
		update = function()
			if not light.Parent then return false end
			local pulse = math.min(rig.pulse, 1.2)
			local base = cue.Base or 2
			local peak = cue.Peak or 8
			light.Brightness = base + pulse * (peak - base)
			local scale = getScale(character)
			light.Range = math.min((cue.Range or 40) * scale, 60)
			return character.Parent ~= nil
		end,
		destroy = function()
			if light.Parent then light:Destroy() end
			if session.aura == light then session.aura = nil end
		end,
	})
end



end
