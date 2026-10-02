--!strict
-- The tracks and the cup they make up. Control points are {x, y, z} and are
-- driven in list order; the first point is the start/finish line.
-- tests/Simulation.spec.luau has CPU drivers race every track, so a bad edit
-- here (a corner too tight, a jump too steep) fails the tests.
--
-- Making a track bigger: raise `scale` (stretches the whole layout) and
-- `width` (road width in studs). Then run `lune run tests/run`.

local Track = require("./Track")
local v = Track.v

local Tracks = {}

Tracks.Themes = {
	sunny = {
		road = { 70, 70, 78 },
		shoulder = { 120, 170, 80 },
		ground = { 100, 160, 70 },
		wall = { 235, 235, 240 },
		accent = { 255, 210, 60 },
		curb = { { 220, 40, 40 }, { 245, 245, 245 } },
		line = { 245, 245, 245 },
		clock = 14,
		-- Lighting: hazy summer afternoon.
		ambient = { 120, 120, 130 },
		brightness = 3,
		atmosphere = { density = 0.3, haze = 1.2, glare = 0.4, color = { 200, 220, 255 }, decay = { 110, 140, 200 } },
		bloom = 0.6,
		tint = { 255, 250, 240 },
		saturation = 0.15,
	},
	canyon = {
		road = { 92, 80, 72 },
		shoulder = { 196, 150, 100 },
		ground = { 180, 120, 80 },
		wall = { 150, 90, 60 },
		accent = { 255, 140, 60 },
		curb = { { 230, 110, 40 }, { 250, 235, 210 } },
		line = { 250, 230, 190 },
		clock = 17.2,
		-- Lighting: dusty golden hour.
		ambient = { 140, 100, 80 },
		brightness = 2.6,
		atmosphere = { density = 0.38, haze = 2.2, glare = 1.2, color = { 255, 200, 150 }, decay = { 200, 110, 70 } },
		bloom = 0.9,
		tint = { 255, 235, 210 },
		saturation = 0.2,
	},
	neon = {
		road = { 30, 30, 42 },
		shoulder = { 50, 30, 80 },
		ground = { 16, 12, 28 },
		wall = { 0, 230, 255 },
		accent = { 255, 60, 220 },
		curb = { { 255, 60, 220 }, { 0, 230, 255 } },
		line = { 0, 230, 255 },
		clock = 0,
		-- Lighting: dark city night with glowing neon.
		ambient = { 60, 40, 90 },
		brightness = 1,
		atmosphere = { density = 0.42, haze = 1.5, glare = 0, color = { 120, 60, 180 }, decay = { 40, 20, 80 } },
		bloom = 1.6,
		tint = { 235, 220, 255 },
		saturation = 0.3,
	},
}

Tracks.List = {
	{
		id = "sunny",
		name = "Sunny Loop",
		theme = "sunny",
		width = 56,
		scale = 1.6,
		laps = 3,
		controls = {
			v(0, 0, 0),
			v(0, 0, -260),
			v(40, 0, -400),
			v(170, 0, -470),
			v(310, 0, -430),
			v(370, 0, -320),
			v(330, 0, -190),
			v(380, 0, -80),
			v(470, 0, 10),
			v(500, 0, 160),
			v(430, 0, 280),
			v(280, 0, 320),
			v(130, 0, 300),
			v(30, 0, 210),
			v(0, 0, 100),
		},
		boostPads = { { t = 0.08, offset = 0 }, { t = 0.55, offset = 0.4 }, { t = 0.83, offset = -0.4 } },
		itemRows = { 0.2, 0.62 },
	},
	{
		id = "canyon",
		name = "Canyon Climb",
		theme = "canyon",
		width = 52,
		scale = 1.6,
		laps = 3,
		controls = {
			v(0, 0, 0),
			v(0, 0, -250),
			v(60, 18, -400),
			v(200, 36, -460),
			v(360, 40, -400),
			v(430, 30, -260),
			v(390, 12, -120),
			v(460, 0, 20),
			v(570, 14, 150),
			v(550, 32, 310),
			v(400, 40, 370),
			v(240, 26, 330),
			v(150, 10, 230),
			v(50, 0, 150),
			v(0, 0, 80),
		},
		boostPads = { { t = 0.1, offset = -0.3 }, { t = 0.47, offset = 0 }, { t = 0.78, offset = 0.3 } },
		itemRows = { 0.25, 0.68 },
	},
	{
		id = "neon",
		name = "Neon Eight",
		theme = "neon",
		width = 50,
		scale = 1.5,
		laps = 3,
		controls = {
			v(-300, 0, 200),
			v(-150, 0, 150),
			v(0, 0, 0),
			v(150, 0, -150),
			v(300, 0, -200),
			v(470, 0, -80),
			v(470, 0, 80),
			v(300, 12, 200),
			v(150, 30, 150),
			v(0, 30, 0),
			v(-150, 30, -150),
			v(-300, 12, -200),
			v(-470, 0, -80),
			v(-470, 0, 80),
		},
		boostPads = { { t = 0.12, offset = 0 }, { t = 0.36, offset = 0.35 }, { t = 0.6, offset = 0 }, { t = 0.86, offset = -0.35 } },
		itemRows = { 0.3, 0.75 },
	},
} :: { Track.TrackDef }

-- A Grand Prix is every track in order.
Tracks.Cup = { name = "Starter Cup", tracks = { "sunny", "canyon", "neon" } }

function Tracks.get(id: string): Track.TrackDef
	for _, t in Tracks.List do
		if t.id == id then
			return t
		end
	end
	error(`unknown track {id}`)
end

return Tracks
