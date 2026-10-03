-- Roads and land: the road cross-section has no folds or gaps, and the
-- terrain plan never puts ground, hills or water on the road.
local T = require("./TestLib")
local Landscape = require("../src/shared/Landscape")
local RoadGeometry = require("../src/shared/RoadGeometry")
local Track = require("../src/shared/Track")
local Tracks = require("../src/shared/Tracks")

local built = {}
local function trackOf(def)
	built[def.id] = built[def.id] or Track.build(def)
	return built[def.id]
end

T.test("road edges never fold back on any track, and pieces share their ends", function()
	for _, def in Tracks.List do
		local track = trackOf(def)
		local frames = RoadGeometry.frames(track)
		T.eq(#frames, #track.points, def.id)
		for _, side in { -1, 1 } do
			T.eq(#RoadGeometry.folds(frames, side * def.width / 2), 0, `{def.id} road edge folds`)
			T.ok(#RoadGeometry.folds(frames, side * (def.width / 2 + Track.ShoulderWidth + 0.9)) <= 2, `{def.id} barrier folds`)
		end
		-- Sideways vectors are level and unit length, so widths are exact.
		for _, f in frames do
			T.ok(math.abs(f.rx * f.rx + f.rz * f.rz - 1) < 1e-6, "unit side vector")
		end
	end
end)

T.test("corners get curbs, straights get lines", function()
	for _, def in Tracks.List do
		local corners = 0
		local frames = RoadGeometry.frames(trackOf(def))
		for _, f in frames do
			if RoadGeometry.isCorner(f) then
				corners += 1
			end
		end
		T.ok(corners > 0 and corners < #frames, `{def.id}: {corners} of {#frames} points are corners`)
	end
end)

T.test("realistic outdoor tracks get terrain; the toy worlds don't", function()
	for _, id in { "sunny", "canyon", "alpine", "backyard", "emberfort" } do
		T.ok(Landscape.plan(trackOf(Tracks.get(id))) ~= nil, `{id} has no terrain`)
	end
	for _, id in { "toyroom", "kitchen", "neon" } do
		T.eq(Landscape.plan(trackOf(Tracks.get(id))), nil, `{id} should not have terrain`)
	end
	T.ok(#Landscape.plan(trackOf(Tracks.get("sunny"))).caps > 0, "snow caps on the sunny mountains")
	T.ok(#Landscape.plan(trackOf(Tracks.get("canyon"))).mesas > 0, "canyon mesas")
end)

T.test("land never rises onto the road, and no water sits on it except under bridges", function()
	for _, def in Tracks.List do
		local track = trackOf(def)
		local plan = Landscape.plan(track)
		if plan then
			local frames = RoadGeometry.frames(track)
			local half = def.width / 2
			for i, f in frames do
				local verge = half + Track.ShoulderWidth + 3 -- RoadSurface.VergeExtra
				for _, lateral in { -verge, -half, 0, half, verge } do
					local e = RoadGeometry.edge(f, lateral)
					local h = Landscape.groundAt(plan, e.x, e.z)
					if h then
						-- Terrain stays well under the 4-stud road and verge slabs, so
						-- its 4-stud voxels can't round up through them (grass poking
						-- through the road was the bug this guards).
						T.ok(h <= f.y - 2.5, `{def.id} point {i}: ground {h} is less than 2.5 under the road {f.y}`)
					else
						T.ok(not plan.bankAt[i], `{def.id} point {i}: water on a banked road`)
					end
				end
			end
		end
	end
end)

T.test("Pinewater Pass crosses its lake on a raised bridge", function()
	local track = trackOf(Tracks.get("alpine"))
	local plan = Landscape.plan(track) :: Landscape.Plan
	local lake = nil
	for _, l in plan.lakes do
		if l.bridged then
			lake = l
		end
	end
	T.ok(lake, "bridged lake")
	local over = 0
	for i, p in track.points do
		local dx, dz = p.x - lake.x, p.z - lake.z
		if dx * dx + dz * dz < lake.r * lake.r then
			over += 1
			T.ok(not plan.bankAt[i], "no earth bank damming the lake")
			T.ok(p.y - lake.surface > 8, `bridge only {p.y - lake.surface} studs above the water`)
		end
	end
	T.ok(over >= 4, `road crosses the lake ({over} points over water)`)
end)

T.test("the land plan is the same on every server", function()
	local a = Landscape.plan(trackOf(Tracks.get("canyon"))) :: Landscape.Plan
	local b = Landscape.plan(Track.build(Tracks.get("canyon"))) :: Landscape.Plan
	T.eq(#a.hills, #b.hills)
	T.eq(a.hills[1].x, b.hills[1].x)
	T.eq(a.mesas[2].top, b.mesas[2].top)
end)
