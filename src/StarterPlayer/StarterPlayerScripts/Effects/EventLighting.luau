--!strict
-- Implements EventLighting through explicit effect dependencies.
return function(context: any)
local Lighting=context.Lighting
local TweenService=context.TweenService
local WHITE=context.WHITE
local scope=context.scope
local snapshots={}
local created={}
local function isTweenable(value)
	local kind = typeof(value)
	return kind == "number" or kind == "Color3"
end

local NEUTRAL = {
	ColorCorrectionEffect = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE },
	BloomEffect = { Intensity = 0, Size = 24, Threshold = 2 },
	BlurEffect = { Size = 0 },
	SunRaysEffect = { Intensity = 0, Spread = 1 },
}

local function applyProps(instance, props, duration)
	if not instance or type(props) ~= "table" then return end
	snapshots[instance] = snapshots[instance] or {}
	local tweenable = {}
	for key, value in pairs(props) do
		local ok, current = pcall(function() return instance[key] end)
		if ok then
			if snapshots[instance][key] == nil then snapshots[instance][key] = current end
			if duration > 0 and isTweenable(value) then
				tweenable[key] = value
			else
				pcall(function() instance[key] = value end)
			end
		end
	end
	if next(tweenable) then
		scope:Tween(instance, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), tweenable):Play()
	end
end

local function getEffect(name, className)
	local existing = created[name]
	if existing and existing.Parent then return existing end
	local effect = Instance.new(className)
	effect.Name = name
	for key, value in pairs(NEUTRAL[className]) do effect[key] = value end
	effect.Parent = Lighting
	created[name] = effect
	snapshots[effect] = table.clone(NEUTRAL[className])
	return effect
end

local function getAtmosphere()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		if not snapshots[atmosphere] then
			snapshots[atmosphere] = {
				Density = atmosphere.Density, Offset = atmosphere.Offset, Color = atmosphere.Color,
				Decay = atmosphere.Decay, Glare = atmosphere.Glare, Haze = atmosphere.Haze,
			}
		end
		return atmosphere
	end
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "EventAtmosphere"
	atmosphere.Density, atmosphere.Offset, atmosphere.Glare, atmosphere.Haze = 0, 0, 0, 0
	atmosphere.Parent = Lighting
	created.EventAtmosphere = atmosphere
	snapshots[atmosphere] = { Density = 0, Offset = 0, Glare = 0, Haze = 0, Color = atmosphere.Color, Decay = atmosphere.Decay }
	return atmosphere
end

local function getSky()
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		if not snapshots[sky] then
			local snap = {}
			for _, key in ipairs({
				"SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp",
				"StarCount", "SunAngularSize", "MoonAngularSize", "CelestialBodiesShown",
				}) do snap[key] = sky[key] end
			snapshots[sky] = snap
		end
		return sky
	end
	sky = Instance.new("Sky")
	sky.Name = "EventSky"
	sky.Parent = Lighting
	created.EventSky = sky
	snapshots[sky] = {}
	return sky
end

local function applyLook(look, duration)
	if type(look) ~= "table" then return end
	applyProps(Lighting, look.Lighting, duration)
	if look.Atmosphere then applyProps(getAtmosphere(), look.Atmosphere, duration) end
	if look.Sky then applyProps(getSky(), look.Sky, 0) end
	if look.ColorCorrection then applyProps(getEffect("EventColor", "ColorCorrectionEffect"), look.ColorCorrection, duration) end
	if look.Bloom then applyProps(getEffect("EventBloom", "BloomEffect"), look.Bloom, duration) end
	applyProps(getEffect("EventBlur", "BlurEffect"), look.Blur or NEUTRAL.BlurEffect, duration)
	applyProps(getEffect("EventSunRays", "SunRaysEffect"), look.SunRays or NEUTRAL.SunRaysEffect, duration)
end

local function restoreAll(duration)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for instance, props in pairs(snapshots) do
		if instance.Parent then
			local tweenable = {}
			for key, value in pairs(props) do
				if duration > 0 and isTweenable(value) then
					tweenable[key] = value
				else
					pcall(function() instance[key] = value end)
				end
			end
			if next(tweenable) then scope:Tween(instance, info, tweenable):Play() end
		end
	end
	table.clear(snapshots)
	local toDestroy = created
	created = {}
	if duration <= 0 then
        for _,instance in pairs(toDestroy) do instance:Destroy() end
    else
        scope:Delay(duration+0.15,function() for _,instance in pairs(toDestroy) do instance:Destroy() end end)
    end
end


return {applyLook=applyLook,restoreAll=restoreAll,getEffect=getEffect,getAtmosphere=getAtmosphere,getSky=getSky,applyProps=applyProps}
end
