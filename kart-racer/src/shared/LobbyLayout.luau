--!strict
-- Compact indoor voting hall with garage, trophies and party bays.
-- World-space coordinates; the legacy practice definition is kept only for
-- old data/module compatibility and is not built or reachable from the lobby.

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

-- Compact indoor chamber; no practice or viewing rooms.
LobbyLayout.HalfWidth = 68
LobbyLayout.HalfDepth = 78
LobbyLayout.Height = 44
LobbyLayout.DeckHeight = 8
LobbyLayout.Screen = { center = at(0, -77, 24), width = 76, height = 26, recess = 2 }
LobbyLayout.StatusBoard = at(0, -76, 39)
LobbyLayout.DepartureDoors = { at(-54, -78), at(54, -78) }
LobbyLayout.CentralFloor = { center = at(0, -10), radius = 25 }
LobbyLayout.VotePads = { at(-39, -48), at(-13, -52), at(13, -52), at(39, -48) }
LobbyLayout.VotePadSize = 16
LobbyLayout.RandomPad = 4
LobbyLayout.PadColors = { { 105, 165, 190 }, { 195, 125, 150 }, { 205, 175, 105 }, { 155, 140, 195 } }
LobbyLayout.Platform = box(-68, 48, 68, 78)
LobbyLayout.Spawn = at(0, 65, 8)
LobbyLayout.Stairs = { from = at(0, 48, 8), to = at(0, 28), width = 28, steps = 4 }
LobbyLayout.Ramps = {
 { from = at(-44, 48, 8), to = at(-44, 0), width = 12 },
 { from = at(44, 48, 8), to = at(44, 0), width = 12 },
}
LobbyLayout.Walkways = { box(-68, -66, -58, 48), box(58, -66, 68, 48) }
export type Room = { id: string, name: string, icon: string, door: Spot, side: number, box: Box }
LobbyLayout.Rooms = {
 { id = "garage", name = "Garage", icon = "🔧", door = at(-68, -24), side = -1, box = box(-110, -66, -68, 6) },
 { id = "trophy", name = "Trophy Room", icon = "🏆", door = at(68, -28), side = 1, box = box(68, -66, 110, 0) },
 { id = "party", name = "Party Bays", icon = "🎉", door = at(68, 28), side = 1, box = box(68, 8, 110, 66) },
} :: { Room }
LobbyLayout.DoorWidth = 16
LobbyLayout.DoorHeight = 13
LobbyLayout.KartDisplays = { at(-23, -70), at(0, -70), at(23, -70), at(-58, 20) }

-- Indoor practice circuit (inside the removed legacy practice layout). Open, no walls.
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
 at(-61, -62, 10), at(61, -62, 10), at(-104, -58, 2),
 at(104, 58, 2), at(104, -58, 2), at(-56, 67, 10),
}

-- Practice sign at the removed legacy practice layout entrance; it starts a practice kart.
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
