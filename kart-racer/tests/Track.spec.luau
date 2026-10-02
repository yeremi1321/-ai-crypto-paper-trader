local T = require("./TestLib")
local Track = require("../src/shared/Track")
local Tracks = require("../src/shared/Tracks")

local square = Track.build({
	id = "sq", name = "sq", width = 40, laps = 3, theme = "sunny",
	-- Extra points along each side keep the edges straight (Catmull-Rom bulges otherwise).
	controls = (function()
		local pts = {}
		for z = 0, -300, -100 do table.insert(pts, Track.v(0, 0, z)) end
		for x = 0, 300, 100 do table.insert(pts, Track.v(x, 0, -400)) end
		for z = -400, -100, 100 do table.insert(pts, Track.v(400, 0, z)) end
		for x = 400, 100, -100 do table.insert(pts, Track.v(x, 0, 0)) end
		return pts
	end)(),
	boostPads = { { t = 0.1, offset = 0 } }, itemRows = { 0.5 },
})

T.test("samples are evenly spaced and the loop closes", function()
	local n = #square.points
	local step = square.length / n
	for i = 1, n do
		local a, b = square.points[i], square.points[i % n + 1]
		local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
		T.ok(math.abs(d - step) < step * 0.15, `gap {d} vs {step} at {i}`)
	end
	T.eq(square.points[1].x, 0)
	T.eq(square.points[1].z, 0)
end)

T.test("projection finds distance and side of the road", function()
	local p = Track.project(square, Track.v(5, 0, -100))
	T.ok(p.distance > 80 and p.distance < 120, `distance {p.distance}`)
	-- Driving north (-z), +x is the right-hand side.
	T.ok(p.lateral > 3 and p.lateral < 7, `lateral {p.lateral}`)
	T.eq(Track.surfaceAt(square, p), "road")
	T.eq(Track.surfaceAt(square, Track.project(square, Track.v(-25, 0, -200))), "offroad")
	T.eq(Track.surfaceAt(square, Track.project(square, Track.v(-40, 0, -200))), "wall")
end)

T.test("boost pads are detected where they are placed", function()
	local pad = Track.pads(square)[1]
	local pos = Track.spot(square, pad.distance, pad.lateral)
	T.eq(Track.surfaceAt(square, Track.project(square, pos)), "boost")
end)

T.test("spot and project agree", function()
	for _, d in { 50, 333, 900, 1400 } do
		for _, lat in { -12, 0, 15 } do
			local pos = Track.spot(square, d, lat)
			local p = Track.project(square, pos)
			T.ok(math.abs(p.distance - d) < 3, `distance {p.distance} vs {d}`)
			T.ok(math.abs(p.lateral - lat) < 1, `lateral {p.lateral} vs {lat}`)
		end
	end
end)

local function drive(track, progress, from, to, stepSize)
	local crossings = 0
	local d = from
	while (stepSize > 0 and d < to) or (stepSize < 0 and d > to) do
		local pos = Track.spot(track, d, 0)
		if Track.updateProgress(track, progress, Track.project(track, pos, progress.index)) then
			crossings += 1
		end
		d += stepSize
	end
	return crossings
end

T.test("laps count only when driven all the way round", function()
	local _, gridD = Track.gridSpot(square, 1)
	local p = Track.newProgress(square, gridD)
	T.eq(p.lap, 0)
	drive(square, p, gridD, square.length + 10, 6)
	T.eq(p.lap, 1)
	drive(square, p, 10, square.length * 2 + 10, 6)
	T.eq(p.lap, 3)
end)

T.test("cutting across the infield does not count", function()
	local p = Track.newProgress(square, 10)
	p.lap = 1
	p.sector = 0
	-- Teleport from the start to just before the line, skipping most sectors.
	Track.updateProgress(square, p, Track.project(square, Track.spot(square, square.length - 30, 0)))
	Track.updateProgress(square, p, Track.project(square, Track.spot(square, 20, 0)))
	T.eq(p.lap, 1)
end)

T.test("reversing over the line takes the lap back", function()
	local _, gridD = Track.gridSpot(square, 1)
	local p = Track.newProgress(square, gridD)
	drive(square, p, gridD, square.length + 30, 6)
	T.eq(p.lap, 1)
	drive(square, p, square.length + 30, square.length - 40, -6)
	T.eq(p.lap, 0)
end)

T.test("wrong-way detection", function()
	local p = Track.project(square, Track.v(0, 0, -100))
	T.ok(not Track.wrongWay(square, p, 0, -1))
	T.ok(Track.wrongWay(square, p, 0, 1))
end)

T.test("bridge crossing on Neon Eight stays on the right level", function()
	local neon = Track.build(Tracks.get("neon"))
	-- Find the upper and lower passes over the origin.
	local lower, upper
	for i, pt in neon.points do
		if math.abs(pt.x) < 10 and math.abs(pt.z) < 10 then
			if pt.y < 10 then
				lower = i
			else
				upper = i
			end
		end
	end
	T.ok(lower and upper, "both passes exist")
	local onLower = Track.project(neon, Track.v(0, 2, 0))
	local onUpper = Track.project(neon, Track.v(0, 32, 0))
	T.ok(math.abs(onLower.index - lower) <= 2, "lower pass")
	T.ok(math.abs(onUpper.index - upper) <= 2, "upper pass")
	T.ok(neon.points[upper].y - neon.points[lower].y > 20, "enough clearance under the bridge")
end)

T.test("every track: grid is behind the line, items and pads are on the road", function()
	for _, def in Tracks.List do
		local track = Track.build(def)
		for slot = 1, 8 do
			local pos, d = Track.gridSpot(track, slot)
			T.ok(d > track.length * 0.8, `{def.id} grid slot {slot} distance`)
			T.eq(Track.surfaceAt(track, Track.project(track, pos)), "road", `{def.id} grid slot {slot}`)
		end
		for _, box in Track.itemBoxes(track) do
			local s = Track.surfaceAt(track, Track.project(track, Track.spot(track, box.distance, box.lateral)))
			T.ok(s == "road" or s == "boost", `{def.id} item box on {s}`)
		end
		T.ok(#Track.pads(track) == #def.boostPads)
		T.ok(track.length > 1500 and track.length < 6500, `{def.id} length {track.length}`)
	end
end)

T.test("slopes stay drivable", function()
	for _, def in Tracks.List do
		local track = Track.build(def)
		local n = #track.points
		for i = 1, n do
			local a, b = track.points[i], track.points[i % n + 1]
			local run = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
			T.ok(math.abs(b.y - a.y) / run < 0.25, `{def.id} grade too steep at point {i}`)
		end
	end
end)
