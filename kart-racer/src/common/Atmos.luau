-- Lighting for a track theme (sky haze, sun, bloom, colour grading). Runs on
-- each client: racers see the track's theme while lobby players keep the
-- Kart HQ look, since Lighting changes made on a client stay on that client.
-- Changes ease in over a second or so instead of snapping.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local function child(parent: Instance, name: string): Instance
	return parent:FindFirstChild(name) or parent:WaitForChild(name)
end
local Tracks = require(child(child(ReplicatedStorage, "Shared"), "Tracks"))

local Atmos = {}

Atmos.FadeSeconds = 1.2

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The effect objects are made once and then tweened between themes.
local function effect(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local e = Instance.new(className)
	e.Name = name
	e.Parent = Lighting
	return e
end

local function tween(inst: Instance, seconds: number, goals: { [string]: any })
	if seconds <= 0 then
		for k, v in goals do
			(inst :: any)[k] = v
		end
		return
	end
	TweenService:Create(inst, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goals):Play()
end

-- Sky, sun and colour grading for a theme. `seconds` = fade time (0 = snap).
function Atmos.applyTheme(theme: any, seconds: number?)
	local fade = seconds or Atmos.FadeSeconds
	-- The sun can't sweep across the sky in a second without looking odd, so
	-- the time of day changes at once; everything else fades.
	Lighting.ClockTime = theme.clock
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.5
	tween(Lighting, fade, {
		Brightness = theme.brightness,
		Ambient = rgb(theme.ambient),
		OutdoorAmbient = rgb(theme.ambient),
	})

	local a = theme.atmosphere
	tween(effect("Atmosphere", "KartAtmosphere"), fade, {
		Density = a.density,
		Haze = a.haze,
		Glare = a.glare,
		Color = rgb(a.color),
		Decay = rgb(a.decay),
	})

	local bloom = effect("BloomEffect", "KartBloom") :: BloomEffect
	bloom.Size = 24
	bloom.Threshold = 0.9
	tween(bloom, fade, { Intensity = theme.bloom })

	local grade = effect("ColorCorrectionEffect", "KartGrade") :: ColorCorrectionEffect
	grade.Contrast = 0.08
	tween(grade, fade, { TintColor = rgb(theme.tint), Saturation = theme.saturation })

	local rays = effect("SunRaysEffect", "KartSunRays") :: SunRaysEffect
	rays.Spread = 0.6
	tween(rays, fade, { Intensity = if theme.clock > 6 and theme.clock < 19 then 0.08 else 0 })
end

function Atmos.apply(themeId: string, seconds: number?)
	local theme = Tracks.Themes[themeId] or Tracks.Themes.hq
	Atmos.applyTheme(theme, seconds)
end

return Atmos
