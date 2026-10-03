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
local Assets = require(child(child(ReplicatedStorage, "Common"), "Assets"))

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

-- The sky: one placed in Lighting in Studio wins, then a custom one from
-- KartAssets.Sky, else Roblox's default sky with a bigger sun and stars.
local function ensureSky()
	if Lighting:FindFirstChildOfClass("Sky") then
		return
	end
	local sky = Assets.sky()
	if not sky then
		local made = Instance.new("Sky")
		made.SunAngularSize = 14
		made.MoonAngularSize = 10
		made.StarCount = 3000
		sky = made
	end
	local s = sky :: Sky
	s.Name = "KartSky"
	s.Parent = Lighting
end

-- Sky, sun and colour grading for a theme. `seconds` = fade time (0 = snap).
function Atmos.applyTheme(theme: any, seconds: number?)
	ensureSky()
	local fade = seconds or Atmos.FadeSeconds
	-- The sun can't sweep across the sky in a second without looking odd, so
	-- the time of day changes at once; everything else fades.
	Lighting.ClockTime = theme.clock
	Lighting.GlobalShadows = true
	-- Realistic themes let the sky light and reflect everything (PBR), with
	-- softer shadow edges; toy worlds keep flatter, cartoon lighting.
	Lighting.EnvironmentDiffuseScale = if theme.realistic then 1 else 0.5
	Lighting.EnvironmentSpecularScale = if theme.realistic then 1 else 0.5
	Lighting.ShadowSoftness = if theme.realistic then 0.15 else 0.2
	-- Roblox's realistic lighting style for the realistic themes (stronger
	-- sky light and shading); the toy worlds keep the softer style.
	pcall(function()
		(Lighting :: any).LightingStyle = if theme.realistic then Enum.LightingStyle.Realistic else Enum.LightingStyle.Soft
	end)
	-- ColorShift_Top tints sunlit surfaces (warm afternoons, cool mornings),
	-- like light bouncing off the sky and ground.
	tween(Lighting, fade, {
		Brightness = theme.brightness,
		Ambient = rgb(theme.ambient),
		OutdoorAmbient = rgb(theme.ambient),
		ColorShift_Top = rgb(theme.colorShiftTop or { 0, 0, 0 }),
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
	grade.Contrast = theme.contrast or 0.08
	tween(grade, fade, { TintColor = rgb(theme.tint), Saturation = theme.saturation })

	-- Volumetric clouds for outdoor themes (they live under Terrain).
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local clouds = terrain:FindFirstChild("KartClouds") :: Clouds?
		if not clouds then
			local made = Instance.new("Clouds")
			made.Name = "KartClouds"
			made.Cover = 0
			made.Density = 0
			made.Parent = terrain
			clouds = made
		end
		local cloud = clouds :: Clouds
		local c = theme.clouds
		cloud.Enabled = c ~= nil
		if c then
			tween(cloud, fade, { Cover = c.cover, Density = c.density })
		end
	end

	local rays = effect("SunRaysEffect", "KartSunRays") :: SunRaysEffect
	rays.Spread = 0.6
	tween(rays, fade, { Intensity = if theme.clock > 6 and theme.clock < 19 then 0.08 else 0 })
end

function Atmos.apply(themeId: string, seconds: number?)
	local theme = Tracks.Themes[themeId] or Tracks.Themes.hq
	Atmos.applyTheme(theme, seconds)
end

return Atmos
