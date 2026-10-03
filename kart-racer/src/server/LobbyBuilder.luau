-- Compact indoor Kart HQ: soft lighting, four voting pads, garage,
-- trophy room and party bays. No practice hall or viewing lounge.
-- Clients draw the wall screens and animate proximity doors.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Karts = require(Shared.Karts)
local LobbyLayout = require(Shared.LobbyLayout)
local KartRig = require(ReplicatedStorage.Common.KartRig)
local Shapes = require(ReplicatedStorage.Common.Shapes)


local LobbyBuilder = {}

-- Optional looping ambience (a soft machinery hum). Upload a sound to Roblox
-- and paste its id here, e.g. "rbxassetid://123456". Empty = silent.
LobbyBuilder.AmbientSoundId = ""

local C = {
	wall = Color3.fromRGB(68, 75, 86),
	wallLight = Color3.fromRGB(90, 99, 112),
	panel = Color3.fromRGB(28, 38, 72),
	floor = Color3.fromRGB(58, 63, 72),
	floorLine = Color3.fromRGB(44, 64, 110),
	navy = Color3.fromRGB(16, 22, 44),
	cyan = Color3.fromRGB(110, 165, 180),
	cyanSoft = Color3.fromRGB(155, 185, 195),
	white = Color3.fromRGB(240, 246, 255),
	lamp = Color3.fromRGB(190, 215, 245),
	steel = Color3.fromRGB(170, 185, 210),
	gold = Color3.fromRGB(255, 200, 60),
	silver = Color3.fromRGB(205, 215, 230),
	bronze = Color3.fromRGB(225, 145, 80),
	pink = Color3.fromRGB(255, 90, 170),
	screen = Color3.fromRGB(8, 12, 26),
	glass = Color3.fromRGB(150, 220, 255),
}
local NEON = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass

local O = LobbyLayout.Origin
local HW, HD = LobbyLayout.HalfWidth, LobbyLayout.HalfDepth
local HEIGHT, DECK = LobbyLayout.Height, LobbyLayout.DeckHeight
local WALL = 4 -- chamber wall thickness

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- World position from chamber-relative x/z.
local function W(x: number, y: number, z: number): Vector3
	return Vector3.new(O.x + x, y, O.z + z)
end

local function at(spot: LobbyLayout.Spot, y: number?): CFrame
	return CFrame.new(spot.x, (y or 0) + spot.y, spot.z)
end

-- A CFrame at `pos` whose front face (-Z) looks along `dir`.
local function facing(pos: Vector3, dir: Vector3): CFrame
	return CFrame.lookAt(pos, pos + dir)
end

local function light(parent: BasePart, kind: string, range: number, brightness: number, color: Color3)
	local l = Instance.new(kind) :: any
	l.Range = range
	l.Brightness = brightness
	l.Color = color
	l.Shadows = false
	l.Parent = parent
	return l
end

-- Text on the front face of a part.
local function text(part: BasePart, value: string, color: Color3, pixelsPerStud: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 20
	gui.LightInfluence = 0
	gui.Parent = part
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.5
	l.Text = value
	l.Parent = gui
	return l
end

local function prompt(parent: BasePart, action: string, object: string): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.MaxActivationDistance = 14
	p.RequiresLineOfSight = false
	p.HoldDuration = 0.15
	p.Parent = parent
	return p
end

-- A disc with a glowing rim: a neon disc with a slightly smaller one on top.
local function rimDisc(parent: Instance, diameter: number, top: number, cf: CFrame, color: Color3, rim: Color3, rimWidth: number?)
	local w = rimWidth or 1
	Shapes.disc(parent, diameter, 0.4, cf * CFrame.new(0, top - 0.25, 0), { color = rim, material = NEON, collide = true })
	return Shapes.disc(parent, diameter - w * 2, 0.4, cf * CFrame.new(0, top - 0.2, 0), { color = color, collide = true })
end

---------------------------------------------------------------------------
-- Architecture pieces
---------------------------------------------------------------------------

-- A straight wall from floor point `a` to `b`, with rectangular openings.
-- Each opening is { at = distance from a, width, bottom, top }.
type Opening = { at: number, width: number, bottom: number, top: number }
local function wall(parent: Instance, a: Vector3, b: Vector3, height: number, thickness: number, openings: { Opening }, color: Color3?)
	local along = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = along.Magnitude
	local u = along.Unit
	local style = { color = color or C.wall, collide = true }
	local function block(d0: number, d1: number, y0: number, y1: number)
		if d1 - d0 < 0.05 or y1 - y0 < 0.05 then
			return
		end
		local center = a + u * ((d0 + d1) / 2) + Vector3.new(0, (y0 + y1) / 2, 0)
		Shapes.box(parent, Vector3.new(thickness, y1 - y0, d1 - d0), facing(center, u), style)
	end
	table.sort(openings, function(x, y)
		return x.at < y.at
	end)
	local cursor = 0
	for _, o in openings do
		local s, e = o.at - o.width / 2, o.at + o.width / 2
		block(cursor, s, 0, height)
		block(s, e, o.top, height)
		block(s, e, 0, o.bottom)
		cursor = e
	end
	block(cursor, length, 0, height)
end

-- A beveled wall panel on a wall, facing out along cf's look direction.
local function wallPanel(parent: Instance, cf: CFrame, w: number, h: number, color: Color3?)
	Shapes.box(parent, Vector3.new(w, h, 0.6), cf, { color = color or C.panel })
	Shapes.box(parent, Vector3.new(w - 2.4, h - 2.4, 0.6), cf * CFrame.new(0, 0, -0.5), { color = C.wallLight })
	-- 45° chamfers along each edge catch the light like a bevel.
	for _, sy in { -1, 1 } do
		Shapes.box(parent, Vector3.new(w - 1.2, 0.9, 0.9), cf * CFrame.new(0, sy * (h / 2 - 1.1), -0.35) * CFrame.Angles(math.rad(45), 0, 0), { color = C.panel })
	end
	for _, sx in { -1, 1 } do
		Shapes.box(parent, Vector3.new(0.9, h - 1.2, 0.9), cf * CFrame.new(sx * (w / 2 - 1.1), 0, -0.35) * CFrame.Angles(0, math.rad(45), 0), { color = C.panel })
	end
end

-- A rail between two floor points: posts, a steel top tube, a cyan glow tube
-- under it and a glass panel. Works on slopes (stairs and ramps) too.
local RAIL_HEIGHT = 3.6
local function railing(parent: Instance, a: Vector3, b: Vector3, posts: boolean?)
	local length = (b - a).Magnitude
	if length < 0.1 then
		return
	end
	local up = Vector3.new(0, RAIL_HEIGHT, 0)
	local mid = (a + b) / 2
	local along = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0) -- local x runs a → b
	Shapes.tube(parent, 0.7, length + 0.6, along + up, { color = C.steel, collide = true })
	Shapes.tube(parent, 0.35, length, along + up * 0.82, { color = C.cyan, material = NEON })
	Shapes.box(parent, Vector3.new(length, RAIL_HEIGHT * 0.7, 0.2), along + up * 0.45, { color = C.glass, material = GLASS, transparency = 0.6, collide = true })
	if posts ~= false then
		local n = math.max(1, math.floor(length / 8 + 0.5))
		for i = 0, n do
			local p = a:Lerp(b, i / n)
			Shapes.pillar(parent, 0.7, RAIL_HEIGHT, CFrame.new(p + up / 2), { color = C.steel })
		end
	end
end

local function railPath(parent: Instance, points: { Vector3 })
	for i = 1, #points - 1 do
		railing(parent, points[i], points[i + 1], i == 1 or i == #points - 1 or (points[i + 1] - points[i]).Magnitude > 4)
	end
end

-- Quarter-circle corner points (for rounded railing ends).
local function arc(center: Vector3, radius: number, from: number, to: number, steps: number): { Vector3 }
	local out = {}
	for i = 0, steps do
		local a = from + (to - from) * i / steps
		table.insert(out, center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
	end
	return out
end

-- A rounded column with glowing rings and a lit panel facing `face`.
local function column(parent: Instance, base: Vector3, height: number, face: Vector3)
	Shapes.pillar(parent, 11, 2, CFrame.new(base + Vector3.new(0, 1, 0)), { color = C.wallLight, collide = true })
	Shapes.pillar(parent, 8, height, CFrame.new(base + Vector3.new(0, height / 2, 0)), { color = C.panel, collide = true })
	Shapes.pillar(parent, 11, 2.4, CFrame.new(base + Vector3.new(0, height - 1.2, 0)), { color = C.wallLight })
	for _, y in { 8, 40, 76 } do
		if y < height - 4 then
			Shapes.pillar(parent, 8.6, 0.8, CFrame.new(base + Vector3.new(0, y, 0)), { color = C.cyan, material = NEON })
		end
	end
	-- Illuminated panel strip on the side facing the room.
	local stripHeight = math.min(28, height - 20)
	local stripCf = facing(base + face.Unit * 4.05 + Vector3.new(0, 10 + stripHeight / 2, 0), face)
	Shapes.box(parent, Vector3.new(2.2, stripHeight, 0.3), stripCf, { color = C.cyanSoft, material = NEON })
	Shapes.box(parent, Vector3.new(3.4, stripHeight + 1.2, 0.2), stripCf * CFrame.new(0, 0, 0.15), { color = C.navy })
end

-- A hanging checkered racing banner with the HQ name.
local function banner(parent: Instance, top: Vector3, face: Vector3, accent: Color3)
	local cf = facing(top, face)
	Shapes.tube(parent, 0.6, 12, cf * CFrame.new(0, 0.3, 0), { color = C.steel })
	local cloth = Shapes.box(parent, Vector3.new(10, 26, 0.3), cf * CFrame.new(0, -13.3, 0), { color = C.navy })
	Shapes.box(parent, Vector3.new(10, 1.2, 0.35), cf * CFrame.new(0, -1.2, 0), { color = accent, material = NEON })
	for i = 0, 9 do
		local col, row = i % 5, math.floor(i / 5)
		Shapes.box(parent, Vector3.new(2, 2, 0.35), cf * CFrame.new(-4 + col * 2, -23.3 - row * 2, 0), { color = if (col + row) % 2 == 0 then C.white else C.navy })
	end
	Shapes.box(parent, Vector3.new(10, 0.6, 0.35), cf * CFrame.new(0, -21.8, 0), { color = accent, material = NEON })
	text(cloth, "KART\nHQ", C.white, 12)
end

-- Two-panel sliding door. Parts with a "Side" attribute slide apart on
-- clients (client/LobbyScreens); parts named "Glow" light up.
local function slidingDoor(parent: Instance, name: string, cf: CFrame, w: number, h: number, accent: Color3): Model
	local door = Instance.new("Model")
	door.Name = name
	door:SetAttribute("SlidingDoor", true)
	door:SetAttribute("Width", w)
	for _, side in { -1, 1 } do
		local panelCf = cf * CFrame.new(side * w / 4, h / 2, 0)
		local panel = Shapes.box(door, Vector3.new(w / 2, h, 0.8), panelCf, { color = C.wallLight, collide = true, name = `Panel{if side < 0 then 1 else 2}` })
		panel:SetAttribute("Side", side)
		local window = Shapes.box(door, Vector3.new(w / 2 - 3, h * 0.35, 0.9), panelCf * CFrame.new(0, h * 0.12, 0), { color = C.glass, material = GLASS, transparency = 0.45, name = "Window" })
		window:SetAttribute("Side", side)
		local stripe = Shapes.box(door, Vector3.new(w / 2 - 1, 0.5, 1), panelCf * CFrame.new(0, -h * 0.18, 0), { color = accent, material = NEON, name = "Glow" })
		stripe:SetAttribute("Side", side)
		local edge = Shapes.box(door, Vector3.new(0.4, h - 1, 1), panelCf * CFrame.new(-side * (w / 4 - 0.3), 0, 0), { color = accent, material = NEON, name = "Glow" })
		edge:SetAttribute("Side", side)
	end
	-- Frame: posts, header and a glowing outline.
	for _, side in { -1, 1 } do
		Shapes.box(door, Vector3.new(1.6, h + 1.6, 1.6), cf * CFrame.new(side * (w / 2 + 0.8), (h + 1.6) / 2, 0), { color = C.steel, collide = true })
		Shapes.box(door, Vector3.new(0.4, h + 1, 0.4), cf * CFrame.new(side * (w / 2 + 0.2), h / 2, -1.1), { color = accent, material = NEON, name = "Glow" })
	end
	Shapes.box(door, Vector3.new(w + 3.2, 1.6, 1.6), cf * CFrame.new(0, h + 0.8, 0), { color = C.steel, collide = true })
	Shapes.box(door, Vector3.new(w + 0.4, 0.4, 0.4), cf * CFrame.new(0, h + 0.2, -1.1), { color = accent, material = NEON, name = "Glow" })
	door.Parent = parent
	return door
end

-- Floor, ceiling, light and walls around a side room. The wall shared with
-- the chamber already exists, apart from any stretch beyond the chamber.
local function roomShell(parent: Instance, room: LobbyLayout.Room, height: number, lights: number)
	local b = room.box
	local x0, x1, z0, z1 = b.min.x, b.max.x, b.min.z, b.max.z
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local folder = Instance.new("Folder")
	folder.Name = room.id
	folder.Parent = parent
	Shapes.box(folder, Vector3.new(x1 - x0 + 4, 1, z1 - z0 + 4), CFrame.new(cx, -0.5, cz), { color = C.floor, collide = true, name = "Floor" })
	-- Spans stop inside the chamber wall on the near side, so nothing pokes in.
	local e0 = if room.side < 0 then x0 - 2 else x0 + 2
	local e1 = if room.side < 0 then x1 - 2 else x1 + 2
	Shapes.box(folder, Vector3.new(e1 - e0, 2, z1 - z0 + 4), CFrame.new((e0 + e1) / 2, height + 1, cz), { color = C.wall, collide = true })
	-- Walls: far side, both ends, and the chamber side outside the chamber.
	local farX = if room.side < 0 then x0 else x1
	local nearX = if room.side < 0 then x1 else x0
	wall(folder, Vector3.new(farX + room.side, 0, z0 - 2), Vector3.new(farX + room.side, 0, z1 + 2), height, 2, {})
	wall(folder, Vector3.new(e0, 0, z0 - 1), Vector3.new(e1, 0, z0 - 1), height, 2, {})
	wall(folder, Vector3.new(e0, 0, z1 + 1), Vector3.new(e1, 0, z1 + 1), height, 2, {})
	local chamberZ0, chamberZ1 = O.z - HD - WALL, O.z + HD + WALL
	if z0 < chamberZ0 then
		wall(folder, Vector3.new(nearX - room.side, 0, z0), Vector3.new(nearX - room.side, 0, chamberZ0), height, 2, {})
	end
	if z1 > chamberZ1 then
		wall(folder, Vector3.new(nearX - room.side, 0, chamberZ1), Vector3.new(nearX - room.side, 0, z1), height, 2, {})
	end
	-- Glowing skirting and recessed ceiling lights.
	for _, z in { z0 + 0.1, z1 - 0.1 } do
		Shapes.box(folder, Vector3.new(x1 - x0, 0.4, 0.2), CFrame.new(cx, 1, z), { color = C.cyan, material = NEON })
	end
	for i = 1, lights do
		local lx = x0 + (x1 - x0) * (i - 0.5) / lights
		local lamp = Shapes.box(folder, Vector3.new(math.min(24, (x1 - x0) / lights - 6), 0.4, math.min(24, z1 - z0 - 10)), CFrame.new(lx, height - 0.2, cz), { color = C.lamp, material = NEON })
		local holder = Shapes.box(folder, Vector3.new(1, 1, 1), CFrame.new(lx, height - 6, cz), { color = C.white, transparency = 1 })
		local _ = lamp
		light(holder, "PointLight", 60, 1.1, Color3.fromRGB(235, 242, 255))
	end
	return folder
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
export type Handles = {
 setPodium: (rows: { any }) -> (), setKartDisplay: (slot: number, name: string?, kartId: string?, look: any?) -> (),
 setDeparture: (lit: boolean) -> (), celebrate: (place: number, character: Model) -> (),
 garagePrompt: ProximityPrompt, collectibles: { BasePart },
}

function LobbyBuilder.build(): Handles
 local old = Workspace:FindFirstChild("Lobby")
 if old then old:Destroy() end
 local practice = Workspace:FindFirstChild("PracticeTrack")
 if practice then practice:Destroy() end
 local lobby = Instance.new("Folder")
 lobby.Name = "Lobby"
 local shell = Instance.new("Folder")
 shell.Name = "Chamber"
 shell.Parent = lobby
 Shapes.box(shell, Vector3.new(HW * 2 + 8, 2, HD * 2 + 8), CFrame.new(W(0, -1, 0)), { color = C.floor, material = Enum.Material.Slate, collide = true, name = "Floor" })
 Shapes.box(shell, Vector3.new(HW * 2 + 8, 2, HD * 2 + 8), CFrame.new(W(0, HEIGHT + 1, 0)), { color = C.wall, collide = true })
 for _, side in { -1, 1 } do
  local openings = {}
  for _, room in LobbyLayout.Rooms do
   if room.side == side then table.insert(openings, { at = room.door.z - (O.z - HD), width = LobbyLayout.DoorWidth + 2, bottom = 0, top = LobbyLayout.DoorHeight + 1 }) end
  end
  wall(shell, W(side * HW, 0, -HD), W(side * HW, 0, HD), HEIGHT, WALL, openings)
 end
 wall(shell, W(-HW, 0, HD), W(HW, 0, HD), HEIGHT, WALL, {})
 wall(shell, W(-HW, 0, -HD), W(HW, 0, -HD), HEIGHT, WALL, {
  { at = HW - 54, width = 18, bottom = 0, top = 15 }, { at = HW + 54, width = 18, bottom = 0, top = 15 },
 })
 -- Recessed white fixtures, matte trims, and restrained local illumination.
 for _, x in { -38, 0, 38 } do
  for _, z in { -40, 35 } do
   Shapes.roundedBox(shell, Vector3.new(18, 0.5, 5), 0.7, CFrame.new(W(x, HEIGHT - 0.3, z)), { color = C.lamp })
   local lamp = Shapes.box(shell, Vector3.new(1, 1, 1), CFrame.new(W(x, HEIGHT - 3, z)), { color = C.white, transparency = 1 })
   light(lamp, "PointLight", 65, 0.7, Color3.fromRGB(255, 242, 222))
  end
 end
 for _, side in { -1, 1 } do
  for _, z in { -60, -5, 42 } do
   Shapes.capsule(shell, 4, HEIGHT, CFrame.new(W(side * (HW - 2), HEIGHT / 2, z)), { color = C.wallLight })
   wallPanel(shell, facing(W(side * (HW - 0.5), 26, z + 14), Vector3.new(-side, 0, 0)), 18, 16)
  end
 end
 local sc = LobbyLayout.Screen
 local screenCf = facing(Vector3.new(sc.center.x, sc.center.y, sc.center.z + 2.6), Vector3.zAxis)
 Shapes.roundedBox(shell, Vector3.new(sc.width + 4, sc.height + 4, 1), 1.3, screenCf * CFrame.new(0, 0, 0.8), { color = C.steel })
 Shapes.box(shell, Vector3.new(sc.width, sc.height, 0.4), screenCf, { color = C.screen, name = "VoteScreen" })
 Shapes.box(shell, Vector3.new(66, 6, 0.4), facing(Vector3.new(0, 39, O.z - 75), Vector3.zAxis), { color = C.screen, name = "StatusBoard" })
 local departure = Instance.new("Folder")
 departure.Name = "Departure"
 departure.Parent = lobby
 for i, spot in LobbyLayout.DepartureDoors do
  local door = slidingDoor(departure, `DepartureDoor{i}`, facing(Vector3.new(spot.x, 0, spot.z), Vector3.zAxis), 16, 14, C.cyan)
  door:SetAttribute("Departure", true)
  door:SetAttribute("Lit", false)
 end
 -- Raised spawn deck, broad stairs and accessible side ramps.
 Shapes.box(shell, Vector3.new(HW * 2, DECK, 30), CFrame.new(W(0, DECK / 2, 63)), { color = C.floor, collide = true })
 for i = 1, 4 do
  Shapes.box(shell, Vector3.new(28, i * 2, 5), CFrame.new(W(0, i, 25.5 + i * 5)), { color = C.wallLight, collide = true })
 end
 for _, ramp in LobbyLayout.Ramps do
  for i = 1, 24 do
   local h = i * DECK / 24
   Shapes.box(shell, Vector3.new(12, h, 2.1), CFrame.new(ramp.from.x, h / 2, O.z + i * 2 - 1), { color = C.floor, collide = true })
  end
 end
 for _, side in { -1, 1 } do
  Shapes.box(shell, Vector3.new(10, 1, 114), CFrame.new(W(side * 63, DECK - 0.5, -9)), { color = C.floor, collide = true })
  railing(shell, W(side * 57, DECK, -66), W(side * 57, DECK, 48))
 end
 local spawn = Instance.new("SpawnLocation")
 spawn.Name = "LobbySpawn"
 spawn.Size = Vector3.new(12, 1, 10)
 spawn.CFrame = at(LobbyLayout.Spawn, 0.5)
 spawn.Anchored = true
 spawn.Neutral = true
 spawn.Transparency = 1
 spawn.Duration = 0
 spawn.Parent = shell
 local logo = Shapes.box(shell, Vector3.new(40, 7, 0.4), facing(W(0, 22, HD - 2.5), -Vector3.zAxis), { color = C.navy })
 text(logo, "KART HQ · RACE CLUB", C.white, 14)
 local pedestalCf = CFrame.new(W(0, 0, 7))
 local stepX, stepHeights = { 0, -10, 10 }, { 2.4, 1.6, 0.8 }
 for i = 1, 3 do
  rimDisc(shell, 8, stepHeights[i], pedestalCf * CFrame.new(stepX[i], 0, 0), C.wallLight, C.gold, 0.3)
 end
 for i, spot in LobbyLayout.VotePads do
  rimDisc(shell, 16, 0.25, at(spot), C.wallLight, rgb(LobbyLayout.PadColors[i]), 0.5)
  local sign = Shapes.box(shell, Vector3.new(18, 5, 0.3), facing(Vector3.new(spot.x, 5.5, spot.z - 9), Vector3.zAxis), { color = C.screen, name = `PadSign{i}` })
 end
 local displays = Instance.new("Folder")
 displays.Name = "KartDisplays"
 displays.Parent = lobby
 local displayYaw = { math.pi, math.pi, math.pi, math.pi / 2 }
 for _, spot in LobbyLayout.KartDisplays do rimDisc(shell, 12, 0.5, at(spot), C.navy, C.steel, 0.4) end
 local rooms = Instance.new("Folder")
 rooms.Name = "Rooms"
 rooms.Parent = lobby
 local roomFolders = {}
 for _, room in LobbyLayout.Rooms do
  local folder = roomShell(rooms, room, 24, 1)
  roomFolders[room.id] = folder
  local cf = facing(Vector3.new(room.door.x, 0, room.door.z), Vector3.new(-room.side, 0, 0))
  slidingDoor(folder, `Door_{room.id}`, cf, LobbyLayout.DoorWidth, LobbyLayout.DoorHeight, C.cyan)
  local sign = Shapes.box(folder, Vector3.new(18, 4, 0.4), cf * CFrame.new(0, 17, -2.5), { color = C.navy })
  text(sign, string.upper(room.name), C.white, 14)
 end
 local garage = LobbyLayout.roomById("garage")
 local g = roomFolders.garage
 local benchCf = CFrame.new(garage.box.min.x + 22, 0, garage.door.z)
 Shapes.roundedBox(g, Vector3.new(12, 4, 5), 0.6, benchCf * CFrame.new(0, 2, 0), { color = C.wallLight, collide = true })
 local garageSpot = Shapes.box(g, Vector3.one, benchCf * CFrame.new(0, 6, 0), { color = C.white, transparency = 1 })
 local garagePrompt = prompt(garageSpot, "Customize kart", "Garage")
 for i = 1, 5 do
  Shapes.pillar(g, 4, 1.5, CFrame.new(garage.box.min.x + 8, i * 1.5, garage.box.min.z + 9), { color = Color3.fromRGB(28, 28, 32), material = Enum.Material.SmoothPlastic })
 end
 local trophy = LobbyLayout.roomById("trophy")
 local podiumCf = CFrame.new(trophy.box.min.x + 22, 0, trophy.door.z) * CFrame.Angles(0, -math.pi / 2, 0)
 local podiumX, podiumH = { 0, -11, 11 }, { 3, 2, 1 }
 local podiumKarts = Instance.new("Folder")
 podiumKarts.Name = "PodiumKarts"
 podiumKarts.Parent = roomFolders.trophy
 for i = 1, 3 do rimDisc(roomFolders.trophy, 10, podiumH[i], podiumCf * CFrame.new(podiumX[i], 0, 0), C.wallLight, C.gold, 0.4) end
 local podiumSign = Shapes.box(roomFolders.trophy, Vector3.new(32, 5, 0.4), podiumCf * CFrame.new(0, 15, 9), { color = C.navy })
 local podiumText = text(podiumSign, "LAST RACE · NO RACES YET", C.white, 14)
 local party = LobbyLayout.roomById("party")
 for i = 1, 3 do
  local cf = CFrame.new(party.box.min.x + 20, 0, party.box.min.z + i * 14)
  Shapes.roundedBox(roomFolders.party, Vector3.new(16, 2, 5), 0.7, cf * CFrame.new(0, 1, 0), { color = C.wallLight, collide = true })
  Shapes.roundedBox(roomFolders.party, Vector3.new(16, 3, 1), 0.4, cf * CFrame.new(0, 3, 2), { color = C.wallLight, collide = true })
 end
 local tokens = {}
 local tokenFolder = Instance.new("Folder")
 tokenFolder.Name = "Tokens"
 tokenFolder.Parent = lobby
 for i, spot in LobbyLayout.Collectibles do
  local token = Shapes.tube(tokenFolder, 2.5, 0.6, at(spot, 1.5), { color = C.gold, material = Enum.Material.Metal, name = `Token{i}` })
  token:SetAttribute("Spin", 2)
  token:SetAttribute("TokenId", i)
  table.insert(tokens, token)
 end
 lobby.Parent = Workspace
	local function setKartDisplay(slot: number, name: string?, kartId: string?, look: any?)
		local existing = displays:FindFirstChild(`Slot{slot}`)
		if existing then
			existing:Destroy()
		end
		local spot = LobbyLayout.KartDisplays[slot]
		if not spot or not name then
			return
		end
		local kartCf = CFrame.new(spot.x, 1.3, spot.z) * CFrame.Angles(0, displayYaw[slot], 0)
		local kart = KartRig.build(kartId or Karts.Default, name, kartCf, displays, look)
		kart.Name = `Slot{slot}`
		kart.PrimaryPart.Anchored = true
		local tag = kart:FindFirstChild("NameTag")
		local label = tag and tag:FindFirstChildOfClass("TextLabel")
		if label then
			label.Text = name
		end
	end

	local function setPodium(rows: { any })
		podiumKarts:ClearAllChildren()
		local lines = {}
		for place = 1, math.min(3, #rows) do
			local row = rows[place]
			local kartCf = podiumCf * CFrame.new(podiumX[place], podiumH[place] + 0.1, 0)
			local kart = KartRig.build(row.kartId or Karts.Default, row.name, kartCf, podiumKarts, row.look)
			kart.PrimaryPart.Anchored = true
			table.insert(lines, `{place}. {row.name}`)
		end
		podiumText.Text = "🏆 LAST RACE\n" .. (if #lines > 0 then table.concat(lines, "   ") else "No races yet")
	end

	-- Departure doors light up (and open on clients) when a track is chosen.
	local function setDeparture(lit: boolean)
		for _, door in departure:GetChildren() do
			if door:GetAttribute("Departure") then
				door:SetAttribute("Lit", lit)
			end
		end
	end

	-- Top three players stand on the pedestals in the middle of the chamber,
	-- cheer, and get confetti.
	local function celebrate(place: number, character: Model)
		local h = stepHeights[place]
		if not h or not character.Parent then
			return
		end
		local spot = pedestalCf * CFrame.new(stepX[place], h + 3, 0) * CFrame.Angles(0, math.pi, 0)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.CFrame = spot
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			pcall(function()
				humanoid:PlayEmote(if place == 1 then "cheer" else "wave")
			end)
		end
		local burst = Shapes.box(lobby, Vector3.new(1, 1, 1), spot * CFrame.new(0, 12, 0), { color = C.white, transparency = 1 })
		local confetti = Instance.new("ParticleEmitter")
		confetti.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		confetti.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.pink),
			ColorSequenceKeypoint.new(0.33, C.gold),
			ColorSequenceKeypoint.new(0.66, C.cyan),
			ColorSequenceKeypoint.new(1, C.white),
		})
		confetti.Size = NumberSequence.new(0.6)
		confetti.Lifetime = NumberRange.new(2, 3)
		confetti.Speed = NumberRange.new(20, 30)
		confetti.SpreadAngle = Vector2.new(60, 60)
		confetti.Acceleration = Vector3.new(0, -20, 0)
		confetti.Rotation = NumberRange.new(0, 360)
		confetti.RotSpeed = NumberRange.new(-200, 200)
		confetti.Rate = 120
		confetti.Parent = burst
		task.delay(1.5, function()
			confetti.Enabled = false
		end)
		task.delay(5, function()
			burst:Destroy()
		end)
	end

	return {
		setPodium = setPodium,
		setKartDisplay = setKartDisplay,
		setDeparture = setDeparture,
		celebrate = celebrate,
		garagePrompt = garagePrompt,
		collectibles = tokens,
	}
end

return LobbyBuilder
