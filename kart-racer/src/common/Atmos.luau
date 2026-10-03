-- Lighting for a track theme (sky haze, sun, bloom, colour grading). Runs on
-- each client: racers see the track's theme while lobby players keep the
-- carnival look, since Lighting changes made on a client stay on that client.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function child(parent: Instance, name: string): Instance
	return parent:FindFirstChild(name) or parent:WaitForChild(name)
end
local Tracks = require(child(child(ReplicatedStorage, "Shared"), "Tracks"))

local Atmos = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Sky, sun and colour grading for a theme. Replaces the previous track's.
function Atmos.applyTheme(theme: any)
	for _, name in { "KartAtmosphere", "KartBloom", "KartGrade", "KartSunRays" } do
		local old = Lighting:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	Lighting.ClockTime = theme.clock
	Lighting.Brightness = theme.brightness
	Lighting.Ambient = rgb(theme.ambient)
	Lighting.OutdoorAmbient = rgb(theme.ambient)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.5

	local a = theme.atmosphere
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "KartAtmosphere"
	atmosphere.Density = a.density
	atmosphere.Haze = a.haze
	atmosphere.Glare = a.glare
	atmosphere.Color = rgb(a.color)
	atmosphere.Decay = rgb(a.decay)
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "KartBloom"
	bloom.Intensity = theme.bloom
	bloom.Size = 24
	bloom.Threshold = 0.9
	bloom.Parent = Lighting

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "KartGrade"
	grade.TintColor = rgb(theme.tint)
	grade.Saturation = theme.saturation
	grade.Contrast = 0.08
	grade.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Name = "KartSunRays"
	rays.Intensity = if theme.clock > 6 and theme.clock < 19 then 0.08 else 0
	rays.Spread = 0.6
	rays.Parent = Lighting
end

function Atmos.apply(themeId: string)
	local theme = Tracks.Themes[themeId] or Tracks.Themes.carnival
	Atmos.applyTheme(theme)
end

return Atmos
