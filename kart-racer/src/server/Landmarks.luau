-- Big themed pieces for the oversized-world tracks: tunnels (the bed, garden
-- hose, cardboard box, hollow log), set pieces (toaster, cereal bowls, toy
-- train set, night lamp, flowerpots, sprinklers...), the moving crossers
-- (toy robot, toy train, beetles) and giant room walls for indoor tracks.
--
-- Built from rounded primitives (common/Shapes). Every one of these is a
-- good candidate for a custom mesh later; see README "Assets to replace".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Track = require(Shared.Track)
local Shapes = require(ReplicatedStorage.Common.Shapes)

local Landmarks = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function c3(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function at(track: Track.Built, distance: number, lateral: number, height: number?): CFrame
	local p = Track.spot(track, distance, lateral)
	local _, tan = Track.at(track, distance)
	local pos = Vector3.new(p.x, p.y + (height or 0), p.z)
	return CFrame.lookAt(pos, pos + Vector3.new(tan.x, 0, tan.z))
end

---------------------------------------------------------------------------
-- Tunnels
---------------------------------------------------------------------------
local tunnelBuilders: { [string]: (Track.Built, number, number, any, Instance) -> () } = {}

-- A giant bed the road passes under: legs outside the walls, a puffy
-- mattress and blanket above, a pillow and a headboard at one end.
tunnelBuilders.bed = function(track, from, to, _theme, parent)
	local half = track.def.width / 2 + Track.ShoulderWidth + 6
	local mid = (from + to) / 2
	local length = to - from
	local cf = at(track, mid, 0, 0)
	local h = 34
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Shapes.pillar(parent, 6, h, cf * CFrame.new(sx * half, h / 2, sz * length / 2), { color = rgb(120, 80, 50), collide = true })
		end
	end
	Shapes.roundedBox(parent, Vector3.new(half * 2 + 10, 6, length + 10), 4, cf * CFrame.new(0, h + 3, 0), { color = rgb(120, 80, 50), collide = true })
	Shapes.roundedBox(parent, Vector3.new(half * 2 + 8, 10, length + 6), 5, cf * CFrame.new(0, h + 11, 0), { color = rgb(245, 245, 255) })
	Shapes.ellipsoid(parent, Vector3.new(half * 2 + 16, 12, length * 0.75), cf * CFrame.new(0, h + 18, length * 0.1), { color = rgb(90, 120, 220) })
	Shapes.ellipsoid(parent, Vector3.new(half * 1.2, 10, 18), cf * CFrame.new(0, h + 20, -length / 2 + 10), { color = rgb(255, 255, 255) })
	Shapes.roundedBox(parent, Vector3.new(half * 2 + 12, 40, 6), 6, cf * CFrame.new(0, h + 10, -length / 2 - 6), { color = rgb(140, 95, 60), collide = true })
	-- Fairy lights under the bed so the tunnel isn't pitch black.
	for z = -length / 2 + 6, length / 2 - 6, 10 do
		local bulb = Shapes.ball(parent, 1.4, cf * CFrame.new(0, h - 1, z), { color = rgb(255, 220, 140), material = Enum.Material.Neon })
		local light = Instance.new("PointLight")
		light.Range = 22
		light.Brightness = 1.4
		light.Color = bulb.Color
		light.Parent = bulb
	end
end

-- Rings of a green garden hose with yellow stripes.
tunnelBuilders.hose = function(track, from, to, _theme, parent)
	local span = track.def.width + Track.ShoulderWidth * 2 + 10
	local i = 0
	for d = from, to, 7 do
		i += 1
		local cf = at(track, d, 0, -2)
		Shapes.arch(parent, span, 4, 6, cf, { color = if i % 3 == 0 then rgb(255, 210, 60) else rgb(60, 170, 80), collide = true }, 16)
	end
	local endCf = at(track, to, 0, -2)
	Shapes.tube(parent, 6, 40, endCf * CFrame.new(span / 2 + 18, 2, 6) * CFrame.Angles(0, math.rad(90), 0), { color = rgb(60, 170, 80) })
end

-- A cardboard box with the ends cut out.
tunnelBuilders.box = function(track, from, to, _theme, parent)
	local span = track.def.width + Track.ShoulderWidth * 2 + 6
	local mid = (from + to) / 2
	local length = to - from
	local cf = at(track, mid, 0, 0)
	local h = 30
	local cardboard = rgb(200, 160, 110)
	for _, sx in { -1, 1 } do
		Shapes.box(parent, Vector3.new(3, h, length), cf * CFrame.new(sx * span / 2, h / 2, 0), { color = cardboard, collide = true })
	end
	Shapes.box(parent, Vector3.new(span + 3, 3, length), cf * CFrame.new(0, h, 0), { color = cardboard, collide = true })
	Shapes.box(parent, Vector3.new(span * 0.3, 0.2, length + 0.2), cf * CFrame.new(0, h + 1.6, 0), { color = rgb(220, 200, 150) })
	for _, sz in { -1, 1 } do
		Shapes.box(parent, Vector3.new(span + 3, 8, 1), cf * CFrame.new(0, h - 4, sz * length / 2), { color = cardboard })
	end
end

-- A hollow log (half-rings of bark).
tunnelBuilders.log = function(track, from, to, _theme, parent)
	local span = track.def.width + 10
	for d = from, to, 4 do
		Shapes.arch(parent, span, 5, 4.5, at(track, d, 0, -3), { color = rgb(130, 90, 55), collide = true }, 16)
	end
end

tunnelBuilders.arch = function(track, from, to, theme, parent)
	local span = track.def.width + Track.ShoulderWidth * 2 + 6
	local i = 0
	for d = from, to, 10 do
		i += 1
		Shapes.arch(parent, span, 3, 3, at(track, d, 0, 0), { color = if i % 2 == 0 then c3(theme.accent) else c3(theme.wall), material = Enum.Material.Neon }, 14)
	end
end

function Landmarks.tunnel(track: Track.Built, style: string, from: number, to: number, theme: any, parent: Instance)
	local builder = tunnelBuilders[style]
	if builder then
		builder(track, from * track.length, to * track.length, theme, parent)
	end
end

---------------------------------------------------------------------------
-- Set pieces (placed by Scenery.setPieceSpots)
---------------------------------------------------------------------------
local pieces: { [string]: (CFrame, any, Instance) -> () } = {}

pieces.toaster = function(cf, _theme, parent)
	local body = rgb(220, 70, 60)
	Shapes.roundedBox(parent, Vector3.new(70, 50, 44), 12, cf * CFrame.new(0, 25, 0), { color = body, collide = true, reflectance = 0.1 })
	for _, x in { -14, 14 } do
		Shapes.roundedBox(parent, Vector3.new(14, 2, 34), 4, cf * CFrame.new(x, 50.5, 0), { color = rgb(40, 40, 45) })
		-- Toast popping out.
		Shapes.roundedBox(parent, Vector3.new(12, 22, 30), 5, cf * CFrame.new(x, 58, 0), { color = rgb(225, 170, 90) })
		Shapes.box(parent, Vector3.new(12.2, 18, 26), cf * CFrame.new(x, 58, 0), { color = rgb(245, 215, 150) })
	end
	Shapes.box(parent, Vector3.new(4, 4, 10), cf * CFrame.new(37, 30, 0), { color = rgb(40, 40, 45) })
	Shapes.ball(parent, 6, cf * CFrame.new(37, 22, -8), { color = rgb(240, 240, 240) })
end

pieces.cerealBowl = function(cf, _theme, parent)
	Shapes.pillar(parent, 50, 18, cf * CFrame.new(0, 9, 0), { color = rgb(255, 255, 255), collide = true })
	Shapes.pillar(parent, 56, 4, cf * CFrame.new(0, 19, 0), { color = rgb(90, 150, 230), collide = true })
	Shapes.pillar(parent, 48, 1, cf * CFrame.new(0, 19.6, 0), { color = rgb(250, 248, 240) })
	local colors = { rgb(255, 120, 60), rgb(255, 210, 70), rgb(140, 200, 80), rgb(200, 100, 200) }
	for i = 1, 22 do
		local a = i * 2.4
		local r = (i % 6) * 3.5
		Shapes.tube(parent, 5, 2, cf * CFrame.new(math.cos(a) * r, 21, math.sin(a) * r) * CFrame.Angles(0, a, math.rad(90)), { color = colors[i % 4 + 1] })
	end
end

pieces.mug = function(cf, _theme, parent)
	Shapes.pillar(parent, 30, 40, cf * CFrame.new(0, 20, 0), { color = rgb(255, 230, 90), collide = true })
	Shapes.pillar(parent, 26, 1, cf * CFrame.new(0, 39, 0), { color = rgb(110, 70, 40) })
	Shapes.arch(parent, 18, 4, 4, cf * CFrame.new(15, 20, 0) * CFrame.Angles(0, 0, math.rad(-90)), { color = rgb(255, 230, 90) }, 10)
end

pieces.fruitBowl = function(cf, _theme, parent)
	Shapes.ellipsoid(parent, Vector3.new(60, 22, 60), cf * CFrame.new(0, 8, 0), { color = rgb(170, 220, 255), material = Enum.Material.Glass, transparency = 0.3, collide = true })
	local fruit = { rgb(230, 50, 50), rgb(255, 160, 40), rgb(250, 220, 60), rgb(120, 200, 60) }
	for i = 1, 9 do
		local a = i * 2.1
		Shapes.ball(parent, 14, cf * CFrame.new(math.cos(a) * 12, 20 + (i % 3) * 5, math.sin(a) * 12), { color = fruit[i % 4 + 1] })
	end
end

pieces.trainSet = function(cf, _theme, parent)
	-- An oval of toy track with sleepers.
	for i = 0, 47 do
		local a = i / 48 * math.pi * 2
		local p = Vector3.new(math.cos(a) * 60, 0.6, math.sin(a) * 36)
		local tangent = Vector3.new(-math.sin(a) * 60, 0, math.cos(a) * 36).Unit
		local seg = CFrame.lookAt(p, p + tangent)
		Shapes.box(parent, Vector3.new(12, 1.2, 3), cf * seg, { color = rgb(160, 110, 70) })
		for _, side in { -1, 1 } do
			Shapes.box(parent, Vector3.new(1, 1.6, 9), cf * seg * CFrame.new(side * 4, 0.6, 0), { color = rgb(200, 200, 210) })
		end
	end
	-- A little station.
	Shapes.roundedBox(parent, Vector3.new(24, 16, 16), 3, cf * CFrame.new(0, 8, 0), { color = rgb(240, 90, 90), collide = true })
	Shapes.box(parent, Vector3.new(28, 3, 20), cf * CFrame.new(0, 17, 0), { color = rgb(80, 120, 220) })
end

pieces.nightLamp = function(cf, _theme, parent)
	Shapes.pillar(parent, 40, 6, cf * CFrame.new(0, 3, 0), { color = rgb(240, 240, 250), collide = true })
	Shapes.pillar(parent, 6, 70, cf * CFrame.new(0, 40, 0), { color = rgb(240, 240, 250), collide = true })
	local shade = Shapes.ellipsoid(parent, Vector3.new(56, 40, 56), cf * CFrame.new(0, 86, 0), { color = rgb(255, 220, 140), material = Enum.Material.Neon, transparency = 0.15 })
	local light = Instance.new("PointLight")
	light.Range = 120
	light.Brightness = 2.2
	light.Color = rgb(255, 210, 140)
	light.Shadows = true
	light.Parent = shade
end

pieces.toyChest = function(cf, _theme, parent)
	Shapes.roundedBox(parent, Vector3.new(80, 40, 50), 8, cf * CFrame.new(0, 20, 0), { color = rgb(80, 150, 230), collide = true })
	Shapes.ellipsoid(parent, Vector3.new(84, 20, 54), cf * CFrame.new(0, 42, 0), { color = rgb(255, 200, 60), collide = true })
	for i, color in { rgb(255, 90, 90), rgb(110, 220, 120), rgb(255, 255, 255) } do
		Shapes.ball(parent, 12, cf * CFrame.new((i - 2) * 20, 54, 0), { color = color })
	end
end

pieces.bookStack = function(cf, _theme, parent)
	local colors = { rgb(220, 70, 70), rgb(70, 130, 220), rgb(250, 200, 60), rgb(110, 190, 110) }
	for i = 0, 4 do
		Shapes.roundedBox(parent, Vector3.new(70 - i * 4, 9, 50 - i * 3), 3, cf * CFrame.new(i * 1.5, 4.5 + i * 9, 0) * CFrame.Angles(0, math.rad(i * 7), 0), { color = colors[i % 4 + 1], collide = true })
	end
end

pieces.flowerpot = function(cf, _theme, parent)
	Shapes.pillar(parent, 46, 34, cf * CFrame.new(0, 17, 0), { color = rgb(210, 110, 70), collide = true })
	Shapes.pillar(parent, 52, 6, cf * CFrame.new(0, 34, 0), { color = rgb(220, 120, 80), collide = true })
	Shapes.pillar(parent, 44, 1, cf * CFrame.new(0, 37, 0), { color = rgb(100, 70, 45) })
	Shapes.pillar(parent, 3, 50, cf * CFrame.new(0, 60, 0), { color = rgb(80, 160, 70) })
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		Shapes.ellipsoid(parent, Vector3.new(16, 6, 9), cf * CFrame.new(math.cos(a) * 9, 86, math.sin(a) * 9) * CFrame.Angles(0, -a, 0), { color = rgb(255, 120, 170) })
	end
	Shapes.ball(parent, 10, cf * CFrame.new(0, 87, 0), { color = rgb(255, 220, 60) })
end

-- Sprinklers spray when their slippery zone is on (TrackAnimator toggles the water).
pieces.sprinkler = function(cf, _theme, parent)
	Shapes.pillar(parent, 10, 4, cf * CFrame.new(0, 2, 0), { color = rgb(70, 70, 80), collide = true })
	Shapes.pillar(parent, 3, 10, cf * CFrame.new(0, 9, 0), { color = rgb(200, 200, 210) })
	local head = Shapes.ellipsoid(parent, Vector3.new(6, 3, 6), cf * CFrame.new(0, 15, 0), { color = rgb(255, 210, 60) })
	head.Name = "SprinklerHead"
	local water = Instance.new("ParticleEmitter")
	water.Name = "Water"
	water.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	water.Color = ColorSequence.new(rgb(170, 220, 255))
	water.Size = NumberSequence.new(0.8, 0.3)
	water.Transparency = NumberSequence.new(0.2, 1)
	water.Lifetime = NumberRange.new(1.2, 1.6)
	water.Speed = NumberRange.new(45, 60)
	water.SpreadAngle = Vector2.new(25, 60)
	water.Acceleration = Vector3.new(0, -60, 0)
	water.Rate = 160
	water.Enabled = false
	water.Parent = head
end

pieces.log = function(_cf, _theme, _parent)
	-- The hollow log shortcut is built with the shortcut itself (see TrackBuilder).
end

pieces.wateringCan = function(cf, _theme, parent)
	Shapes.ellipsoid(parent, Vector3.new(50, 44, 40), cf * CFrame.new(0, 22, 0), { color = rgb(90, 180, 220), collide = true })
	Shapes.tube(parent, 6, 46, cf * CFrame.new(-34, 34, 0) * CFrame.Angles(0, 0, math.rad(35)), { color = rgb(90, 180, 220) })
	Shapes.pillar(parent, 10, 3, cf * CFrame.new(-52, 46, 0), { color = rgb(70, 150, 190) })
	Shapes.arch(parent, 30, 4, 4, cf * CFrame.new(10, 44, 0), { color = rgb(70, 150, 190) }, 10)
end

function Landmarks.setPiece(kind: string, cf: CFrame, theme: any, parent: Instance)
	local builder = pieces[kind]
	if builder then
		builder(cf, theme, parent)
	end
end

---------------------------------------------------------------------------
-- Crossers (moved by client/TrackAnimator; hits are checked by the server)
---------------------------------------------------------------------------
local crossers: { [string]: (Model) -> () } = {}

crossers.robot = function(m)
	local base = CFrame.new()
	local metal = rgb(180, 190, 210)
	Shapes.roundedBox(m, Vector3.new(9, 9, 7), 2, base * CFrame.new(0, 9, 0), { color = metal, anchored = true })
	Shapes.roundedBox(m, Vector3.new(7, 6, 6), 2, base * CFrame.new(0, 17, 0), { color = metal, anchored = true })
	for _, x in { -1.6, 1.6 } do
		Shapes.ball(m, 2.2, base * CFrame.new(x, 17.5, -3), { color = rgb(80, 220, 255), material = Enum.Material.Neon, anchored = true })
		Shapes.pillar(m, 2.4, 5, base * CFrame.new(x * 1.4, 2.5, 0), { color = rgb(120, 130, 150), anchored = true })
	end
	Shapes.pillar(m, 0.5, 4, base * CFrame.new(0, 22, 0), { color = rgb(120, 130, 150), anchored = true })
	Shapes.ball(m, 1.6, base * CFrame.new(0, 24.5, 0), { color = rgb(255, 80, 80), material = Enum.Material.Neon, anchored = true })
	for _, x in { -6, 6 } do
		Shapes.capsule(m, 2.4, 8, base * CFrame.new(x, 10, 0), { color = metal, anchored = true })
	end
end

crossers.train = function(m)
	local colors = { rgb(230, 60, 60), rgb(70, 130, 230), rgb(250, 200, 60) }
	for i = 0, 2 do
		local cf = CFrame.new(0, 0, (i - 1) * 13)
		Shapes.roundedBox(m, Vector3.new(9, 9, 11), 2, cf * CFrame.new(0, 6, 0), { color = colors[i + 1], anchored = true })
		for _, x in { -4.7, 4.7 } do
			for _, z in { -3.5, 3.5 } do
				Shapes.tube(m, 3.6, 1, cf * CFrame.new(x, 2, z), { color = rgb(40, 40, 45), anchored = true })
			end
		end
	end
	Shapes.pillar(m, 3, 5, CFrame.new(0, 12.5, -16), { color = rgb(40, 40, 45), anchored = true })
end

crossers.beetle = function(m)
	local shell = rgb(220, 40, 40)
	Shapes.ellipsoid(m, Vector3.new(12, 7, 15), CFrame.new(0, 5, 0), { color = shell, anchored = true, reflectance = 0.15 })
	Shapes.ellipsoid(m, Vector3.new(7, 5, 5), CFrame.new(0, 4, -8), { color = rgb(30, 30, 35), anchored = true })
	for _, x in { -2, 2 } do
		Shapes.ball(m, 1.6, CFrame.new(x, 5, -10), { color = rgb(255, 255, 255), anchored = true })
	end
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		Shapes.ball(m, 2.2, CFrame.new(math.cos(a) * 3.5, 8.4, math.sin(a) * 4.5), { color = rgb(30, 30, 35), anchored = true })
	end
	for _, side in { -1, 1 } do
		for k = -1, 1 do
			Shapes.box(m, Vector3.new(6, 0.6, 0.6), CFrame.new(side * 7, 2, k * 4) * CFrame.Angles(0, 0, side * 0.5), { color = rgb(30, 30, 35), anchored = true })
		end
	end
end

function Landmarks.crosser(kind: string, index: number, parent: Instance, start: CFrame): Model
	local m = Instance.new("Model")
	m.Name = `Crosser{index}`
	local builder = crossers[kind]
	if builder then
		builder(m)
	end
	-- Pivot at the model's base so the animator can place it on the road.
	local origin = Instance.new("Part")
	origin.Name = "Origin"
	origin.Anchored = true
	origin.CanCollide = false
	origin.CanQuery = false
	origin.CanTouch = false
	origin.Transparency = 1
	origin.Size = Vector3.one
	origin.CFrame = CFrame.new()
	origin.Parent = m
	m.PrimaryPart = origin
	-- Built around the origin; move every part to the starting spot.
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = start * d.CFrame
		end
	end
	m:SetAttribute("CrosserIndex", index)
	m.Parent = parent
	return m
end

---------------------------------------------------------------------------
-- Room walls for indoor tracks (the bedroom, the kitchen)
---------------------------------------------------------------------------
function Landmarks.room(theme: any, minX: number, maxX: number, minZ: number, maxZ: number, floorY: number, parent: Instance)
	local room = theme.room
	if not room then
		return
	end
	local margin = 280
	local x0, x1, z0, z1 = minX - margin, maxX + margin, minZ - margin, maxZ + margin
	local h = room.height
	local wallColor, trim = c3(room.wall), c3(room.trim)
	local function wall(cx: number, cz: number, w: number, d: number)
		Shapes.box(parent, Vector3.new(w, h, d), CFrame.new(cx, floorY + h / 2, cz), { color = wallColor, collide = true })
		Shapes.box(parent, Vector3.new(w + 1, 14, d + 1), CFrame.new(cx, floorY + 7, cz), { color = trim })
	end
	wall((x0 + x1) / 2, z0, x1 - x0, 6)
	wall((x0 + x1) / 2, z1, x1 - x0, 6)
	wall(x0, (z0 + z1) / 2, 6, z1 - z0)
	wall(x1, (z0 + z1) / 2, 6, z1 - z0)

	-- A window in the far wall (moonlit for the bedroom, sunny for the kitchen).
	local night = theme.clock < 6 or theme.clock > 19
	local winCf = CFrame.new((x0 + x1) / 2, floorY + h * 0.55, z0 + 4)
	Shapes.roundedBox(parent, Vector3.new(180, 140, 2), 10, winCf, { color = trim })
	Shapes.box(parent, Vector3.new(164, 124, 2.2), winCf, { color = if night then rgb(30, 40, 90) else rgb(170, 220, 255), material = Enum.Material.Neon, transparency = if night then 0 else 0.3 })
	Shapes.box(parent, Vector3.new(6, 124, 2.4), winCf, { color = trim })
	Shapes.box(parent, Vector3.new(164, 6, 2.4), winCf, { color = trim })
	if night then
		Shapes.disc(parent, 34, 2.5, winCf * CFrame.new(40, 30, 0) * CFrame.Angles(math.rad(90), 0, 0), { color = rgb(255, 250, 220), material = Enum.Material.Neon })
		for i = 1, 14 do
			Shapes.ball(parent, 2.2, winCf * CFrame.new(-70 + (i * 37) % 140, -50 + (i * 23) % 100, 0.5), { color = rgb(255, 255, 230), material = Enum.Material.Neon })
		end
	end
	-- A big door on a side wall.
	local doorCf = CFrame.new(x1 - 4, floorY + 110, (z0 + z1) / 2) * CFrame.Angles(0, math.rad(90), 0)
	Shapes.roundedBox(parent, Vector3.new(120, 220, 3), 6, doorCf, { color = trim })
	Shapes.ball(parent, 10, doorCf * CFrame.new(42, -10, -3), { color = rgb(255, 210, 60), reflectance = 0.3 })
end

return Landmarks
