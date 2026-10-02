-- Scenery models built from parts. Scenery.luau decides where they go; this
-- decides what they look like. Each builder gets the prop, the track theme
-- and a parent, and makes anchored, non-colliding decoration (grandstands
-- and towers collide so nobody drives through them).

local Props = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Varies a colour a little so rows of props don't look copy-pasted.
local function vary(c: Color3, amount: number, seed: number): Color3
	local h, s, v = c:ToHSV()
	local k = (math.sin(seed * 12.9898) * 43758.5453) % 1
	return Color3.fromHSV(h, s, math.clamp(v + (k - 0.5) * amount, 0, 1))
end

local builders: { [string]: (any, any, Instance) -> () } = {}

builders.tree = function(prop, _theme, parent)
	local s = prop.size
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	part(parent, Vector3.new(2, 14 * s, 2) , base * CFrame.new(0, 7 * s, 0), Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
	local leaf = vary(Color3.fromRGB(70, 150, 60), 0.25, prop.x + prop.z)
	part(parent, Vector3.one * 12 * s, base * CFrame.new(0, 16 * s, 0), leaf, Enum.Material.Grass, Enum.PartType.Ball)
	part(parent, Vector3.one * 8 * s, base * CFrame.new(3 * s, 13 * s, 1 * s), leaf, Enum.Material.Grass, Enum.PartType.Ball)
end

builders.bush = function(prop, _theme, parent)
	local s = prop.size
	part(parent, Vector3.new(7, 5, 7) * s, CFrame.new(prop.x, prop.y + 1.5 * s, prop.z), vary(Color3.fromRGB(80, 160, 70), 0.2, prop.z), Enum.Material.Grass, Enum.PartType.Ball)
end

builders.flag = function(prop, theme, parent)
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	part(parent, Vector3.new(0.4, 12, 0.4), base * CFrame.new(0, 6, 0), Color3.fromRGB(230, 230, 235), Enum.Material.Metal)
	local colors = { rgb(theme.accent), rgb(theme.curb[1]), rgb(theme.curb[2]) }
	part(parent, Vector3.new(0.1, 3, 5), base * CFrame.new(0, 10.5, 2.5), colors[(math.floor(prop.x) % 3) + 1], Enum.Material.Fabric)
end

builders.billboard = function(prop, theme, parent)
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	for _, side in { -9, 9 } do
		part(parent, Vector3.new(1, 14, 1), base * CFrame.new(side, 7, 0), Color3.fromRGB(80, 80, 90), Enum.Material.Metal)
	end
	local board = part(parent, Vector3.new(24, 9, 0.6), base * CFrame.new(0, 16, 0), Color3.fromRGB(20, 20, 30), Enum.Material.SmoothPlastic)
	local glow = theme.clock < 6 or theme.clock > 19
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = if glow then 0 else 1
	gui.Parent = board
	local slogans = { "GO FAST", "TURBO!", "DRIFT KING", "KART RACER", "FULL SPEED", "NO BRAKES" }
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = rgb(theme.accent)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(20, 20, 30)
	label.Text = slogans[(math.floor(prop.x + prop.z) % #slogans) + 1]
	label.Parent = gui
	-- Same text on the back.
	local back = gui:Clone()
	back.Face = Enum.NormalId.Back
	back.Parent = board
end

builders.grandstand = function(prop, theme, parent)
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	local steps = 5
	for i = 0, steps - 1 do
		local step = part(parent, Vector3.new(60, 2.5, 5), base * CFrame.new(0, 1.25 + i * 2.5, i * 4.5), Color3.fromRGB(150, 150, 160), Enum.Material.Concrete)
		step.CanCollide = true
		-- Crowd: little coloured blocks.
		for c = -27, 27, 3 do
			local seed = c * 7 + i * 13 + prop.x
			local h = (math.sin(seed) * 43758.5453) % 1
			part(parent, Vector3.new(1.4, 2, 1.2), base * CFrame.new(c, 3.5 + i * 2.5, i * 4.5 - 0.5), Color3.fromHSV(h, 0.6, 0.9), Enum.Material.SmoothPlastic)
		end
	end
	local roof = part(parent, Vector3.new(64, 1, 26), base * CFrame.new(0, 20, 9) * CFrame.Angles(math.rad(-8), 0, 0), rgb(theme.accent), Enum.Material.Metal)
	roof.CanCollide = true
	for _, x in { -30, 30 } do
		part(parent, Vector3.new(1.2, 20, 1.2), base * CFrame.new(x, 10, 20), Color3.fromRGB(90, 90, 100), Enum.Material.Metal)
	end
end

builders.rock = function(prop, theme, parent)
	local s = prop.size
	local color = vary(rgb(theme.wall), 0.2, prop.x)
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	part(parent, Vector3.new(10, 7, 8) * s, base * CFrame.new(0, 2.5 * s, 0) * CFrame.Angles(0.2, 0, 0.15), color, Enum.Material.Slate)
	part(parent, Vector3.new(6, 5, 6) * s, base * CFrame.new(3 * s, 4.5 * s, 1 * s) * CFrame.Angles(-0.3, 0.6, 0.2), color, Enum.Material.Slate)
end

builders.mesa = function(prop, theme, parent)
	local s = prop.size
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	local layers = { { 70, 18, 60 }, { 58, 16, 50 }, { 46, 14, 40 } }
	local y = 0
	for i, l in layers do
		local color = vary(rgb(theme.wall), 0.25, i + prop.x)
		local p = part(parent, Vector3.new(l[1], l[2], l[3]) * s, base * CFrame.new(0, (y + l[2] / 2) * s, 0), color, Enum.Material.Sandstone)
		p.CanCollide = true
		y += l[2]
	end
end

builders.cactus = function(prop, _theme, parent)
	local s = prop.size
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	local green = Color3.fromRGB(70, 130, 70)
	part(parent, Vector3.new(2, 12, 2) * s, base * CFrame.new(0, 6 * s, 0), green, Enum.Material.Grass)
	part(parent, Vector3.new(3, 1.4, 1.4) * s, base * CFrame.new(1.8 * s, 6 * s, 0), green, Enum.Material.Grass)
	part(parent, Vector3.new(1.4, 4, 1.4) * s, base * CFrame.new(2.8 * s, 8 * s, 0), green, Enum.Material.Grass)
end

builders.tower = function(prop, theme, parent)
	local s = prop.size
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	local h = 60 * s + (math.floor(prop.x * 7) % 5) * 20
	local w = 30 * math.min(s, 1.4)
	local tower = part(parent, Vector3.new(w, h, w), base * CFrame.new(0, h / 2, 0), Color3.fromRGB(22, 20, 36), Enum.Material.Glass)
	tower.CanCollide = true
	local colors = { rgb(theme.accent), rgb(theme.wall), Color3.fromRGB(255, 200, 60) }
	local color = colors[(math.floor(prop.z) % #colors) + 1]
	-- Glowing window bands.
	for y = 12, h - 6, 14 do
		part(parent, Vector3.new(w + 0.4, 1.2, w + 0.4), base * CFrame.new(0, y, 0), color, Enum.Material.Neon)
	end
	part(parent, Vector3.new(1, 10, 1), base * CFrame.new(0, h + 5, 0), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
end

builders.lamp = function(prop, theme, parent)
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	part(parent, Vector3.new(0.8, 16, 0.8), base * CFrame.new(0, 8, 0), Color3.fromRGB(60, 60, 80), Enum.Material.Metal)
	local head = part(parent, Vector3.new(1.2, 1.2, 6), base * CFrame.new(0, 16, 2.5), rgb(theme.wall), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = rgb(theme.wall)
	light.Range = 30
	light.Brightness = 2
	light.Parent = head
end

function Props.build(prop: any, theme: any, parent: Instance)
	local builder = builders[prop.kind]
	if builder then
		builder(prop, theme, parent)
	end
end

Props.Kinds = builders

return Props
