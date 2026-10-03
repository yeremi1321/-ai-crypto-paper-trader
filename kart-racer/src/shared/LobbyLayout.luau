--!strict
-- Where everything in the Kart Carnival lobby goes. The lobby sits far from
-- the race tracks (which are built around the world origin), so the two never
-- overlap. Coordinates are world studs; +z is "south", away from the voting area.
--
--            [voting pads + track displays]
--   [podium]       [status board]          [garage + kart displays]
--   [ready arch]     (spawn plaza)         [photo spot]
--   [spectator screen]
--            [practice loop: drift circle, jump ramp, boost tunnel]

local Track = require("./Track")
local v = Track.v

export type Spot = { x: number, y: number, z: number }

local LobbyLayout = {}

local OX, OZ = 0, 5000
local function at(dx: number, dz: number, y: number?): Spot
	return { x = OX + dx, y = y or 0, z = OZ + dz }
end

LobbyLayout.Origin = at(0, 0)
LobbyLayout.Spawn = at(0, 0)
LobbyLayout.PlazaRadius = 46
LobbyLayout.StatusBoard = at(0, -58)
LobbyLayout.VotePads = { at(-52, -112), at(0, -112), at(52, -112) }
LobbyLayout.VotePadSize = 26
LobbyLayout.ReadyArch = at(-72, 0)
LobbyLayout.Garage = at(140, 0)
LobbyLayout.KartDisplays = (function()
	local spots = {}
	for i = 0, 7 do
		table.insert(spots, at(92, -56 + i * 16))
	end
	return spots
end)()
LobbyLayout.Podium = at(-120, -70)
LobbyLayout.SpectatorScreen = at(-130, 60)
LobbyLayout.PhotoSpot = at(120, 110)
LobbyLayout.FerrisWheel = at(-190, -150)

-- Hidden collectibles (stage 5 turns these into coins).
LobbyLayout.Collectibles = {
	at(176, 30, 2), -- behind the garage
	at(-190, -110, 2), -- under the Ferris wheel
	at(120, 132, 2), -- behind the photo wall
	at(-150, 74, 2), -- behind the spectator screen
	at(0, 300, 3), -- inside the boost tunnel
	at(-180, 380, 2), -- far corner of the practice area
}

-- Practice loop: an open area (no walls) south of the plaza.
LobbyLayout.PracticeArea = { min = at(-240, 170), max = at(240, 470) }
LobbyLayout.DriftCircle = { center = at(0, 320), radius = 46 }
LobbyLayout.PracticeTrack = {
	id = "practice",
	name = "Practice Loop",
	theme = "carnival",
	width = 36,
	laps = 1,
	walls = false,
	controls = {
		v(OX + 0, 0, OZ + 200),
		v(OX + 150, 0, OZ + 200),
		v(OX + 205, 0, OZ + 260),
		v(OX + 205, 0, OZ + 380),
		v(OX + 150, 0, OZ + 440),
		v(OX - 150, 0, OZ + 440),
		v(OX - 205, 0, OZ + 380),
		v(OX - 205, 0, OZ + 260),
		v(OX - 150, 0, OZ + 200),
	},
	-- Boost "tunnel" pads on the opening straight; the jump ramp is on the far straight.
	boostPads = { { t = 0.04, offset = 0 }, { t = 0.08, offset = 0 } },
	itemRows = {},
	ramps = { { t = 0.6, offset = 0, width = 18 } },
	difficulty = "Easy",
	feature = "Practice drifting, jumping and boosting",
	icon = "🎡",
} :: Track.TrackDef

function LobbyLayout.inPlaza(x: number, z: number): boolean
	local dx, dz = x - LobbyLayout.Spawn.x, z - LobbyLayout.Spawn.z
	return dx * dx + dz * dz <= LobbyLayout.PlazaRadius * LobbyLayout.PlazaRadius
end

-- Which vote pad (1..3) a position is standing on, if any.
function LobbyLayout.padAt(x: number, z: number): number?
	local half = LobbyLayout.VotePadSize / 2
	for i, pad in LobbyLayout.VotePads do
		if math.abs(x - pad.x) <= half and math.abs(z - pad.z) <= half then
			return i
		end
	end
	return nil
end

return LobbyLayout
