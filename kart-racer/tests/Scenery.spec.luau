local T = require("./TestLib")
local Scenery = require("../src/shared/Scenery")
local Track = require("../src/shared/Track")
local Tracks = require("../src/shared/Tracks")

for _, def in Tracks.List do
	T.test(`{def.name}: scenery is plentiful and never on the road`, function()
		local track = Track.build(def)
		local props = Scenery.place(track)
		local barrier = Scenery.barrier(track)
		local counts = {}
		for _, prop in props do
			counts[prop.kind] = (counts[prop.kind] or 0) + 1
			local p = Track.project(track, Track.v(prop.x, track.points[1].y, prop.z))
			-- Measure flat distance to every centerline point (bridges overlap in 3D).
			local nearest = math.huge
			for _, pt in track.points do
				nearest = math.min(nearest, math.sqrt((pt.x - prop.x) ^ 2 + (pt.z - prop.z) ^ 2))
			end
			T.ok(nearest > barrier, `{prop.kind} at ({math.floor(prop.x)}, {math.floor(prop.z)}) is {nearest} from the road`)
			local _ = p
		end
		T.ok(#props >= 100, `only {#props} props`)
		T.eq(counts.grandstand, 2)
	end)
end

T.test("scenery is the same every time (all servers agree)", function()
	local track = Track.build(Tracks.List[1])
	local a, b = Scenery.place(track), Scenery.place(track)
	T.eq(#a, #b)
	T.eq(a[10].x, b[10].x)
end)
