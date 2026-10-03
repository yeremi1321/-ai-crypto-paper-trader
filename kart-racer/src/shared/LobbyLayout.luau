--!strict
-- Layout of the indoor lobby: a tall voting chamber in the middle, with
-- side doors to optional rooms. It sits far from the race tracks (which are
-- built around the world origin). Coordinates are world studs; -z is the
-- "front" of the chamber (the giant voting screen), +z is the back (spawn).
--
--                     [ giant voting screen + status board ]
--   [departure door]   pads: 1   2   3   RANDOM   [departure door]
--   west wall doors:          ( central circular floor )       east wall doors:
--     garage            ramp                       ramp          practice hall
--     viewing lounge                                             party bays
--     trophy room        [ stairs down from the entrance ]
--   [ walkway ]       [ entrance platform with spawn (raised) ]       [ walkway ]

local Track = require("./Track")
local v = Track.v

export type Spot = { x: number, y: number, z: number }
export type Box = { min: Spot, max: Spot }

local LobbyLayout = {}

local OX, OZ = 0, 5000
local function at(dx: number, dz: number, y: number?): Spot
	return { x = OX + dx, y = y or 0, z = OZ + dz }
end
local function box(x0: number, z0: number, x1: number, z1: number): Box
	return { min = at(x0, z0), max = at(x1, z1) }
end

LobbyLayout.Origin = at(0, 0)

-- The chamber ------------------------------------------------------------
LobbyLayout.HalfWidth = 120 -- interior x from -120 to 120
LobbyLayout.HalfDepth = 150 -- interior z from -150 (screen) to 150 (back)
LobbyLayout.Height = 110 -- tall ceiling, so cameras have room
LobbyLayout.DeckHeight = 20 -- entrance platform and walkways

LobbyLayout.Screen = { center = at(0, -150, 50), width = 130, height = 56, recess = 6 }
LobbyLayout.StatusBoard = at(0, -149, 94)
LobbyLayout.DepartureDoors = { at(-92, -150), at(92, -150) }
LobbyLayout.CentralFloor = { center = at(0, -30), radius = 56 }

-- Vote pads in an arc in front of the screen. Pad 4 is Random.
LobbyLayout.VotePads = { at(-63, -100), at(-21, -106), at(21, -106), at(63, -100) }
LobbyLayout.VotePadSize = 22
LobbyLayout.RandomPad = 4
-- Colours shared by the pads, the wall screen and the vote cards (RGB).
LobbyLayout.PadColors = { { 0, 225, 255 }, { 255, 90, 170 }, { 255, 200, 60 }, { 170, 120, 255 } }

-- Raised entrance platform across the back, with spawn in the middle.
LobbyLayout.Platform = box(-120, 100, 120, 150)
LobbyLayout.Spawn = at(0, 128, LobbyLayout.DeckHeight)
LobbyLayout.Stairs = { from = at(0, 100, LobbyLayout.DeckHeight), to = at(0, 60), width = 50, steps = 10 }
-- Gentle accessible ramps either side of the stairs (about 11 degrees).
LobbyLayout.Ramps = {
	{ from = at(-69, 100, LobbyLayout.DeckHeight), to = at(-69, 0), width = 18 },
	{ from = at(69, 100, LobbyLayout.DeckHeight), to = at(69, 0), width = 18 },
}
-- Walkways along both side walls at deck height.
LobbyLayout.Walkways = { box(-120, -140, -104, 100), box(104, -140, 120, 100) }

-- Doors in the side walls (floor level, under the walkways), and the rooms behind.
export type Room = { id: string, name: string, icon: string, door: Spot, side: number, box: Box }
LobbyLayout.Rooms = {
	{ id = "garage", name = "Garage", icon = "🔧", door = at(-120, -70), side = -1, box = box(-230, -112, -120, -28) },
	{ id = "lounge", name = "Viewing Lounge", icon = "📺", door = at(-120, 5), side = -1, box = box(-230, -22, -120, 34) },
	{ id = "trophy", name = "Trophy Room", icon = "🏆", door = at(-120, 70), side = -1, box = box(-230, 40, -120, 98) },
	{ id = "practice", name = "Practice Circuit", icon = "🏁", door = at(120, -70), side = 1, box = box(120, -240, 520, -10) },
	{ id = "party", name = "Party Bays", icon = "🎉", door = at(120, 40), side = 1, box = box(120, 10, 230, 90) },
} :: { Room }
LobbyLayout.DoorWidth = 22
LobbyLayout.DoorHeight = 15

-- Kart display alcoves: four under the screen, four in the side walls.
LobbyLayout.KartDisplays = {
	at(-45, -143),
	at(-15, -143),
	at(15, -143),
	at(45, -143),
	at(-114, -115),
	at(-114, -32),
	at(114, -115),
	at(114, -5),
}

-- Indoor practice circuit (inside the practice hall). Open, no walls.
LobbyLayout.PracticeArea = box(150, -230, 510, -18)
LobbyLayout.DriftCircle = { center = at(330, -120), radius = 40 }
LobbyLayout.PracticeTrack = {
	id = "practice",
	name = "Practice Circuit",
	theme = "hq",
	width = 34,
	laps = 1,
	walls = false,
	controls = {
		v(OX + 240, 0, OZ - 40),
		v(OX + 420, 0, OZ - 40),
		v(OX + 465, 0, OZ - 80),
		v(OX + 465, 0, OZ - 160),
		v(OX + 420, 0, OZ - 200),
		v(OX + 240, 0, OZ - 200),
		v(OX + 195, 0, OZ - 160),
		v(OX + 195, 0, OZ - 80),
	},
	boostPads = { { t = 0.05, offset = 0 }, { t = 0.1, offset = 0 } },
	itemRows = {},
	ramps = { { t = 0.62, offset = 0, width = 16 } },
	difficulty = "Easy",
	feature = "Practice drifting, jumping and boosting",
	icon = "🏁",
} :: Track.TrackDef

-- Hidden golden tokens around the lobby rooms.
LobbyLayout.Collectibles = {
	at(-112, -136, LobbyLayout.DeckHeight + 2), -- far end of the west walkway
	at(112, -136, LobbyLayout.DeckHeight + 2), -- far end of the east walkway
	at(-220, -104, 2), -- back corner of the garage
	at(226, 86, 2), -- behind the couch in the last party bay
	at(-222, 92, 2), -- behind the trophy shelves
	at(500, -225, 2), -- corner of the practice hall
}

-- Practice sign at the practice hall entrance; it starts a practice kart.
LobbyLayout.PracticeStart = at(170, -70)

function LobbyLayout.roomById(id: string): Room?
	for _, room in LobbyLayout.Rooms do
		if room.id == id then
			return room
		end
	end
	return nil
end

-- Which vote pad (1..4, 4 = Random) a position is standing on, if any.
function LobbyLayout.padAt(x: number, z: number): number?
	local r = LobbyLayout.VotePadSize / 2
	for i, pad in LobbyLayout.VotePads do
		local dx, dz = x - pad.x, z - pad.z
		if dx * dx + dz * dz <= r * r then
			return i
		end
	end
	return nil
end

function LobbyLayout.inChamber(x: number, z: number): boolean
	return math.abs(x - OX) <= LobbyLayout.HalfWidth and math.abs(z - OZ) <= LobbyLayout.HalfDepth
end

function LobbyLayout.inBox(b: Box, x: number, z: number): boolean
	return x >= b.min.x and x <= b.max.x and z >= b.min.z and z <= b.max.z
end

return LobbyLayout
