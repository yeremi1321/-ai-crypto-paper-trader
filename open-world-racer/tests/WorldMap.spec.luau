local T = require("./TestLib")
local WorldMap = require("../src/shared/WorldMap")

local function distToSegment(pt, a, b)
	local abx, abz = b.x - a.x, b.z - a.z
	local len2 = abx * abx + abz * abz
	local t = if len2 == 0 then 0 else math.clamp(((pt.x - a.x) * abx + (pt.z - a.z) * abz) / len2, 0, 1)
	local dx, dz = a.x + abx * t - pt.x, a.z + abz * t - pt.z
	return math.sqrt(dx * dx + dz * dz)
end

local function nearRoad(pt, slack)
	for _, r in WorldMap.Roads do
		if distToSegment(pt, r.a, r.b) <= r.width / 2 + slack then
			return true
		end
	end
	return false
end

T.test("every event start and checkpoint sits on a road", function()
	for id, ev in WorldMap.Events do
		T.ok(nearRoad(ev.start, 10), `{id} start off-road`)
		for i, cp in ev.checkpoints do
			T.ok(nearRoad(cp, 10), `{id} checkpoint {i} off-road`)
		end
	end
end)

T.test("every place and flash spot is reachable from a road", function()
	for id, place in WorldMap.Places do
		T.ok(nearRoad(place.pos, 40), `{id} is far from any road`)
	end
	for _, spot in WorldMap.FlashSpots do
		T.ok(nearRoad(spot.pos, 10), `{spot.id} off-road`)
		T.ok(WorldMap.Events[spot.eventId], `{spot.id} has unknown event`)
	end
end)

T.test("districts resolve by location", function()
	T.eq(WorldMap.districtAt(WorldMap.p(0, 0)), "downtown")
	T.eq(WorldMap.districtAt(WorldMap.p(1600, -300)), "circuit")
	T.eq(WorldMap.districtAt(WorldMap.p(-1300, 200)), "dragstrip")
	T.eq(WorldMap.districtAt(WorldMap.p(0, 900)), "highway")
end)

T.test("each event's district matches where it is", function()
	for id, ev in WorldMap.Events do
		T.eq(WorldMap.districtAt(ev.start), ev.district, id)
	end
end)

T.test("hidden part rewards are real parts", function()
	local CarCatalog = require("../src/shared/CarCatalog")
	for _, d in WorldMap.Discoveries do
		if d.kind == "hiddenPart" then
			T.ok(CarCatalog.getPart(d.reward), `{d.id} reward`)
		end
	end
end)
