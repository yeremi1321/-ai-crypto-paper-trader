--!strict
-- The whole playable map as data. The server builds roads and landmarks from
-- this at startup, so the first playable version needs no hand-built terrain,
-- and a hand-built map can later replace WorldBuilder while keeping this layout.
--
-- Coordinates are {x, z} in studs on flat ground (y = 0).
-- Layout (first playable slice):
--   Downtown grid in the middle, wrapped by an octagonal highway loop.
--   East off the highway: the Harbor Ring circuit. West: the drag strip.

export type Point = { x: number, z: number }
export type Road = { a: Point, b: Point, width: number, kind: string }

export type EventDef = {
	id: string,
	name: string,
	kind: "circuit" | "sprint" | "drag",
	district: string,
	classCap: string?,
	laps: number?,
	start: Point,
	heading: Point, -- direction the grid faces
	checkpoints: { Point }, -- last one is the finish (for circuits, the start/finish line)
}

export type Place = {
	id: string,
	kind: "garage" | "dealership" | "tuning" | "meet" | "photo",
	name: string,
	pos: Point,
	district: string,
}

export type Discovery = {
	id: string,
	kind: "speedTrap" | "driftZone" | "hiddenPart" | "scenic",
	name: string,
	pos: Point,
	radius: number,
	district: string,
	reward: string?, -- part id for hidden parts
}

local WorldMap = {}

local function p(x: number, z: number): Point
	return { x = x, z = z }
end

WorldMap.p = p

---------------------------------------------------------------------------
-- Districts (used for reputation and for the map screen)
---------------------------------------------------------------------------
WorldMap.Districts = {
	downtown = { id = "downtown", name = "Downtown", center = p(0, 0), radius = 520, style = "Tight corners, traffic, sprints" },
	highway = { id = "highway", name = "Highway Loop", center = p(0, 0), radius = 980, style = "Top speed runs" },
	circuit = { id = "circuit", name = "Harbor Ring", center = p(1600, 0), radius = 450, style = "Clean laps" },
	dragstrip = { id = "dragstrip", name = "Westside Strip", center = p(-1300, 0), radius = 500, style = "Launch and gearing" },
}

-- Order matters: smaller, more specific districts are checked first.
local DISTRICT_ORDER = { "circuit", "dragstrip", "downtown", "highway" }

function WorldMap.districtAt(pos: Point): string
	for _, id in DISTRICT_ORDER do
		local d = WorldMap.Districts[id]
		local dx, dz = pos.x - d.center.x, pos.z - d.center.z
		if dx * dx + dz * dz <= d.radius * d.radius then
			return id
		end
	end
	return "highway"
end

---------------------------------------------------------------------------
-- Roads
---------------------------------------------------------------------------
local GRID_MIN, GRID_MAX, GRID_STEP = -360, 360, 120
local HIGHWAY_R = 900

WorldMap.Grid = { min = GRID_MIN, max = GRID_MAX, step = GRID_STEP }
WorldMap.HighwayRadius = HIGHWAY_R

local function octagon(cx: number, cz: number, r: number): { Point }
	local pts = {}
	for i = 0, 7 do
		local a = math.rad(i * 45)
		table.insert(pts, p(math.floor(cx + r * math.cos(a) + 0.5), math.floor(cz + r * math.sin(a) + 0.5)))
	end
	return pts
end

WorldMap.HighwayPoints = octagon(0, 0, HIGHWAY_R)

WorldMap.CircuitPoints = {
	p(1300, 0),
	p(1350, -300),
	p(1600, -380),
	p(1850, -250),
	p(1900, 50),
	p(1750, 300),
	p(1500, 320),
	p(1370, 200),
}

WorldMap.DragStrip = { a = p(-1300, 400), b = p(-1300, -400) }

local function buildRoads(): { Road }
	local roads: { Road } = {}
	local function add(a: Point, b: Point, width: number, kind: string)
		table.insert(roads, { a = a, b = b, width = width, kind = kind })
	end

	-- Downtown grid
	for v = GRID_MIN, GRID_MAX, GRID_STEP do
		add(p(v, GRID_MIN), p(v, GRID_MAX), 28, "street")
		add(p(GRID_MIN, v), p(GRID_MAX, v), 28, "street")
	end

	-- Highway loop
	local hw = WorldMap.HighwayPoints
	for i = 1, #hw do
		add(hw[i], hw[i % #hw + 1], 48, "highway")
	end

	-- Ramps from the four edges of downtown out to the highway
	add(p(GRID_MAX, 0), p(HIGHWAY_R, 0), 32, "ramp")
	add(p(GRID_MIN, 0), p(-HIGHWAY_R, 0), 32, "ramp")
	add(p(0, GRID_MAX), p(0, HIGHWAY_R), 32, "ramp")
	add(p(0, GRID_MIN), p(0, -HIGHWAY_R), 32, "ramp")

	-- Circuit and its access road
	add(p(HIGHWAY_R, 0), WorldMap.CircuitPoints[1], 32, "ramp")
	local cp = WorldMap.CircuitPoints
	for i = 1, #cp do
		add(cp[i], cp[i % #cp + 1], 40, "track")
	end

	-- Drag strip and its access road
	add(p(-HIGHWAY_R, 0), p(WorldMap.DragStrip.a.x, 0), 32, "ramp")
	add(WorldMap.DragStrip.a, WorldMap.DragStrip.b, 40, "strip")

	return roads
end

WorldMap.Roads = buildRoads()

---------------------------------------------------------------------------
-- Places you drive to
---------------------------------------------------------------------------
WorldMap.Places = {
	garage = { id = "garage", kind = "garage", name = "Your Garage", pos = p(-300, -340), district = "downtown" },
	dealership = { id = "dealership", kind = "dealership", name = "Crown Motors", pos = p(180, -340), district = "downtown" },
	tuning = { id = "tuning", kind = "tuning", name = "Torque Lab Tuning", pos = p(-180, 140), district = "downtown" },
	meetGas = { id = "meetGas", kind = "meet", name = "Night Owl Gas", pos = p(300, 340), district = "downtown" },
	meetStrip = { id = "meetStrip", kind = "meet", name = "Strip Pit Lane", pos = p(-1230, 0), district = "dragstrip" },
	photoHarbor = { id = "photoHarbor", kind = "photo", name = "Harbor Overlook", pos = p(1600, -420), district = "circuit" },
} :: { [string]: Place }

---------------------------------------------------------------------------
-- Fixed events (flash races and the midnight meet reuse these routes)
---------------------------------------------------------------------------
WorldMap.Events = {
	harborRing = {
		id = "harborRing",
		name = "Harbor Ring",
		kind = "circuit",
		district = "circuit",
		laps = 2,
		start = p(1320, -100),
		heading = p(1350 - 1300, -300 - 0),
		checkpoints = { p(1350, -300), p(1600, -380), p(1850, -250), p(1900, 50), p(1750, 300), p(1500, 320), p(1370, 200), p(1300, 0) },
	},
	downtownSprint = {
		id = "downtownSprint",
		name = "Downtown Sprint",
		kind = "sprint",
		district = "downtown",
		start = p(-360, -330),
		heading = p(0, 1),
		checkpoints = { p(-360, 120), p(0, 120), p(0, -240), p(360, -240), p(360, 360) },
	},
	highwayRun = {
		id = "highwayRun",
		name = "Highway Run",
		kind = "sprint",
		district = "highway",
		start = p(900, 60),
		heading = p(0, 1),
		checkpoints = {
			WorldMap.HighwayPoints[2],
			WorldMap.HighwayPoints[3],
			WorldMap.HighwayPoints[4],
			WorldMap.HighwayPoints[5],
			WorldMap.HighwayPoints[6],
		},
	},
	westsideDrag = {
		id = "westsideDrag",
		name = "Westside Quarter",
		kind = "drag",
		district = "dragstrip",
		start = p(-1300, 360),
		heading = p(0, -1),
		checkpoints = { p(-1300, -360) },
	},
} :: { [string]: EventDef }

-- Places where flash races can pop up, each tied to a route that starts nearby.
WorldMap.FlashSpots = {
	{ id = "tunnelMouth", name = "Tunnel Mouth", pos = p(-360, -330), eventId = "downtownSprint" },
	{ id = "overpass", name = "East Overpass", pos = p(900, 60), eventId = "highwayRun" },
	{ id = "stripLot", name = "Strip Staging Lot", pos = p(-1300, 360), eventId = "westsideDrag" },
	{ id = "harborGate", name = "Harbor Gate", pos = p(1320, -100), eventId = "harborRing" },
}

-- Secret midnight meet locations with the clue players get during the day.
WorldMap.MidnightSpots = {
	{ id = "rooftop", name = "Parking Garage Rooftop", pos = p(120, 0), clue = "Where downtown's cars sleep, look up." },
	{ id = "docksLot", name = "Old Harbor Lot", pos = p(1600, 0), clue = "Inside the ring, where the gulls land." },
	{ id = "underpass", name = "West Underpass", pos = p(-900, 60), clue = "Under the highway, facing the sunset." },
	{ id = "gasOwl", name = "Night Owl Forecourt", pos = p(300, 340), clue = "The owl stays open late." },
}

WorldMap.Discoveries = {
	{ id = "trapRamp", kind = "speedTrap", name = "East Ramp Camera", pos = p(640, 0), radius = 30, district = "highway" },
	{ id = "trapStrip", kind = "speedTrap", name = "Strip Trap", pos = p(-1300, -300), radius = 30, district = "dragstrip" },
	{ id = "driftHarbor", kind = "driftZone", name = "Harbor Hairpin", pos = p(1600, -380), radius = 80, district = "circuit" },
	{ id = "partAlley", kind = "hiddenPart", name = "Alley Stash", pos = p(-240, 60), radius = 14, district = "downtown", reward = "tiresSport" },
	{ id = "partUnder", kind = "hiddenPart", name = "Underpass Stash", pos = p(-630, -630), radius = 14, district = "highway", reward = "weight1" },
	{ id = "scenicNorth", kind = "scenic", name = "North Bend", pos = WorldMap.HighwayPoints[3], radius = 60, district = "highway" },
} :: { Discovery }

return WorldMap
