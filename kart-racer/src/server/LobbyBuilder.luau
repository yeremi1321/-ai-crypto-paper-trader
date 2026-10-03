-- Builds the Kart Carnival lobby from LobbyLayout: spawn plaza, status board,
-- map voting pads with miniature track displays, ready arch, garage with kart
-- display pedestals, podium, spectator screen, photo spot, Ferris wheel,
-- practice loop (drift circle, jump ramp, boost tunnel) and hidden tokens.
-- Returns handles RoundService uses to update signs and displays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Karts = require(Shared.Karts)
local LobbyLayout = require(Shared.LobbyLayout)
local Track = require(Shared.Track)
local Tracks = require(Shared.Tracks)
local KartRig = require(ReplicatedStorage.Common.KartRig)
local Shapes = require(ReplicatedStorage.Common.Shapes)

local TrackBuilder = require(script.Parent.TrackBuilder)

local LobbyBuilder = {}

local PALETTE = {
	pink = Color3.fromRGB(255, 95, 140),
	yellow = Color3.fromRGB(255, 205, 60),
	sky = Color3.fromRGB(90, 190, 255),
	mint = Color3.fromRGB(110, 220, 170),
	purple = Color3.fromRGB(160, 110, 240),
	white = Color3.fromRGB(250, 250, 252),
	cream = Color3.fromRGB(255, 240, 215),
	grass = Color3.fromRGB(120, 200, 110),
	tile = Color3.fromRGB(235, 225, 210),
	dark = Color3.fromRGB(40, 42, 56),
	gold = Color3.fromRGB(255, 200, 40),
}
local PAD_COLORS = { PALETTE.pink, PALETTE.sky, PALETTE.mint }

local function cf(spot: LobbyLayout.Spot, y: number?): CFrame
	return CFrame.new(spot.x, (y or 0) + spot.y, spot.z)
end

local function facing(spot: LobbyLayout.Spot, target: LobbyLayout.Spot, y: number): CFrame
	local from = Vector3.new(spot.x, y, spot.z)
	return CFrame.lookAt(from, Vector3.new(target.x, y, target.z))
end

-- A sign with a SurfaceGui on its front. Returns the title and body labels.
local function sign(parent: Instance, size: Vector3, at: CFrame, color: Color3, title: string): (TextLabel, TextLabel)
	local parts = Shapes.roundedBox(parent, size, 1.2, at, { color = color, collide = true })
	local face = Shapes.box(parent, Vector3.new(size.X - 2, size.Y - 2, 0.2), at * CFrame.new(0, 0, -size.Z / 2 - 0.1), { color = PALETTE.dark })
	local _ = parts
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Parent = face
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.fromScale(1, 0.32)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = PALETTE.yellow
	titleLabel.Text = title
	titleLabel.Parent = gui
	local body = Instance.new("TextLabel")
	body.Position = UDim2.fromScale(0.04, 0.34)
	body.Size = UDim2.fromScale(0.92, 0.62)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.FredokaOne
	body.TextScaled = true
	body.TextWrapped = true
	body.TextColor3 = PALETTE.white
	body.Text = ""
	body.Parent = gui
	return titleLabel, body
end

local function prompt(parent: BasePart, action: string, object: string, key: Enum.KeyCode?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = key or Enum.KeyCode.E
	p.MaxActivationDistance = 16
	p.RequiresLineOfSight = false
	p.HoldDuration = 0.15
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------
-- Decorations
---------------------------------------------------------------------------
local function balloonCluster(parent: Instance, at: CFrame)
	local colors = { PALETTE.pink, PALETTE.yellow, PALETTE.sky, PALETTE.mint, PALETTE.purple }
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		local offset = Vector3.new(math.cos(a) * 2.2, 14 + (i % 2) * 2.5, math.sin(a) * 2.2)
		Shapes.ellipsoid(parent, Vector3.new(3.4, 4.2, 3.4), at + offset, { color = colors[i], reflectance = 0.15 })
		Shapes.box(parent, Vector3.new(0.08, offset.Y - 2, 0.08), at + Vector3.new(offset.X / 2, (offset.Y - 2) / 2, offset.Z / 2), { color = PALETTE.white })
	end
end

local function tent(parent: Instance, at: CFrame, color: Color3, size: number)
	local s = size
	Shapes.pillar(parent, 16 * s, 8 * s, at * CFrame.new(0, 4 * s, 0), { color = PALETTE.cream, collide = true })
	for i = 0, 3 do
		local d = (16 - i * 3.6) * s
		Shapes.pillar(parent, d, 2 * s, at * CFrame.new(0, (9 + i * 2) * s, 0), { color = if i % 2 == 0 then color else PALETTE.white })
	end
	Shapes.ball(parent, 1.6 * s, at * CFrame.new(0, 17.4 * s, 0), { color = PALETTE.yellow })
	Shapes.box(parent, Vector3.new(0.2, 4 * s, 3 * s), at * CFrame.new(0, 20 * s, 1.5 * s), { color = color })
end

local function stringLights(parent: Instance, a: Vector3, b: Vector3)
	local colors = { PALETTE.yellow, PALETTE.pink, PALETTE.sky, PALETTE.mint }
	local n = math.floor((b - a).Magnitude / 4)
	for i = 0, n do
		local t = i / n
		local sag = math.sin(t * math.pi) * 3
		Shapes.ball(parent, 0.9, CFrame.new(a:Lerp(b, t) - Vector3.new(0, sag, 0)), { color = colors[i % #colors + 1], material = Enum.Material.Neon })
	end
end

local function ferrisWheel(parent: Instance, spot: LobbyLayout.Spot)
	local base = cf(spot) * CFrame.Angles(0, math.rad(30), 0)
	for _, side in { -1, 1 } do
		Shapes.box(parent, Vector3.new(2, 48, 2), base * CFrame.new(side * 14, 22, -6) * CFrame.Angles(0, 0, math.rad(side * -16)), { color = PALETTE.white, collide = true })
		Shapes.box(parent, Vector3.new(2, 48, 2), base * CFrame.new(side * 14, 22, 6) * CFrame.Angles(0, 0, math.rad(side * -16)), { color = PALETTE.white, collide = true })
	end
	-- The wheel turns on each client (Main.client spins models with a "Spin" attribute).
	local wheel = Instance.new("Model")
	wheel.Name = "FerrisWheel"
	local hubCf = base * CFrame.new(0, 44, 0)
	local hub = Shapes.tube(wheel, 5, 14, hubCf * CFrame.Angles(0, math.rad(90), 0), { color = PALETTE.yellow })
	wheel.PrimaryPart = hub
	local radius = 34
	local cabins = 10
	for i = 0, 35 do
		local a = i / 36 * math.pi * 2
		Shapes.ball(wheel, 1.4, hubCf * CFrame.new(math.cos(a) * radius, math.sin(a) * radius, 0), { color = PALETTE.pink, material = Enum.Material.Neon })
	end
	for i = 0, cabins - 1 do
		local a = i / cabins * math.pi * 2
		local p = Vector3.new(math.cos(a) * radius, math.sin(a) * radius, 0)
		Shapes.box(wheel, Vector3.new(0.8, radius, 0.8), hubCf * CFrame.new(p / 2) * CFrame.Angles(0, 0, a + math.pi / 2), { color = PALETTE.white })
		local colors = { PALETTE.pink, PALETTE.sky, PALETTE.mint, PALETTE.purple, PALETTE.yellow }
		Shapes.ellipsoid(wheel, Vector3.new(6, 5, 5), hubCf * CFrame.new(p - Vector3.new(0, 3, 0)), { color = colors[i % #colors + 1] })
	end
	wheel:SetAttribute("Spin", 0.12)
	wheel.Parent = parent
end

-- Little themed model for each track on the voting pads.
local function miniature(parent: Instance, trackId: string, at: CFrame)
	local def = Tracks.get(trackId)
	local theme = Tracks.Themes[def.theme]
	local function c(t: { number }): Color3
		return Color3.fromRGB(t[1], t[2], t[3])
	end
	local folder = Instance.new("Model")
	folder.Name = `Mini_{trackId}`
	Shapes.disc(folder, 14, 1, at * CFrame.new(0, 0.5, 0), { color = c(theme.ground) })
	-- A loop of road on the base.
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		Shapes.box(folder, Vector3.new(2.6, 0.3, 2.4), at * CFrame.new(math.cos(a) * 4.5, 1.1, math.sin(a) * 4.5) * CFrame.Angles(0, -a, 0), { color = c(theme.road) })
	end
	if def.theme == "sunny" then
		Shapes.pillar(folder, 0.8, 4, at * CFrame.new(0, 3, 0), { color = Color3.fromRGB(140, 95, 60) })
		Shapes.ball(folder, 4, at * CFrame.new(0, 5.6, 0), { color = Color3.fromRGB(90, 180, 80) })
	elseif def.theme == "canyon" then
		for i, w in { 6, 4.6, 3.2 } do
			Shapes.pillar(folder, w, 1.4, at * CFrame.new(0, 1.2 + i * 1.4, 0), { color = c(theme.wall):Lerp(Color3.new(1, 1, 1), i * 0.08) })
		end
	elseif def.theme == "neon" then
		for i, h in { 6, 9, 4.5 } do
			local x = (i - 2) * 2
			Shapes.box(folder, Vector3.new(1.6, h, 1.6), at * CFrame.new(x, 1 + h / 2, 0), { color = Color3.fromRGB(30, 26, 50) })
			Shapes.box(folder, Vector3.new(1.7, 0.3, 1.7), at * CFrame.new(x, 1 + h * 0.7, 0), { color = c(theme.accent), material = Enum.Material.Neon })
		end
	elseif def.theme == "toyroom" then
		-- A wobbly tower of toy blocks and a ball.
		local colors = { Color3.fromRGB(240, 80, 80), Color3.fromRGB(80, 150, 240), Color3.fromRGB(255, 210, 60) }
		for i = 0, 2 do
			Shapes.box(folder, Vector3.new(2.6, 2.6, 2.6), at * CFrame.new(0.3 * i, 2.5 + i * 2.6, 0) * CFrame.Angles(0, i * 0.4, 0), { color = colors[i + 1] })
		end
		Shapes.ball(folder, 2.4, at * CFrame.new(3.5, 2.4, 1), { color = Color3.fromRGB(110, 210, 120) })
	elseif def.theme == "kitchen" then
		-- A little fridge with its door swung open.
		Shapes.roundedBox(folder, Vector3.new(4, 8, 3.4), 0.6, at * CFrame.new(0, 5, 0), { color = Color3.fromRGB(240, 245, 250) })
		Shapes.box(folder, Vector3.new(3.4, 7.4, 0.2), at * CFrame.new(0, 5, -1.75), { color = Color3.fromRGB(180, 230, 255), material = Enum.Material.Neon })
		Shapes.box(folder, Vector3.new(0.3, 7.6, 3.4), at * CFrame.new(-3.7, 5, -2.6) * CFrame.Angles(0, math.rad(70), 0), { color = Color3.fromRGB(240, 245, 250) })
		Shapes.ball(folder, 1.2, at * CFrame.new(0.8, 6.5, -1.2), { color = Color3.fromRGB(230, 60, 60) })
	elseif def.theme == "backyard" then
		-- A flowerpot with a ladybug on the rim.
		Shapes.pillar(folder, 4, 3.5, at * CFrame.new(0, 2.8, 0), { color = Color3.fromRGB(210, 110, 70) })
		Shapes.pillar(folder, 0.4, 4, at * CFrame.new(0, 6, 0), { color = Color3.fromRGB(80, 160, 70) })
		Shapes.ball(folder, 2.2, at * CFrame.new(0, 8.3, 0), { color = Color3.fromRGB(255, 120, 170) })
		Shapes.ellipsoid(folder, Vector3.new(1.4, 0.9, 1.8), at * CFrame.new(1.8, 4.8, 0), { color = Color3.fromRGB(230, 40, 40) })
	else
		Shapes.ball(folder, 4, at * CFrame.new(0, 3.5, 0), { color = c(theme.accent) })
	end
	folder.Parent = parent
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
export type Handles = {
	setStatus: (title: string, body: string) -> (),
	setVoteOption: (index: number, info: any?) -> (),
	setPodium: (rows: { any }) -> (),
	setSpectator: (title: string, body: string) -> (),
	setKartDisplay: (slot: number, name: string?, kartId: string?, look: any?) -> (),
	readyPrompt: ProximityPrompt,
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
	local O = LobbyLayout.Origin
	local spawnSpot = LobbyLayout.Spawn

	-- Ground: soft grass everywhere, a tiled plaza, paths to each area.
	Shapes.box(lobby, Vector3.new(900, 2, 1000), CFrame.new(O.x, -1, O.z + 120), { color = PALETTE.grass, collide = true, name = "Ground" })
	Shapes.disc(lobby, LobbyLayout.PlazaRadius * 2, 0.4, cf(spawnSpot, 0.2), { color = PALETTE.tile, collide = true })
	Shapes.disc(lobby, LobbyLayout.PlazaRadius * 2 - 6, 0.42, cf(spawnSpot, 0.21), { color = PALETTE.cream, collide = true })
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Shapes.disc(lobby, 8, 0.45, cf(spawnSpot, 0.23) * CFrame.new(math.cos(a) * 34, 0, math.sin(a) * 34), { color = PAD_COLORS[i % 3 + 1] })
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 0.5, 14)
	spawn.CFrame = cf(spawnSpot, 0.5)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = lobby
	local fountain = Shapes.pillar(lobby, 10, 3, cf(spawnSpot, 1.5) * CFrame.new(0, 0, 18), { color = PALETTE.white, collide = true })
	local _ = fountain
	Shapes.disc(lobby, 8.6, 0.4, cf(spawnSpot, 3.1) * CFrame.new(0, 0, 18), { color = PALETTE.sky, material = Enum.Material.Glass, transparency = 0.2 })
	Shapes.ellipsoid(lobby, Vector3.new(5, 7, 5), cf(spawnSpot, 6) * CFrame.new(0, 0, 18), { color = PALETTE.yellow, reflectance = 0.2 })

	local function path(a: LobbyLayout.Spot, b: LobbyLayout.Spot, width: number)
		local pa, pb = Vector3.new(a.x, 0.15, a.z), Vector3.new(b.x, 0.15, b.z)
		Shapes.box(lobby, Vector3.new(width, 0.3, (pb - pa).Magnitude), CFrame.lookAt((pa + pb) / 2, pb), { color = PALETTE.tile, collide = true })
	end
	path(spawnSpot, LobbyLayout.VotePads[2], 20)
	path(spawnSpot, LobbyLayout.Garage, 16)
	path(spawnSpot, LobbyLayout.ReadyArch, 16)
	path(spawnSpot, LobbyLayout.SpectatorScreen, 14)
	path(spawnSpot, LobbyLayout.Podium, 14)
	path(spawnSpot, { x = spawnSpot.x, y = 0, z = spawnSpot.z + 170 }, 18)

	-- Status board: what's happening and the countdown, readable from spawn.
	local boardCf = facing(LobbyLayout.StatusBoard, spawnSpot, 22)
	for _, side in { -1, 1 } do
		Shapes.pillar(lobby, 3, 24, boardCf * CFrame.new(side * 26, -10, 1.5), { color = PALETTE.white, collide = true })
	end
	local statusTitle, statusBody = sign(lobby, Vector3.new(52, 20, 3), boardCf, PALETTE.pink, "KART CARNIVAL")

	-- Voting pads with miniature track displays and info signs.
	local voteTitles, voteBodies = {}, {}
	for i, pad in LobbyLayout.VotePads do
		Shapes.disc(lobby, LobbyLayout.VotePadSize, 0.6, cf(pad, 0.3), { color = PAD_COLORS[i], collide = true, name = `VotePad{i}` })
		Shapes.disc(lobby, LobbyLayout.VotePadSize - 4, 0.62, cf(pad, 0.31), { color = PALETTE.white, collide = true })
		Shapes.disc(lobby, LobbyLayout.VotePadSize - 8, 0.64, cf(pad, 0.32), { color = PAD_COLORS[i], collide = true })
		local displayCf = cf(pad, 0) * CFrame.new(0, 0, -20)
		Shapes.pillar(lobby, 16, 5, displayCf * CFrame.new(0, 2.5, 0), { color = PALETTE.cream, collide = true })
		local title, body = sign(lobby, Vector3.new(22, 14, 2), facing({ x = pad.x, y = 0, z = pad.z - 30 }, spawnSpot, 16), PAD_COLORS[i], `OPTION {i}`)
		voteTitles[i], voteBodies[i] = title, body
	end
	local miniFolder = Instance.new("Folder")
	miniFolder.Name = "Miniatures"
	miniFolder.Parent = lobby

	-- Ready arch.
	local arch = LobbyLayout.ReadyArch
	local archCf = cf(arch, 0) * CFrame.Angles(0, math.rad(90), 0)
	Shapes.arch(lobby, 22, 3, 4, archCf, { color = PALETTE.yellow, collide = true }, 14)
	Shapes.disc(lobby, 20, 0.5, cf(arch, 0.25), { color = PALETTE.mint, collide = true })
	local readySign = Shapes.box(lobby, Vector3.new(4, 4, 4), cf(arch, 2), { color = PALETTE.mint, transparency = 1, collide = false })
	local readyPrompt = prompt(readySign, "Ready up", "Join the next race")
	local readyTitle, readyBody = sign(lobby, Vector3.new(14, 6, 1.5), cf(arch, 14.5) * CFrame.Angles(0, math.rad(90), 0), PALETTE.mint, "READY UP")
	readyBody.Text = "Walk in or press E"
	local _ = readyTitle

	-- Garage with kart display pedestals.
	local garageSpot = LobbyLayout.Garage
	-- Turned so the door (local front) faces the plaza to the west.
	local garageCf = cf(garageSpot, 0) * CFrame.Angles(0, math.rad(90), 0)
	Shapes.roundedBox(lobby, Vector3.new(60, 26, 40), 6, garageCf * CFrame.new(0, 13, 0), { color = PALETTE.sky, collide = true })
	Shapes.ellipsoid(lobby, Vector3.new(62, 16, 42), garageCf * CFrame.new(0, 26, 0), { color = PALETTE.white })
	Shapes.arch(lobby, 22, 2.4, 2, garageCf * CFrame.new(0, 0, -20.5), { color = PALETTE.yellow }, 12)
	Shapes.box(lobby, Vector3.new(20, 11, 0.6), garageCf * CFrame.new(0, 5.5, -20.2), { color = PALETTE.dark })
	local garageDoor = Shapes.box(lobby, Vector3.new(6, 6, 6), garageCf * CFrame.new(0, 3, -24), { color = PALETTE.dark, transparency = 1 })
	local garagePrompt = prompt(garageDoor, "Customize kart", "Garage")
	local gTitle = sign(lobby, Vector3.new(26, 7, 1.5), garageCf * CFrame.new(0, 31, -20), PALETTE.yellow, "GARAGE")
	local _ = gTitle
	local displays = Instance.new("Folder")
	displays.Name = "KartDisplays"
	displays.Parent = lobby
	for _, spot in LobbyLayout.KartDisplays do
		Shapes.disc(lobby, 12, 1.2, cf(spot, 0.6), { color = PALETTE.white, collide = true })
		Shapes.disc(lobby, 10, 1.25, cf(spot, 0.62), { color = PALETTE.purple, collide = true })
	end

	-- Podium for the last race's top three.
	local podium = LobbyLayout.Podium
	local podiumCf = facing(podium, spawnSpot, 0)
	local stepHeights = { 7, 4.5, 2.5 }
	local stepX = { 0, -11, 11 }
	local stepColors = { PALETTE.gold, Color3.fromRGB(200, 210, 225), Color3.fromRGB(230, 150, 80) }
	for place = 1, 3 do
		local h = stepHeights[place]
		Shapes.roundedBox(lobby, Vector3.new(10, h, 10), 1.5, podiumCf * CFrame.new(stepX[place], h / 2, 0), { color = stepColors[place], collide = true })
	end
	local podiumKarts = Instance.new("Folder")
	podiumKarts.Name = "PodiumKarts"
	podiumKarts.Parent = lobby
	local podiumTitle, podiumBody = sign(lobby, Vector3.new(30, 8, 1.5), podiumCf * CFrame.new(0, 20, 6), PALETTE.gold, "LAST RACE")
	local _ = podiumTitle
	podiumBody.Text = "No races yet"

	-- Spectator screen.
	local screenSpot = LobbyLayout.SpectatorScreen
	local screenCf = facing(screenSpot, spawnSpot, 16)
	for _, side in { -1, 1 } do
		Shapes.pillar(lobby, 2.5, 18, screenCf * CFrame.new(side * 17, -7, 1), { color = PALETTE.dark, collide = true })
	end
	local spectatorTitle, spectatorBody = sign(lobby, Vector3.new(34, 18, 2), screenCf, PALETTE.purple, "LIVE RACE")
	spectatorBody.Text = "No race running"
	local spectateSpot = Shapes.box(lobby, Vector3.new(4, 4, 4), screenCf * CFrame.new(0, -13, -8), { color = PALETTE.dark, transparency = 1 })
	local spectatePrompt = prompt(spectateSpot, "Watch race", "Spectator screen")

	-- Photo spot: a backdrop with a marker to stand on.
	local photo = LobbyLayout.PhotoSpot
	local photoCf = facing(photo, spawnSpot, 0)
	Shapes.arch(lobby, 30, 3, 3, photoCf * CFrame.new(0, 0, 8), { color = PALETTE.pink, collide = true }, 14)
	Shapes.box(lobby, Vector3.new(30, 16, 1), photoCf * CFrame.new(0, 8, 9.5), { color = PALETTE.cream, collide = true })
	local photoTitle, photoBody = sign(lobby, Vector3.new(22, 6, 1), photoCf * CFrame.new(0, 10, 8.5), PALETTE.pink, "KART CARNIVAL")
	local _ = photoTitle
	photoBody.Text = "Say cheese!"
	Shapes.disc(lobby, 8, 0.4, photoCf * CFrame.new(0, 0.2, -4), { color = PALETTE.yellow, collide = true })
	for i = 1, 14 do
		local a = i * 2.39
		local colors = { PALETTE.pink, PALETTE.yellow, PALETTE.sky, PALETTE.mint }
		Shapes.ball(lobby, 1.2, photoCf * CFrame.new(math.cos(a) * 11, 6 + (i % 5) * 2, 9) , { color = colors[i % 4 + 1] })
	end

	-- Decorations.
	ferrisWheel(lobby, LobbyLayout.FerrisWheel)
	local tentColors = { PALETTE.pink, PALETTE.sky, PALETTE.purple, PALETTE.mint }
	for i, offset in { { -150, 10 }, { -165, 130 }, { 175, -100 }, { 60, -170 }, { -60, -175 } } do
		tent(lobby, CFrame.new(O.x + offset[1], 0, O.z + offset[2]), tentColors[i % 4 + 1], 1 + (i % 2) * 0.3)
	end
	for _, offset in { { 36, 30 }, { -36, 30 }, { 36, -30 }, { -36, -30 } } do
		balloonCluster(lobby, CFrame.new(O.x + offset[1], 0, O.z + offset[2]))
		Shapes.pillar(lobby, 1, 16, CFrame.new(O.x + offset[1], 8, O.z + offset[2]), { color = PALETTE.white, collide = true })
	end
	stringLights(lobby, Vector3.new(O.x + 36, 16, O.z + 30), Vector3.new(O.x - 36, 16, O.z + 30))
	stringLights(lobby, Vector3.new(O.x + 36, 16, O.z - 30), Vector3.new(O.x - 36, 16, O.z - 30))
	stringLights(lobby, Vector3.new(O.x + 36, 16, O.z - 30), Vector3.new(O.x + 36, 16, O.z + 30))
	stringLights(lobby, Vector3.new(O.x - 36, 16, O.z - 30), Vector3.new(O.x - 36, 16, O.z + 30))

	-- Practice loop: open track with boost tunnel, jump ramp and drift circle.
	local area = LobbyLayout.PracticeArea
	Shapes.box(lobby, Vector3.new(area.max.x - area.min.x, 0.3, area.max.z - area.min.z), CFrame.new((area.min.x + area.max.x) / 2, 0.1, (area.min.z + area.max.z) / 2), { color = Color3.fromRGB(150, 210, 140), collide = true })
	local _, practice = TrackBuilder.build(LobbyLayout.PracticeTrack.id, { folderName = "PracticeTrack", ground = false, scenery = false })
	local drift = LobbyLayout.DriftCircle
	Shapes.disc(lobby, drift.radius * 2, 0.35, cf(drift.center, 0.12), { color = PALETTE.white, collide = true })
	Shapes.disc(lobby, drift.radius * 2 - 4, 0.37, cf(drift.center, 0.13), { color = Color3.fromRGB(70, 72, 90), collide = true })
	Shapes.disc(lobby, 10, 0.4, cf(drift.center, 0.14), { color = PALETTE.pink, collide = true })
	local dTitle, dBody = sign(lobby, Vector3.new(16, 6, 1), cf(drift.center, 6) * CFrame.new(0, 0, -drift.radius - 4), PALETTE.purple, "DRIFT CIRCLE")
	local _ = dTitle
	dBody.Text = "Hold drift and go round!"
	-- Boost tunnel arches over the boost pads.
	local padDistances = {}
	for _, pad in Track.pads(practice) do
		table.insert(padDistances, pad.distance)
	end
	if #padDistances > 0 then
		local from, to = math.min(table.unpack(padDistances)) - 20, math.max(table.unpack(padDistances)) + 20
		for d = from, to, 8 do
			local p, tan = Track.at(practice, d)
			-- Arches are built across the local x/y plane, so facing along the road spans it.
			local at = CFrame.lookAt(Vector3.new(p.x, p.y, p.z), Vector3.new(p.x + tan.x, p.y, p.z + tan.z))
			local ring = math.floor(d / 8) % 2
			Shapes.arch(lobby, LobbyLayout.PracticeTrack.width + 6, 2, 3, at, { color = if ring == 0 then PALETTE.pink else PALETTE.yellow, collide = false }, 12)
		end
	end
	local practiceStart = Track.spot(practice, practice.length - 30, 0)
	local practiceSign = Shapes.box(lobby, Vector3.new(4, 4, 4), CFrame.new(practiceStart.x, 2, practiceStart.z - 30), { color = PALETTE.dark, transparency = 1 })
	local practicePrompt = prompt(practiceSign, "Drive practice kart", "Practice loop")
	local pTitle, pBody = sign(lobby, Vector3.new(18, 7, 1.5), CFrame.lookAt(Vector3.new(practiceStart.x, 9, practiceStart.z - 32), Vector3.new(spawnSpot.x, 9, spawnSpot.z)), PALETTE.sky, "PRACTICE")
	local _ = pTitle
	pBody.Text = "Press E to drive"

	-- Hidden collectibles: spinning golden tokens.
	local tokens = {}
	local tokenFolder = Instance.new("Folder")
	tokenFolder.Name = "Tokens"
	tokenFolder.Parent = lobby
	for i, spot in LobbyLayout.Collectibles do
		local token = Shapes.tube(tokenFolder, 4, 0.8, cf(spot, 1.5) * CFrame.Angles(0, 0, 0), { color = PALETTE.gold, material = Enum.Material.Neon, name = `Token{i}` })
		token:SetAttribute("Spin", 2)
		token:SetAttribute("TokenId", i)
		table.insert(tokens, token)
	end

	lobby.Parent = Workspace

	-- Handles -------------------------------------------------------------
	local function setKartDisplay(slot: number, name: string?, kartId: string?, look: any?)
		local existing = displays:FindFirstChild(`Slot{slot}`)
		if existing then
			existing:Destroy()
		end
		local spot = LobbyLayout.KartDisplays[slot]
		if not spot or not name then
			return
		end
		local at = CFrame.new(spot.x, 1.3, spot.z) * CFrame.Angles(0, math.rad(90), 0) -- face the plaza
		local kart = KartRig.build(kartId or Karts.Default, name, at, displays, look)
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
			local h = stepHeights[place]
			local at = podiumCf * CFrame.new(stepX[place], h + 0.1, 0)
			local kart = KartRig.build(row.kartId or Karts.Default, row.name, at, podiumKarts, row.look)
			kart.PrimaryPart.Anchored = true
			table.insert(lines, `{place}. {row.name}`)
		end
		podiumBody.Text = if #lines > 0 then table.concat(lines, "   ") else "No races yet"
	end

	local function setVoteOption(index: number, info: any?)
		local title, body = voteTitles[index], voteBodies[index]
		local mini = miniFolder:FindFirstChild(`Pad{index}`)
		if mini then
			mini:Destroy()
		end
		if not info then
			title.Text = `OPTION {index}`
			body.Text = "Voting opens when someone is ready"
			return
		end
		title.Text = `{info.icon or ""} {info.name}`
		body.Text = `{info.difficulty}\n{info.feature}\n{info.votes} vote{if info.votes == 1 then "" else "s"}`
		local holder = Instance.new("Folder")
		holder.Name = `Pad{index}`
		holder.Parent = miniFolder
		local pad = LobbyLayout.VotePads[index]
		miniature(holder, info.id, cf(pad, 5) * CFrame.new(0, 0, -20))
	end

	for i = 1, #LobbyLayout.VotePads do
		setVoteOption(i, nil)
	end

	return {
		setStatus = function(title: string, body: string)
			statusTitle.Text = title
			statusBody.Text = body
		end,
		setVoteOption = setVoteOption,
		setPodium = setPodium,
		setSpectator = function(title: string, body: string)
			spectatorTitle.Text = title
			spectatorBody.Text = body
		end,
		setKartDisplay = setKartDisplay,
		readyPrompt = readyPrompt,
		garagePrompt = garagePrompt,
		spectatePrompt = spectatePrompt,
		practicePrompt = practicePrompt,
		collectibles = tokens,
	}
end

return LobbyBuilder
