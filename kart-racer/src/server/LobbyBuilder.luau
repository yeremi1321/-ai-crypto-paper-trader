-- Builds the Kart HQ lobby from LobbyLayout: a tall indoor voting chamber.
--   * raised entrance platform with spawn, wide stairs and two gentle ramps
--   * central circular floor with celebration pedestals
--   * four vote pads (three tracks + Random) under a giant recessed screen
--   * status board above the screen, departure doors either side of it
--   * walkways along both side walls, rounded columns with lit panels
--   * labelled sliding doors to the garage, viewing lounge, trophy room,
--     practice circuit and party bays
--
-- The wall screen, status board, pad signs and lounge screen are blank parts
-- here; each client draws them from the round state (client/LobbyScreens), so
-- they stay in sync with the vote cards. Sliding doors are opened on clients.
-- Returns handles RoundService uses for karts, prompts and celebrations.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Karts = require(Shared.Karts)
local LobbyLayout = require(Shared.LobbyLayout)
local Track = require(Shared.Track)
local KartRig = require(ReplicatedStorage.Common.KartRig)
local Shapes = require(ReplicatedStorage.Common.Shapes)

local TrackBuilder = require(script.Parent.TrackBuilder)

local LobbyBuilder = {}

-- Optional looping ambience (a soft machinery hum). Upload a sound to Roblox
-- and paste its id here, e.g. "rbxassetid://123456". Empty = silent.
LobbyBuilder.AmbientSoundId = ""

local C = {
	wall = Color3.fromRGB(22, 30, 58),
	wallLight = Color3.fromRGB(34, 46, 86),
	panel = Color3.fromRGB(28, 38, 72),
	floor = Color3.fromRGB(26, 34, 62),
	floorLine = Color3.fromRGB(44, 64, 110),
	navy = Color3.fromRGB(16, 22, 44),
	cyan = Color3.fromRGB(0, 225, 255),
	cyanSoft = Color3.fromRGB(110, 230, 255),
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
local NEON = Enum.Material.Neon
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
	setPodium: (rows: { any }) -> (),
	setKartDisplay: (slot: number, name: string?, kartId: string?, look: any?) -> (),
	setDeparture: (lit: boolean) -> (),
	celebrate: (place: number, character: Model) -> (),
	garagePrompt: ProximityPrompt,
	spectatePrompt: ProximityPrompt,
	practicePrompt: ProximityPrompt,
	collectibles: { BasePart },
}

function LobbyBuilder.build(): Handles
	local old = Workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	local shell = Instance.new("Folder")
	shell.Name = "Chamber"
	shell.Parent = lobby
	local rooms = Instance.new("Folder")
	rooms.Name = "Rooms"
	rooms.Parent = lobby

	-----------------------------------------------------------------------
	-- Floor, walls, ceiling
	-----------------------------------------------------------------------
	Shapes.box(shell, Vector3.new(HW * 2 + WALL * 2, 1, HD * 2 + WALL * 2), CFrame.new(O.x, -0.5, O.z), { color = C.floor, collide = true, name = "Floor" })
	-- Tile grid on the main floor (stops at the entrance platform).
	local platform = LobbyLayout.Platform
	for x = -HW + 24, HW - 24, 24 do
		local z0, z1 = -HD, platform.min.z - O.z
		Shapes.box(shell, Vector3.new(0.4, 0.06, z1 - z0), CFrame.new(O.x + x, 0.03, O.z + (z0 + z1) / 2), { color = C.floorLine })
	end
	for z = -HD + 25, platform.min.z - O.z - 1, 25 do
		Shapes.box(shell, Vector3.new(HW * 2, 0.06, 0.4), CFrame.new(O.x, 0.03, O.z + z), { color = C.floorLine })
	end

	-- Side walls with door openings (under the walkways).
	local doorW, doorH = LobbyLayout.DoorWidth, LobbyLayout.DoorHeight
	for _, side in { -1, 1 } do
		local openings = {}
		for _, room in LobbyLayout.Rooms do
			if room.side == side then
				table.insert(openings, { at = room.door.z - (O.z - HD - WALL), width = doorW, bottom = 0, top = doorH })
			end
		end
		local x = side * (HW + WALL / 2)
		wall(shell, W(x, 0, -HD - WALL), W(x, 0, HD + WALL), HEIGHT, WALL, openings)
	end
	-- Back wall behind the entrance platform.
	wall(shell, W(-HW, 0, HD + WALL / 2), W(HW, 0, HD + WALL / 2), HEIGHT, WALL, {})
	-- Front wall: the recessed screen and the two departure doors.
	local screen = LobbyLayout.Screen
	local screenBottom = screen.center.y - screen.height / 2
	local frontOpenings: { Opening } = {
		{ at = HW, width = screen.width + 4, bottom = screenBottom - 2, top = screenBottom + screen.height + 2 },
	}
	local departW, departH = 22, 18
	for _, d in LobbyLayout.DepartureDoors do
		table.insert(frontOpenings, { at = d.x - (O.x - HW), width = departW, bottom = 0, top = departH })
	end
	wall(shell, W(-HW, 0, -HD - WALL / 2), W(HW, 0, -HD - WALL / 2), HEIGHT, WALL, frontOpenings)

	-- Ceiling with recessed light coffers.
	Shapes.box(shell, Vector3.new(HW * 2 + WALL * 2, 4, HD * 2 + WALL * 2), CFrame.new(O.x, HEIGHT + 2, O.z), { color = C.wall, collide = true, name = "Ceiling" })
	local cellX, cellZ = 60, 60
	for x = -HW, HW, cellX do
		Shapes.box(shell, Vector3.new(3, 3, HD * 2), CFrame.new(O.x + x, HEIGHT - 1.5, O.z), { color = C.wallLight })
	end
	for z = -HD, HD, cellZ do
		Shapes.box(shell, Vector3.new(HW * 2, 3, 3), CFrame.new(O.x, HEIGHT - 1.5, O.z + z), { color = C.wallLight })
	end
	for x = -HW + cellX / 2, HW, cellX do
		for z = -HD + cellZ / 2, HD, cellZ do
			Shapes.box(shell, Vector3.new(cellX - 16, 0.4, cellZ - 16), CFrame.new(O.x + x, HEIGHT - 0.2, O.z + z), { color = C.lamp, material = NEON })
		end
	end
	-- The coffers can't light a 110-stud room alone, so soft lamps hang lower.
	for _, x in { -70, 0, 70 } do
		for _, z in { -105, -30, 50 } do
			local holder = Shapes.box(shell, Vector3.new(1, 1, 1), CFrame.new(O.x + x, 52, O.z + z), { color = C.white, transparency = 1 })
			light(holder, "PointLight", 60, 1.15, Color3.fromRGB(235, 242, 255))
		end
	end

	-- Cyan cornice under the ceiling and skirting at the floor.
	for _, side in { -1, 1 } do
		Shapes.box(shell, Vector3.new(0.4, 0.8, HD * 2), CFrame.new(O.x + side * (HW - 0.2), HEIGHT - 6, O.z), { color = C.cyan, material = NEON })
		Shapes.box(shell, Vector3.new(HW * 2, 0.8, 0.4), CFrame.new(O.x, HEIGHT - 6, O.z + side * (HD - 0.2)), { color = C.cyan, material = NEON })
		Shapes.box(shell, Vector3.new(HW * 2, 0.5, 0.3), CFrame.new(O.x, 1, O.z + side * (HD - 0.15)), { color = C.cyan, material = NEON })
	end

	-- Beveled panels on the side walls above the walkways.
	for _, side in { -1, 1 } do
		local face = Vector3.new(-side, 0, 0)
		for z = -HD + 20, HD - 20, 26 do
			for _, y in { DECK + 22, DECK + 50 } do
				wallPanel(shell, facing(W(side * (HW - 0.3), y, z), face), 22, 22)
			end
		end
	end

	-----------------------------------------------------------------------
	-- Giant recessed voting screen, status board, departure doors
	-----------------------------------------------------------------------
	local sc = screen.center
	local recessBack = sc.z - screen.recess
	local ow, oh = screen.width + 4, screen.height + 4
	Shapes.box(shell, Vector3.new(ow + 4, oh + 4, 4), CFrame.new(sc.x, sc.y, recessBack - 2), { color = C.navy, collide = true })
	for _, sx in { -1, 1 } do
		Shapes.box(shell, Vector3.new(1, oh, screen.recess), CFrame.new(sc.x + sx * (ow / 2 - 0.5), sc.y, sc.z - screen.recess / 2), { color = C.wallLight })
	end
	for _, sy in { -1, 1 } do
		Shapes.box(shell, Vector3.new(ow, 1, screen.recess), CFrame.new(sc.x, sc.y + sy * (oh / 2 - 0.5), sc.z - screen.recess / 2), { color = C.wallLight })
	end
	local voteScreen = Shapes.box(shell, Vector3.new(screen.width, screen.height, 0.6), facing(Vector3.new(sc.x, sc.y, recessBack + 0.5), Vector3.zAxis), { color = C.screen, name = "VoteScreen" })
	local glow = Instance.new("SurfaceLight")
	glow.Face = Enum.NormalId.Front
	glow.Range = 40
	glow.Brightness = 0.8
	glow.Angle = 120
	glow.Color = C.cyanSoft
	glow.Parent = voteScreen
	-- Beveled frame with a glowing inner edge.
	local frameCf = facing(Vector3.new(sc.x, sc.y, sc.z + 0.6), Vector3.zAxis)
	for _, sx in { -1, 1 } do
		Shapes.box(shell, Vector3.new(4, oh + 8, 1.6), frameCf * CFrame.new(sx * (ow / 2 + 2), 0, 0), { color = C.wallLight })
		Shapes.box(shell, Vector3.new(0.5, oh, 0.4), frameCf * CFrame.new(sx * (ow / 2 + 0.2), 0, -0.6), { color = C.cyan, material = NEON })
	end
	for _, sy in { -1, 1 } do
		Shapes.box(shell, Vector3.new(ow + 8, 4, 1.6), frameCf * CFrame.new(0, sy * (oh / 2 + 2), 0), { color = C.wallLight })
		Shapes.box(shell, Vector3.new(ow, 0.5, 0.4), frameCf * CFrame.new(0, sy * (oh / 2 + 0.2), -0.6), { color = C.cyan, material = NEON })
	end

	local board = LobbyLayout.StatusBoard
	local boardCf = facing(Vector3.new(board.x, board.y, board.z + 0.8), Vector3.zAxis)
	Shapes.roundedBox(shell, Vector3.new(68, 15, 1.4), 2, boardCf * CFrame.new(0, 0, 0.4), { color = C.wallLight })
	Shapes.box(shell, Vector3.new(66, 13, 0.3), boardCf * CFrame.new(0, 0, -0.4), { color = C.cyan, material = NEON })
	Shapes.box(shell, Vector3.new(64, 11, 0.6), boardCf * CFrame.new(0, 0, -0.6), { color = C.screen, name = "StatusBoard" })

	local departure = Instance.new("Folder")
	departure.Name = "Departure"
	departure.Parent = lobby
	for i, d in LobbyLayout.DepartureDoors do
		local wallCf = facing(Vector3.new(d.x, 0, d.z - WALL / 2), Vector3.zAxis)
		local door = slidingDoor(departure, `DepartureDoor{i}`, wallCf, departW, departH, C.cyan)
		door:SetAttribute("Departure", true)
		door:SetAttribute("Lit", false)
		-- A short glowing tunnel behind the door (seen when it opens).
		local tunnelCf = facing(Vector3.new(d.x, 0, d.z - WALL - 8), Vector3.zAxis)
		Shapes.box(departure, Vector3.new(departW + 2, 1, 16), tunnelCf * CFrame.new(0, -0.5, 0), { color = C.navy, collide = true })
		Shapes.box(departure, Vector3.new(departW + 2, 1, 16), tunnelCf * CFrame.new(0, departH + 0.5, 0), { color = C.wall, collide = true })
		for _, sx in { -1, 1 } do
			Shapes.box(departure, Vector3.new(1, departH, 16), tunnelCf * CFrame.new(sx * (departW / 2 + 0.5), departH / 2, 0), { color = C.wall, collide = true })
			for k = 0, 3 do
				Shapes.box(departure, Vector3.new(0.3, departH - 4, 0.5), tunnelCf * CFrame.new(sx * departW / 2, departH / 2, -6 + k * 4), { color = C.cyan, material = NEON, name = "Glow" })
			end
		end
		local back = Shapes.box(departure, Vector3.new(departW + 2, departH, 1), tunnelCf * CFrame.new(0, departH / 2, 8.5), { color = C.navy, collide = true })
		text(back, "» TO THE TRACK »", C.cyan, 10)
		local tunnelLight = Shapes.box(departure, Vector3.new(1, 1, 1), tunnelCf * CFrame.new(0, departH - 3, 0), { color = C.white, transparency = 1 })
		light(tunnelLight, "PointLight", 18, 1, C.cyanSoft)
		local sign = Shapes.box(departure, Vector3.new(departW, 4, 0.6), facing(Vector3.new(d.x, departH + 4, d.z + 0.4), Vector3.zAxis), { color = C.navy, name = "DepartureSign" })
		text(sign, "DEPARTURES", C.cyan, 16)
	end

	-- Big columns flanking the screen.
	for _, sx in { -1, 1 } do
		column(shell, W(sx * 74, 0, -HD + 4), HEIGHT, Vector3.zAxis)
	end

	-- Kart display alcoves: under the screen and in the side walls.
	local displays = Instance.new("Folder")
	displays.Name = "KartDisplays"
	displays.Parent = lobby
	local displayYaw = {}
	for i, spot in LobbyLayout.KartDisplays do
		local face: Vector3
		if math.abs(spot.x - O.x) > HW - 10 then
			face = Vector3.new(if spot.x < O.x then 1 else -1, 0, 0)
		else
			face = Vector3.zAxis
		end
		displayYaw[i] = math.atan2(-face.X, -face.Z)
		local base = Vector3.new(spot.x, 0, spot.z)
		rimDisc(shell, 12, 1, CFrame.new(base), C.panel, C.cyan, 0.6)
		local wallGap = if face.Z ~= 0 then spot.z - (O.z - HD) else HW - math.abs(spot.x - O.x)
		local backCf = facing(base - face * (wallGap - 0.4) + Vector3.new(0, 6.5, 0), face)
		wallPanel(shell, backCf, 14, 12)
		Shapes.box(shell, Vector3.new(15, 0.8, 7), facing(base - face * 2.5 + Vector3.new(0, 13, 0), face), { color = C.wallLight })
		local lamp = Shapes.box(shell, Vector3.new(12, 0.2, 5), facing(base - face * 2.5 + Vector3.new(0, 12.55, 0), face), { color = C.lamp, material = NEON })
		light(lamp, "PointLight", 14, 1.2, Color3.fromRGB(220, 240, 255))
	end

	-----------------------------------------------------------------------
	-- Entrance platform, stairs, ramps, walkways, railings
	-----------------------------------------------------------------------
	local px0, px1, pz0, pz1 = platform.min.x, platform.max.x, platform.min.z, platform.max.z
	Shapes.box(shell, Vector3.new(px1 - px0, DECK, pz1 - pz0), CFrame.new((px0 + px1) / 2, DECK / 2, (pz0 + pz1) / 2), { color = C.wall, collide = true, name = "Platform" })
	Shapes.box(shell, Vector3.new(px1 - px0, 0.1, pz1 - pz0 - 2), CFrame.new((px0 + px1) / 2, DECK + 0.05, (pz0 + pz1) / 2 + 1), { color = C.floor, collide = true })
	Shapes.box(shell, Vector3.new(px1 - px0, 0.5, 0.3), CFrame.new((px0 + px1) / 2, DECK - 0.6, pz0 - 0.1), { color = C.cyan, material = NEON })
	-- Panels on the platform's front face, between the stairs and ramps.
	for _, x in { -45, 45, -96, 96 } do
		wallPanel(shell, facing(W(x, DECK / 2 - 1, pz0 - O.z - 0.3), -Vector3.zAxis), 12, 14)
	end

	local spawnSpot = LobbyLayout.Spawn
	rimDisc(shell, 18, DECK + 0.25, CFrame.new(spawnSpot.x, 0, spawnSpot.z), C.wallLight, C.cyan, 0.8)
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 0.5, 12)
	spawn.CFrame = at(spawnSpot, 0.6) -- facing -z: towards the screen
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = lobby
	-- The HQ logo on the back wall, behind spawn.
	local logo = Shapes.roundedBox(shell, Vector3.new(60, 18, 1.4), 3, facing(W(0, DECK + 26, HD - 0.8), -Vector3.zAxis), { color = C.wallLight })
	local logoFace = Shapes.box(shell, Vector3.new(56, 14, 0.4), facing(W(0, DECK + 26, HD - 1.6), -Vector3.zAxis), { color = C.navy })
	local _ = logo
	text(logoFace, "🏁 KART HQ 🏁", C.cyan, 10)

	-- Stairs: wide steps down to the main floor, with glowing nosings.
	local stairs = LobbyLayout.Stairs
	local steps = stairs.steps
	local run = (stairs.from.z - stairs.to.z) / steps
	local rise = DECK / steps
	for k = 1, steps - 1 do
		local top = DECK - rise * k
		local zFar = stairs.from.z - run * (k - 1)
		local zNear = stairs.from.z - run * k
		Shapes.box(shell, Vector3.new(stairs.width, top, zFar - zNear), CFrame.new(stairs.from.x, top / 2, (zFar + zNear) / 2), { color = if k % 2 == 0 then C.wall else C.panel, collide = true })
		Shapes.box(shell, Vector3.new(stairs.width - 1, 0.12, 0.4), CFrame.new(stairs.from.x, top + 0.04, zNear + 0.3), { color = C.cyanSoft, material = NEON })
	end
	for _, sx in { -1, 1 } do
		local x = stairs.from.x + sx * (stairs.width / 2 + 0.5)
		railing(shell, Vector3.new(x, DECK, stairs.from.z), Vector3.new(x, 0, stairs.to.z + run))
	end

	-- Accessible ramps either side of the stairs (wedges: high end at +z).
	for _, ramp in LobbyLayout.Ramps do
		local length = ramp.from.z - ramp.to.z
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Ramp"
		wedge.Anchored = true
		wedge.Size = Vector3.new(ramp.width, DECK, length)
		wedge.CFrame = CFrame.new(ramp.from.x, DECK / 2, (ramp.from.z + ramp.to.z) / 2)
		wedge.Color = C.panel
		wedge.Material = Enum.Material.SmoothPlastic
		wedge.TopSurface = Enum.SurfaceType.Smooth
		wedge.Parent = shell
		local slope = math.atan2(DECK, length)
		for _, sx in { -1, 1 } do
			local x = ramp.from.x + sx * (ramp.width / 2 + 0.5)
			railing(shell, Vector3.new(x, DECK, ramp.from.z), Vector3.new(x, 0, ramp.to.z))
			Shapes.box(shell, Vector3.new(0.5, 0.15, length / math.cos(slope)), CFrame.new(ramp.from.x + sx * (ramp.width / 2 - 1), DECK / 2 + 0.1, (ramp.from.z + ramp.to.z) / 2) * CFrame.Angles(-slope, 0, 0), { color = C.cyanSoft, material = NEON })
		end
	end

	-- Walkways along both side walls, joined to the platform.
	for _, walk in LobbyLayout.Walkways do
		local x0, x1, z0, z1 = walk.min.x, walk.max.x, walk.min.z, walk.max.z
		Shapes.box(shell, Vector3.new(x1 - x0, 2, z1 - z0), CFrame.new((x0 + x1) / 2, DECK - 1, (z0 + z1) / 2), { color = C.wall, collide = true, name = "Walkway" })
		Shapes.box(shell, Vector3.new(x1 - x0, 0.1, z1 - z0), CFrame.new((x0 + x1) / 2, DECK + 0.05, (z0 + z1) / 2), { color = C.floor, collide = true })
		local side = if x0 < O.x then -1 else 1
		local innerX = if side < 0 then x1 else x0
		Shapes.box(shell, Vector3.new(0.3, 0.5, z1 - z0), CFrame.new(innerX - side * 0.15, DECK - 1.2, (z0 + z1) / 2), { color = C.cyan, material = NEON })
		-- Railing along the inner edge, curving round at the far end.
		local r = 8
		local points = { Vector3.new(innerX, DECK, z1) }
		local corner = Vector3.new(innerX + side * r, DECK, z0 + r)
		for _, p in arc(corner, r, if side < 0 then 0 else math.pi, if side < 0 then -math.pi / 2 else math.pi * 1.5, 6) do
			table.insert(points, p)
		end
		table.insert(points, Vector3.new(if side < 0 then x0 else x1, DECK, z0))
		railPath(shell, points)
	end

	-- Platform edge railing, with gaps for the stairs, ramps and walkways.
	local edgeZ = pz0
	local gaps = { { stairs.from.x - stairs.width / 2 - 1, stairs.from.x + stairs.width / 2 + 1 } }
	for _, ramp in LobbyLayout.Ramps do
		table.insert(gaps, { ramp.from.x - ramp.width / 2 - 1, ramp.from.x + ramp.width / 2 + 1 })
	end
	table.sort(gaps, function(a, b)
		return a[1] < b[1]
	end)
	local walkInner = LobbyLayout.Walkways[1].max.x
	local cursor = walkInner
	for _, g in gaps do
		railing(shell, Vector3.new(cursor, DECK, edgeZ), Vector3.new(g[1], DECK, edgeZ))
		cursor = g[2]
	end
	railing(shell, Vector3.new(cursor, DECK, edgeZ), Vector3.new(LobbyLayout.Walkways[2].min.x, DECK, edgeZ))

	-- Columns along the walkway edges (they hold the walkways up).
	for _, side in { -1, 1 } do
		for _, z in { -128, -100, -40, 22, 90 } do
			local base = W(side * 99, 0, z)
			column(shell, base, HEIGHT, Vector3.new(-side, 0, 0))
			Shapes.box(shell, Vector3.new(6, 2, 4), CFrame.new(base + Vector3.new(side * 4, DECK - 1, 0)), { color = C.wallLight, collide = true })
		end
	end

	-- Racing banners hanging between the columns.
	local accents = { C.cyan, C.pink, C.gold }
	for i, z in { -70, -10, 56 } do
		for _, side in { -1, 1 } do
			banner(shell, W(side * 82, HEIGHT - 4, z), Vector3.new(0, 0, 1), accents[i])
		end
	end

	-----------------------------------------------------------------------
	-- Central floor, celebration pedestals, vote pads
	-----------------------------------------------------------------------
	local cf0 = LobbyLayout.CentralFloor
	local centerCf = CFrame.new(cf0.center.x, 0, cf0.center.z)
	local d = cf0.radius * 2
	rimDisc(shell, d, 0.1, centerCf, C.navy, C.cyan, 1.2)
	rimDisc(shell, d - 16, 0.2, centerCf, C.wallLight, C.floorLine, 1)
	rimDisc(shell, 52, 0.3, centerCf, C.navy, C.cyan, 1)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local mid = (cf0.radius - 8 + 26) / 2
		Shapes.box(shell, Vector3.new(0.6, 0.08, cf0.radius - 8 - 26 - 2), centerCf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.22, mid), { color = C.cyanSoft, material = NEON })
	end
	-- Checker-flag inlay in the middle.
	for i = 0, 15 do
		local col, row = i % 4, math.floor(i / 4)
		Shapes.box(shell, Vector3.new(3, 0.1, 3), centerCf * CFrame.new(-4.5 + col * 3, 0.33, -4.5 + row * 3), { color = if (col + row) % 2 == 0 then C.white else C.navy })
	end

	local stepHeights = { 6, 4, 3 }
	local stepX = { 0, -12, 12 }
	local pedestalCf = centerCf * CFrame.new(0, 0, 12)
	local stepColors = { C.gold, C.silver, C.bronze }
	for place = 1, 3 do
		local h = stepHeights[place]
		local base = pedestalCf * CFrame.new(stepX[place], 0, 0)
		Shapes.pillar(shell, 10.6, 0.5, base * CFrame.new(0, h - 0.4, 0), { color = C.cyan, material = NEON })
		Shapes.pillar(shell, 10, h, base * CFrame.new(0, h / 2, 0), { color = stepColors[place], collide = true })
	end

	for i, pad in LobbyLayout.VotePads do
		local color = rgb(LobbyLayout.PadColors[i])
		local padCf = at(pad)
		rimDisc(shell, LobbyLayout.VotePadSize, 0.45, padCf, C.navy, color, 1.2)
		Shapes.disc(shell, LobbyLayout.VotePadSize - 8, 0.1, padCf * CFrame.new(0, 0.5, 0), { color = color, material = NEON, name = `VotePad{i}` }).Transparency = 0.5
		-- A sign behind each pad; clients draw the track name and votes on it.
		local signCf = facing(Vector3.new(pad.x, 9, pad.z - 14), Vector3.zAxis)
		Shapes.pillar(shell, 1.2, 9, CFrame.new(pad.x, 4.5, pad.z - 14.6), { color = C.steel })
		Shapes.roundedBox(shell, Vector3.new(18, 7, 0.8), 1.2, signCf * CFrame.new(0, 0, 0.5), { color = color })
		Shapes.box(shell, Vector3.new(16.6, 5.6, 0.3), signCf, { color = C.screen, name = `PadSign{i}` })
	end

	-----------------------------------------------------------------------
	-- Side rooms and their doors
	-----------------------------------------------------------------------
	local roomFolders = {}
	for _, room in LobbyLayout.Rooms do
		local isHall = room.id == "practice"
		local folder = roomShell(rooms, room, if isHall then 50 else 26, if isHall then 3 else 1)
		roomFolders[room.id] = folder
		local into = Vector3.new(-room.side, 0, 0) -- from the door into the chamber
		local doorCf = facing(Vector3.new(room.door.x + room.side * WALL / 2, 0, room.door.z), into)
		slidingDoor(folder, `Door_{room.id}`, doorCf, doorW, doorH, C.cyan)
		-- Name sign hanging under the walkway edge, facing the chamber.
		local walkEdge = O.x + room.side * (HW - 16)
		local sign = Shapes.box(folder, Vector3.new(20, 3.6, 0.5), facing(Vector3.new(walkEdge + into.X * 0.4, DECK - 4, room.door.z), into), { color = C.navy, name = "Sign" })
		text(sign, `{room.icon} {string.upper(room.name)}`, C.cyan, 16)
		Shapes.box(folder, Vector3.new(20.6, 0.3, 0.6), facing(Vector3.new(walkEdge + into.X * 0.2, DECK - 6, room.door.z), into), { color = C.cyan, material = NEON })
		-- Floor arrow from the central floor to the door.
		local arrowCf = facing(Vector3.new(room.door.x - room.side * 14, 0.06, room.door.z), -into)
		for k = 0, 2 do
			Shapes.box(folder, Vector3.new(4, 0.08, 1), arrowCf * CFrame.new(0, 0, -k * 3) * CFrame.Angles(0, math.rad(35), 0) * CFrame.new(-1.6, 0, 0), { color = C.cyanSoft, material = NEON })
			Shapes.box(folder, Vector3.new(4, 0.08, 1), arrowCf * CFrame.new(0, 0, -k * 3) * CFrame.Angles(0, math.rad(-35), 0) * CFrame.new(1.6, 0, 0), { color = C.cyanSoft, material = NEON })
		end
	end

	-- Garage: kart lifts, tool wall, tyre stacks and the customise bench.
	local garage = assert(LobbyLayout.roomById("garage"))
	local gFolder = roomFolders.garage
	local gb = garage.box
	for _, z in { gb.min.z + 22, gb.max.z - 22 } do
		local liftCf = CFrame.new(gb.min.x + 34, 0, z)
		Shapes.box(gFolder, Vector3.new(16, 1, 10), liftCf * CFrame.new(0, 3, 0), { color = C.steel, collide = true })
		for _, sx in { -1, 1 } do
			Shapes.box(gFolder, Vector3.new(1.4, 12, 1.4), liftCf * CFrame.new(sx * 9, 6, 0), { color = C.gold })
		end
		Shapes.box(gFolder, Vector3.new(16.4, 0.3, 0.4), liftCf * CFrame.new(0, 3.6, -5.1), { color = C.cyan, material = NEON })
	end
	local toolWall = Shapes.box(gFolder, Vector3.new(0.4, 12, 40), CFrame.new(gb.min.x + 0.3, 9, (gb.min.z + gb.max.z) / 2), { color = C.wallLight })
	local _ = toolWall
	local toolColors = { C.pink, C.gold, C.cyan, C.silver }
	for i = 0, 11 do
		local tz = gb.min.z + 30 + (i % 6) * 5
		local ty = 6 + math.floor(i / 6) * 5
		Shapes.box(gFolder, Vector3.new(0.6, 3.5, 0.8), CFrame.new(gb.min.x + 0.8, ty, tz) * CFrame.Angles(math.rad((i % 3 - 1) * 20), 0, 0), { color = toolColors[i % 4 + 1] })
	end
	for _, spot in { { gb.max.x - 8, gb.min.z + 6 }, { gb.max.x - 8, gb.max.z - 6 }, { gb.min.x + 8, gb.max.z - 6 } } do
		for k = 0, 2 do
			Shapes.pillar(gFolder, 5, 1.6, CFrame.new(spot[1], 0.8 + k * 1.7, spot[2]), { color = Color3.fromRGB(30, 30, 36), collide = true })
			Shapes.pillar(gFolder, 2.6, 1.7, CFrame.new(spot[1], 0.8 + k * 1.7, spot[2]), { color = C.steel })
		end
	end
	local benchCf = CFrame.new(garage.door.x - 16, 0, garage.door.z + 14)
	Shapes.roundedBox(gFolder, Vector3.new(12, 3.6, 5), 1, benchCf * CFrame.new(0, 1.8, 0), { color = C.wallLight, collide = true })
	Shapes.box(gFolder, Vector3.new(12.2, 0.3, 5.2), benchCf * CFrame.new(0, 3.7, 0), { color = C.cyan, material = NEON })
	local garageSpot = Shapes.box(gFolder, Vector3.new(3, 3, 3), benchCf * CFrame.new(0, 5, 0), { color = C.white, transparency = 1, name = "GaragePrompt" })
	local garagePrompt = prompt(garageSpot, "Customize kart", "Garage")
	local gSign = Shapes.box(gFolder, Vector3.new(30, 6, 0.4), facing(Vector3.new(gb.min.x + 0.7, 19, (gb.min.z + gb.max.z) / 2), Vector3.xAxis), { color = C.navy })
	text(gSign, "🔧 GARAGE", C.gold, 14)

	-- Viewing lounge: big screen and sofas.
	local lounge = assert(LobbyLayout.roomById("lounge"))
	local lFolder = roomFolders.lounge
	local lb = lounge.box
	local lz = (lb.min.z + lb.max.z) / 2
	Shapes.box(lFolder, Vector3.new(1.4, 25, 46), CFrame.new(lb.min.x + 1, 13, lz), { color = C.wallLight })
	Shapes.box(lFolder, Vector3.new(0.3, 23, 44), CFrame.new(lb.min.x + 1.8, 13, lz), { color = C.cyan, material = NEON })
	Shapes.box(lFolder, Vector3.new(42, 21, 0.6), facing(Vector3.new(lb.min.x + 2.1, 13, lz), Vector3.xAxis), { color = C.screen, name = "LoungeScreen" })
	for i, x in { lb.min.x + 36, lb.min.x + 60 } do
		for _, sz in { -1, 1 } do
			local sofaCf = CFrame.new(x, 0, lz + sz * 11) * CFrame.Angles(0, math.rad(90), 0)
			Shapes.roundedBox(lFolder, Vector3.new(18, 2.4, 6), 1.2, sofaCf * CFrame.new(0, 1.2, 0), { color = if i == 1 then C.pink else C.wallLight, collide = true })
			Shapes.roundedBox(lFolder, Vector3.new(18, 4, 1.6), 0.8, sofaCf * CFrame.new(0, 3.2, 2.6), { color = if i == 1 then C.pink else C.wallLight, collide = true })
			for k = -1, 1 do
				Shapes.ellipsoid(lFolder, Vector3.new(5, 1.4, 4.2), sofaCf * CFrame.new(k * 5.8, 2.8, -0.2), { color = C.white })
			end
		end
	end
	local watchSpot = Shapes.box(lFolder, Vector3.new(3, 3, 3), CFrame.new(lb.min.x + 48, 3, lz), { color = C.white, transparency = 1, name = "WatchPrompt" })
	local spectatePrompt = prompt(watchSpot, "Watch race", "Viewing lounge")

	-- Trophy room: podium for the last race's top three, trophy shelves.
	local trophy = assert(LobbyLayout.roomById("trophy"))
	local tFolder = roomFolders.trophy
	local tb = trophy.box
	local tz = (tb.min.z + tb.max.z) / 2
	local podiumCf = CFrame.new(tb.min.x + 30, 0, tz) * CFrame.Angles(0, math.rad(-90), 0) -- faces the door (+x)
	local podiumX = { 0, -11, 11 }
	local podiumH = { 7, 4.5, 2.5 }
	for place = 1, 3 do
		local h = podiumH[place]
		Shapes.roundedBox(tFolder, Vector3.new(10, h, 10), 1.5, podiumCf * CFrame.new(podiumX[place], h / 2, 0), { color = stepColors[place], collide = true })
		Shapes.box(tFolder, Vector3.new(10.2, 0.3, 0.3), podiumCf * CFrame.new(podiumX[place], h - 0.3, -5.05), { color = C.cyan, material = NEON })
	end
	local podiumKarts = Instance.new("Folder")
	podiumKarts.Name = "PodiumKarts"
	podiumKarts.Parent = tFolder
	local podiumSign = Shapes.box(tFolder, Vector3.new(32, 8, 0.4), facing(Vector3.new(tb.min.x + 0.7, 19, tz), Vector3.xAxis), { color = C.navy })
	local podiumText = text(podiumSign, "🏆 LAST RACE\nNo races yet", C.gold, 12)
	for _, sz in { -1, 1 } do
		local shelfZ = if sz < 0 then tb.min.z + 2 else tb.max.z - 2
		for _, y in { 6, 12 } do
			Shapes.box(tFolder, Vector3.new(60, 0.8, 3), CFrame.new(tb.min.x + 50, y, shelfZ), { color = C.wallLight, collide = true })
			Shapes.box(tFolder, Vector3.new(60, 0.2, 0.2), CFrame.new(tb.min.x + 50, y - 0.5, shelfZ - sz * 1.5), { color = C.cyan, material = NEON })
			for k = 0, 4 do
				local cup = CFrame.new(tb.min.x + 26 + k * 12, y + 0.4, shelfZ)
				local color = ({ C.gold, C.silver, C.bronze })[(k + y) % 3 + 1]
				Shapes.pillar(tFolder, 1.6, 0.8, cup * CFrame.new(0, 0.4, 0), { color = C.navy })
				Shapes.pillar(tFolder, 0.5, 1.2, cup * CFrame.new(0, 1.4, 0), { color = color })
				Shapes.ellipsoid(tFolder, Vector3.new(2, 2, 2), cup * CFrame.new(0, 2.8, 0), { color = color, reflectance = 0.2 })
				Shapes.tube(tFolder, 0.9, 2.8, cup * CFrame.new(0, 3, 0), { color = color })
			end
		end
	end

	-- Party bays: three hangout booths with couches and coloured light.
	local party = assert(LobbyLayout.roomById("party"))
	local pFolder = roomFolders.party
	local pb = party.box
	local bayColors = { C.pink, C.cyan, C.gold }
	local bayDepth = (pb.max.z - pb.min.z) / 3
	for i = 1, 3 do
		local bz = pb.min.z + bayDepth * (i - 0.5)
		local bayCf = CFrame.new(pb.max.x - 20, 0, bz)
		if i < 3 then
			Shapes.box(pFolder, Vector3.new(26, 10, 1), CFrame.new(pb.max.x - 13, 5, pb.min.z + bayDepth * i), { color = C.wallLight, collide = true })
		end
		Shapes.roundedBox(pFolder, Vector3.new(5, 2.4, bayDepth - 6), 1.2, bayCf * CFrame.new(10, 1.2, 0), { color = bayColors[i], collide = true })
		Shapes.roundedBox(pFolder, Vector3.new(1.6, 4, bayDepth - 6), 0.8, bayCf * CFrame.new(12.4, 3.2, 0), { color = bayColors[i], collide = true })
		Shapes.pillar(pFolder, 7, 0.6, bayCf * CFrame.new(2, 3, 0), { color = C.white, collide = true })
		Shapes.pillar(pFolder, 1.2, 3, bayCf * CFrame.new(2, 1.5, 0), { color = C.steel })
		Shapes.box(pFolder, Vector3.new(0.3, 0.6, bayDepth - 4), CFrame.new(pb.max.x - 0.4, 9, bz), { color = bayColors[i], material = NEON })
		local baySign = Shapes.box(pFolder, Vector3.new(10, 3, 0.4), facing(Vector3.new(pb.max.x - 0.8, 13, bz), -Vector3.xAxis), { color = C.navy })
		text(baySign, `BAY {i}`, bayColors[i], 14)
	end
	local partySign = Shapes.box(pFolder, Vector3.new(28, 5, 0.4), facing(Vector3.new(pb.min.x + 30, 20, pb.min.z + 0.8), Vector3.zAxis), { color = C.navy })
	text(partySign, "🎉 PARTY BAYS · hang out with your crew", C.pink, 12)

	-- Practice circuit hall: track, drift circle, boost tunnel.
	local area = LobbyLayout.PracticeArea
	local hFolder = roomFolders.practice
	Shapes.box(hFolder, Vector3.new(area.max.x - area.min.x, 0.2, area.max.z - area.min.z), CFrame.new((area.min.x + area.max.x) / 2, 0.05, (area.min.z + area.max.z) / 2), { color = C.navy, collide = true })
	local _, practice = TrackBuilder.build(LobbyLayout.PracticeTrack.id, { folderName = "PracticeTrack", ground = false, scenery = false })
	local drift = LobbyLayout.DriftCircle
	rimDisc(hFolder, drift.radius * 2, 0.3, at(drift.center), C.wallLight, C.cyan, 1.5)
	rimDisc(hFolder, 10, 0.4, at(drift.center), C.navy, C.pink, 1)
	local driftSign = Shapes.box(hFolder, Vector3.new(16, 5, 0.5), facing(Vector3.new(drift.center.x, 7, drift.center.z), Vector3.zAxis), { color = C.navy })
	text(driftSign, "DRIFT CIRCLE · hold drift and go round!", C.cyan, 12)
	local padDistances = {}
	for _, pad in Track.pads(practice) do
		table.insert(padDistances, pad.distance)
	end
	if #padDistances > 0 then
		local from, to = math.min(table.unpack(padDistances)) - 20, math.max(table.unpack(padDistances)) + 20
		for dist = from, to, 8 do
			local p, tan = Track.at(practice, dist)
			-- Arches are built across the local x/y plane, so facing along the road spans it.
			local archCf = CFrame.lookAt(Vector3.new(p.x, p.y, p.z), Vector3.new(p.x + tan.x, p.y, p.z + tan.z))
			local ring = math.floor(dist / 8) % 2
			Shapes.arch(hFolder, LobbyLayout.PracticeTrack.width + 6, 2, 3, archCf, { color = if ring == 0 then C.cyan else C.pink, material = NEON }, 12)
		end
	end
	local ps = LobbyLayout.PracticeStart
	local practiceSpot = Shapes.box(hFolder, Vector3.new(3, 3, 3), at(ps, 3), { color = C.white, transparency = 1, name = "PracticePrompt" })
	local practicePrompt = prompt(practiceSpot, "Drive practice kart", "Practice circuit")
	local pKiosk = Shapes.roundedBox(hFolder, Vector3.new(3, 5, 6), 1, at(ps, 2.5) * CFrame.new(4, 0, 0), { color = C.wallLight, collide = true })
	local _ = pKiosk
	local pSign = Shapes.box(hFolder, Vector3.new(14, 4, 0.4), facing(Vector3.new(ps.x + 5.8, 8, ps.z), -Vector3.xAxis), { color = C.navy })
	text(pSign, "🏁 PRACTICE · press E to drive", C.cyan, 14)

	-----------------------------------------------------------------------
	-- Hidden golden tokens, ambience
	-----------------------------------------------------------------------
	local tokens = {}
	local tokenFolder = Instance.new("Folder")
	tokenFolder.Name = "Tokens"
	tokenFolder.Parent = lobby
	for i, spot in LobbyLayout.Collectibles do
		local token = Shapes.tube(tokenFolder, 4, 0.8, at(spot, 1.5), { color = C.gold, material = NEON, name = `Token{i}` })
		token:SetAttribute("Spin", 2)
		token:SetAttribute("TokenId", i)
		table.insert(tokens, token)
	end

	if LobbyBuilder.AmbientSoundId ~= "" then
		local hum = Shapes.box(lobby, Vector3.new(1, 1, 1), at(O, 30), { color = C.white, transparency = 1, name = "Ambience" })
		local sound = Instance.new("Sound")
		sound.SoundId = LobbyBuilder.AmbientSoundId
		sound.Looped = true
		sound.Volume = 0.25
		sound.RollOffMaxDistance = 400
		sound.Parent = hum
		sound:Play()
	end

	lobby.Parent = Workspace

	-----------------------------------------------------------------------
	-- Handles
	-----------------------------------------------------------------------
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
		spectatePrompt = spectatePrompt,
		practicePrompt = practicePrompt,
		collectibles = tokens,
	}
end

return LobbyBuilder
