--!strict
-- Implements PlayerRGB through explicit effect dependencies.
return function(context: any)
local WHITE=context.WHITE
local addFx=context.addFx
local handlers=context.handlers
local rig=context.rig
local scope=context.scope
local vfxHidden=context.vfxHidden
local vfxParent=context.vfxParent
return function(session, cue)
	if vfxHidden() then return end
	local character = session.Character
	if not character then return end

	if session.rim then session.rim:Destroy() session.rim = nil end
	local mode = cue.Mode or "Off"
	if mode == "Off" then return end

	local highlight = Instance.new("Highlight")
	highlight.Adornee = character
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0.7
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = vfxParent()
	session.rim = highlight

	local colors = cue.Colors or { cue.Color or WHITE }
	local index, lastTick = 1, session.beatTick
	local t0, duration = os.clock(), cue.Duration

	addFx(session, {
		update = function()
			if not highlight.Parent or (duration and os.clock() - t0 > duration) then return false end
			if mode == "Rainbow" then
				highlight.OutlineColor = Color3.fromHSV((os.clock() * (cue.Speed or 0.5) * 0.2) % 1, 0.7, 1)
			else
				if session.beatTick ~= lastTick then
					lastTick = session.beatTick
					index = index % #colors + 1
				end
				highlight.OutlineColor = colors[index]
			end
			local pulse = math.min(rig.pulse, 1)
			highlight.OutlineTransparency = 0.7 - 0.6 * pulse
			highlight.FillTransparency = 1 - 0.18 * pulse
			return true
		end,
		destroy = function()
			highlight:Destroy()
			if session.rim == highlight then session.rim = nil end
		end,
	})
end

end
