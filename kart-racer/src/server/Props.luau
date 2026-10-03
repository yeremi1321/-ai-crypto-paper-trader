-- Scenery models built from parts. Scenery.luau decides where they go; this
-- decides what they look like. Each builder gets the prop, the track theme
-- and a parent, and makes anchored, non-colliding decoration (grandstands
-- and towers collide so nobody drives through them).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = require(ReplicatedStorage.Common.Assets)
local Shapes = require(ReplicatedStorage.Common.Shapes)

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

-- Realistic themes use textured materials (bark, leaves, rock, concrete);
-- the toy-world themes keep smooth plastic.
local function mat(theme: any, realistic: Enum.Material): Enum.Material
	return if theme.realistic then realistic else Enum.Material.SmoothPlastic
end

builders.tree = function(prop, theme, parent)
	local s = prop.size
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	local leafMaterial = mat(theme, Enum.Material.LeafyGrass)
	part(parent, Vector3.new(2, 14 * s, 2), base * CFrame.new(0, 7 * s, 0), Color3.fromRGB(96, 70, 48), mat(theme, Enum.Material.Wood))
	-- A couple of branches, then an uneven crown of overlapping leaf clumps.
	if theme.realistic then
		for k = 0, 1 do
			local a = k * math.pi + prop.yaw
			part(parent, Vector3.new(0.8, 6 * s, 0.8), base * CFrame.new(math.cos(a) * 1.6 * s, 11 * s, math.sin(a) * 1.6 * s) * CFrame.Angles(math.sin(a) * 0.6, 0, -math.cos(a) * 0.6), Color3.fromRGB(96, 70, 48), Enum.Material.Wood)
		end
	end
	-- A theme can list its own leaf colours (autumn reds and golds).
	local leaves = theme.leaves
	local tone = if leaves then rgb(leaves[math.floor(math.abs(prop.x * 7 + prop.z * 3)) % #leaves + 1]) elseif theme.realistic then Color3.fromRGB(66, 104, 44) else Color3.fromRGB(70, 150, 60)
	local leaf = vary(tone, 0.25, prop.x + prop.z)
	part(parent, Vector3.one * 12 * s, base * CFrame.new(0, 16 * s, 0), leaf, leafMaterial, Enum.PartType.Ball)
	part(parent, Vector3.one * 8 * s, base * CFrame.new(3 * s, 13 * s, 1 * s), leaf, leafMaterial, Enum.PartType.Ball)
	if theme.realistic then
		part(parent, Vector3.one * 9 * s, base * CFrame.new(-3 * s, 14 * s, -2 * s), vary(leaf, 0.15, prop.z), leafMaterial, Enum.PartType.Ball)
		part(parent, Vector3.one * 7 * s, base * CFrame.new(1 * s, 20 * s, -1 * s), vary(leaf, 0.15, prop.x), leafMaterial, Enum.PartType.Ball)
	end
end

-- A conifer: a tall trunk and stacked, narrowing tiers of needles.
builders.pine = function(prop, theme, parent)
	local s = prop.size
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	part(parent, Vector3.new(1.6, 26 * s, 1.6), base * CFrame.new(0, 13 * s, 0), Color3.fromRGB(84, 62, 46), mat(theme, Enum.Material.Wood))
	local needles = vary(Color3.fromRGB(38, 72, 46), 0.2, prop.x + prop.z)
	local tiers = 5
	for k = 0, tiers - 1 do
		local f = k / (tiers - 1)
		local width = (13 - f * 9) * s
		local tierCf = base * CFrame.new(0, (7 + k * 4.6) * s, 0) * CFrame.Angles(0, k * 0.7, 0)
		local p = part(parent, Vector3.new(width, 6.5 * s, width), tierCf, vary(needles, 0.1, k + prop.x), mat(theme, Enum.Material.Grass))
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	part(parent, Vector3.new(1.2, 3 * s, 1.2), base * CFrame.new(0, 29 * s, 0), needles, mat(theme, Enum.Material.Grass))
end

-- A cheap tree for the distant forest: two parts, no shadow. From the road
-- it reads as a dense treeline; up close it would look plain, so it is only
-- placed far away (Scenery rule `farTree`).
builders.farTree = function(prop, theme, parent)
	local s = prop.size
	local base = CFrame.new(prop.x, prop.y, prop.z)
	local leaves = theme.leaves
	local tone = if leaves and (math.floor(prop.x) % 3 ~= 0) then rgb(leaves[math.floor(math.abs(prop.z)) % #leaves + 1]) else Color3.fromRGB(40, 74, 46)
	local trunk = part(parent, Vector3.new(1.4, 10 * s, 1.4), base * CFrame.new(0, 5 * s, 0), Color3.fromRGB(84, 62, 46), mat(theme, Enum.Material.Wood))
	trunk.CastShadow = false
	local crown = part(parent, Vector3.new(11 * s, 22 * s, 11 * s), base * CFrame.new(0, 17 * s, 0), vary(tone, 0.2, prop.x), mat(theme, Enum.Material.Grass))
	crown.CastShadow = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = crown
end

builders.bush = function(prop, theme, parent)
	local s = prop.size
	local color = vary(if theme.realistic then Color3.fromRGB(70, 110, 48) else Color3.fromRGB(80, 160, 70), 0.2, prop.z)
	part(parent, Vector3.new(7, 5, 7) * s, CFrame.new(prop.x, prop.y + 1.5 * s, prop.z), color, mat(theme, Enum.Material.LeafyGrass), Enum.PartType.Ball)
end

builders.flag = function(prop, theme, parent)
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	part(parent, Vector3.new(0.4, 12, 0.4), base * CFrame.new(0, 6, 0), Color3.fromRGB(230, 230, 235), Enum.Material.SmoothPlastic)
	local colors = { rgb(theme.accent), rgb(theme.curb[1]), rgb(theme.curb[2]) }
	part(parent, Vector3.new(0.1, 3, 5), base * CFrame.new(0, 10.5, 2.5), colors[(math.floor(prop.x) % 3) + 1], Enum.Material.SmoothPlastic)
end

builders.billboard = function(prop, theme, parent)
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	for _, side in { -9, 9 } do
		part(parent, Vector3.new(1, 14, 1), base * CFrame.new(side, 7, 0), Color3.fromRGB(80, 80, 90), Enum.Material.SmoothPlastic)
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
		local step = part(parent, Vector3.new(60, 2.5, 5), base * CFrame.new(0, 1.25 + i * 2.5, i * 4.5), Color3.fromRGB(150, 150, 160), mat(theme, Enum.Material.Concrete))
		step.CanCollide = true
		-- Crowd: little coloured blocks.
		for c = -27, 27, 3 do
			local seed = c * 7 + i * 13 + prop.x
			local h = (math.sin(seed) * 43758.5453) % 1
			part(parent, Vector3.new(1.4, 2, 1.2), base * CFrame.new(c, 3.5 + i * 2.5, i * 4.5 - 0.5), Color3.fromHSV(h, 0.6, 0.9), Enum.Material.SmoothPlastic)
		end
	end
	local roof = part(parent, Vector3.new(64, 1, 26), base * CFrame.new(0, 20, 9) * CFrame.Angles(math.rad(-8), 0, 0), rgb(theme.accent), mat(theme, Enum.Material.Metal))
	roof.CanCollide = true
	for _, x in { -30, 30 } do
		part(parent, Vector3.new(1.2, 20, 1.2), base * CFrame.new(x, 10, 20), Color3.fromRGB(90, 90, 100), Enum.Material.SmoothPlastic)
	end
end

builders.rock = function(prop, theme, parent)
	local s = prop.size
	local tone = if theme.terrain and theme.terrain.colors and theme.terrain.colors.Rock then rgb(theme.terrain.colors.Rock) else rgb(theme.wall)
	local color = vary(tone, 0.2, prop.x)
	local material = mat(theme, Enum.Material.Rock)
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	-- Sunk a little into the ground so boulders sit rather than perch.
	part(parent, Vector3.new(10, 7, 8) * s, base * CFrame.new(0, 2 * s, 0) * CFrame.Angles(0.2, 0, 0.15), color, material)
	part(parent, Vector3.new(6, 5, 6) * s, base * CFrame.new(3 * s, 4 * s, 1 * s) * CFrame.Angles(-0.3, 0.6, 0.2), color, material)
	if theme.realistic then
		part(parent, Vector3.new(5, 3, 4) * s, base * CFrame.new(-4 * s, 1 * s, 2 * s) * CFrame.Angles(0.4, 1.1, -0.2), vary(color, 0.1, prop.z), material)
	end
end

builders.mesa = function(prop, theme, parent)
	local s = prop.size
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	local layers = { { 70, 18, 60 }, { 58, 16, 50 }, { 46, 14, 40 } }
	local y = 0
	for i, l in layers do
		local color = vary(rgb(theme.wall), 0.25, i + prop.x)
		local p = part(parent, Vector3.new(l[1], l[2], l[3]) * s, base * CFrame.new(0, (y + l[2] / 2) * s, 0), color, Enum.Material.SmoothPlastic)
		p.CanCollide = true
		y += l[2]
	end
end

builders.cactus = function(prop, _theme, parent)
	local s = prop.size
	local base = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
	local green = Color3.fromRGB(70, 130, 70)
	part(parent, Vector3.new(2, 12, 2) * s, base * CFrame.new(0, 6 * s, 0), green, Enum.Material.SmoothPlastic)
	part(parent, Vector3.new(3, 1.4, 1.4) * s, base * CFrame.new(1.8 * s, 6 * s, 0), green, Enum.Material.SmoothPlastic)
	part(parent, Vector3.new(1.4, 4, 1.4) * s, base * CFrame.new(2.8 * s, 8 * s, 0), green, Enum.Material.SmoothPlastic)
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
	part(parent, Vector3.new(0.8, 16, 0.8), base * CFrame.new(0, 8, 0), Color3.fromRGB(60, 60, 80), Enum.Material.SmoothPlastic)
	local head = part(parent, Vector3.new(1.2, 1.2, 6), base * CFrame.new(0, 16, 2.5), rgb(theme.wall), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = rgb(theme.wall)
	light.Range = 30
	light.Brightness = 2
	light.Parent = head
end

---------------------------------------------------------------------------
-- Oversized-world props (toy room, kitchen, backyard)
---------------------------------------------------------------------------
local function base(prop: any): CFrame
	return CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0)
end

local function pick(list: { Color3 }, prop: any): Color3
	return list[(math.floor(math.abs(prop.x * 3 + prop.z * 7)) % #list) + 1]
end

local TOY_COLORS = { Color3.fromRGB(240, 80, 80), Color3.fromRGB(80, 150, 240), Color3.fromRGB(255, 210, 60), Color3.fromRGB(110, 210, 120), Color3.fromRGB(190, 110, 230) }

builders.toyBlock = function(prop, _theme, parent)
	local s = prop.size * 14
	local color = pick(TOY_COLORS, prop)
	local parts = Shapes.roundedBox(parent, Vector3.new(s, s, s), s * 0.12, base(prop) * CFrame.new(0, s / 2, 0), { color = color, collide = true })
	local _ = parts
	-- A raised letter panel on the front.
	local panel = Shapes.box(parent, Vector3.new(s * 0.7, s * 0.7, 0.4), base(prop) * CFrame.new(0, s / 2, -s / 2 - 0.2), { color = Color3.fromRGB(255, 255, 255) })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 10
	gui.Parent = panel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	local letters = { "A", "B", "C", "K", "Z", "1", "2", "3" }
	label.Text = letters[(math.floor(math.abs(prop.x + prop.z)) % #letters) + 1]
	label.Parent = gui
end

builders.toyBall = function(prop, _theme, parent)
	local d = prop.size * 20
	local cf = base(prop) * CFrame.new(0, d / 2, 0)
	Shapes.ball(parent, d, cf, { color = pick(TOY_COLORS, prop), collide = true })
	Shapes.tube(parent, d * 1.01, d * 0.18, cf * CFrame.Angles(0, 0, math.rad(90)), { color = Color3.fromRGB(255, 255, 255) })
end

builders.crayon = function(prop, _theme, parent)
	local s = prop.size
	local color = pick(TOY_COLORS, prop)
	local cf = base(prop) * CFrame.new(0, 2.5 * s, 0)
	Shapes.tube(parent, 5 * s, 28 * s, cf, { color = color })
	Shapes.tube(parent, 5.3 * s, 6 * s, cf * CFrame.new(4 * s, 0, 0), { color = Color3.fromRGB(255, 255, 255) })
	Shapes.ellipsoid(parent, Vector3.new(7 * s, 4 * s, 4 * s), cf * CFrame.new(15 * s, 0, 0), { color = color })
end

builders.book = function(prop, _theme, parent)
	local s = prop.size
	local color = pick(TOY_COLORS, prop)
	Shapes.roundedBox(parent, Vector3.new(50 * s, 7 * s, 36 * s), 2 * s, base(prop) * CFrame.new(0, 3.5 * s, 0), { color = color, collide = true })
	Shapes.box(parent, Vector3.new(48 * s, 5.6 * s, 35 * s), base(prop) * CFrame.new(1 * s, 3.5 * s, 0), { color = Color3.fromRGB(250, 245, 230) })
end

local FRUIT = { Color3.fromRGB(230, 50, 50), Color3.fromRGB(255, 160, 40), Color3.fromRGB(250, 220, 60), Color3.fromRGB(120, 200, 60), Color3.fromRGB(150, 60, 160) }

builders.fruit = function(prop, _theme, parent)
	local d = prop.size * 16
	local cf = base(prop) * CFrame.new(0, d / 2, 0)
	Shapes.ellipsoid(parent, Vector3.new(d, d * 0.92, d), cf, { color = pick(FRUIT, prop), collide = true, reflectance = 0.08 })
	Shapes.pillar(parent, 0.8 * prop.size, 3 * prop.size, cf * CFrame.new(0, d * 0.5, 0), { color = Color3.fromRGB(110, 75, 45) })
	Shapes.ellipsoid(parent, Vector3.new(4, 1, 2.2) * prop.size, cf * CFrame.new(1.8 * prop.size, d * 0.5, 0), { color = Color3.fromRGB(90, 180, 70) })
end

builders.jar = function(prop, _theme, parent)
	local s = prop.size
	local cf = base(prop)
	Shapes.pillar(parent, 20 * s, 26 * s, cf * CFrame.new(0, 13 * s, 0), { color = Color3.fromRGB(200, 230, 255), material = Enum.Material.Glass, transparency = 0.4, collide = true })
	Shapes.pillar(parent, 18 * s, 18 * s, cf * CFrame.new(0, 10 * s, 0), { color = pick(FRUIT, prop) })
	Shapes.pillar(parent, 21 * s, 4 * s, cf * CFrame.new(0, 27.5 * s, 0), { color = Color3.fromRGB(220, 60, 60) })
end

builders.cookie = function(prop, _theme, parent)
	local s = prop.size
	local cf = base(prop) * CFrame.new(0, 1.2 * s, 0)
	Shapes.disc(parent, 16 * s, 2.4 * s, cf, { color = Color3.fromRGB(215, 160, 95) })
	for i = 1, 5 do
		local a = i * 1.3
		Shapes.ball(parent, 2.2 * s, cf * CFrame.new(math.cos(a) * 4.5 * s, 1.3 * s, math.sin(a) * 4.5 * s), { color = Color3.fromRGB(90, 55, 35) })
	end
end

builders.shaker = function(prop, _theme, parent)
	local s = prop.size
	local cf = base(prop)
	Shapes.pillar(parent, 8 * s, 18 * s, cf * CFrame.new(0, 9 * s, 0), { color = Color3.fromRGB(245, 245, 250), material = Enum.Material.Glass, transparency = 0.2, collide = true })
	Shapes.ellipsoid(parent, Vector3.new(8.4, 5, 8.4) * s, cf * CFrame.new(0, 18 * s, 0), { color = Color3.fromRGB(200, 205, 215), reflectance = 0.3 })
end

builders.grassBlade = function(prop, _theme, parent)
	local s = prop.size
	local green = Color3.fromRGB(80 + math.floor(prop.x) % 40, 170 + math.floor(prop.z) % 40, 60)
	local cf = base(prop)
	for k = 0, 2 do
		local lean = CFrame.Angles(math.rad(8 + k * 6), math.rad(k * 120), 0)
		Shapes.ellipsoid(parent, Vector3.new(2.4 * s, 30 * s, 1 * s), cf * lean * CFrame.new(0, 14 * s, 0), { color = green })
	end
end

builders.flower = function(prop, _theme, parent)
	local s = prop.size
	local cf = base(prop)
	Shapes.pillar(parent, 1.4 * s, 26 * s, cf * CFrame.new(0, 13 * s, 0), { color = Color3.fromRGB(80, 160, 70) })
	local petal = pick({ Color3.fromRGB(255, 120, 170), Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 200, 60), Color3.fromRGB(170, 120, 255) }, prop)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		Shapes.ellipsoid(parent, Vector3.new(7, 2, 4) * s, cf * CFrame.new(math.cos(a) * 4 * s, 27 * s, math.sin(a) * 4 * s) * CFrame.Angles(0, -a, 0), { color = petal })
	end
	Shapes.ball(parent, 4 * s, cf * CFrame.new(0, 27.5 * s, 0), { color = Color3.fromRGB(255, 210, 60) })
	Shapes.ellipsoid(parent, Vector3.new(7, 1, 3) * s, cf * CFrame.new(2.5 * s, 9 * s, 0) * CFrame.Angles(0, 0, 0.5), { color = Color3.fromRGB(90, 170, 70) })
end

builders.pebble = function(prop, _theme, parent)
	local s = prop.size
	local grey = 150 + math.floor(math.abs(prop.x)) % 50
	Shapes.ellipsoid(parent, Vector3.new(14, 7, 10) * s, base(prop) * CFrame.new(0, 2.5 * s, 0), { color = Color3.fromRGB(grey, grey - 5, grey - 15), collide = true })
end

builders.mushroom = function(prop, _theme, parent)
	local s = prop.size
	local cf = base(prop)
	Shapes.pillar(parent, 5 * s, 10 * s, cf * CFrame.new(0, 5 * s, 0), { color = Color3.fromRGB(245, 235, 215) })
	Shapes.ellipsoid(parent, Vector3.new(16, 9, 16) * s, cf * CFrame.new(0, 11 * s, 0), { color = Color3.fromRGB(230, 60, 60) })
	for i = 1, 5 do
		local a = i * 1.25
		Shapes.ball(parent, 2.4 * s, cf * CFrame.new(math.cos(a) * 4.5 * s, 14.2 * s, math.sin(a) * 4.5 * s), { color = Color3.fromRGB(255, 255, 255) })
	end
end

builders.clover = function(prop, _theme, parent)
	local s = prop.size
	local cf = base(prop)
	Shapes.pillar(parent, 0.8 * s, 6 * s, cf * CFrame.new(0, 3 * s, 0), { color = Color3.fromRGB(80, 160, 70) })
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		Shapes.ellipsoid(parent, Vector3.new(5, 0.8, 5) * s, cf * CFrame.new(math.cos(a) * 2.4 * s, 6 * s, math.sin(a) * 2.4 * s), { color = Color3.fromRGB(90, 190, 80) })
	end
end

function Props.build(prop: any, theme: any, parent: Instance)
	-- Imported models (ReplicatedStorage.KartAssets) replace the built-in
	-- shapes for trees, pines, rocks, bushes and the distant forest.
	if Assets.placeProp(prop, parent, prop.kind ~= "farTree") then
		return
	end
	local builder = builders[prop.kind]
	if builder then
		builder(prop, theme, parent)
	end
end

Props.Kinds = builders

return Props
