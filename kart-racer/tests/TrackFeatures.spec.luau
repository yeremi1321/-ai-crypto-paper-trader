local T = require("./TestLib")
local Track = require("../src/shared/Track")
local Tracks = require("../src/shared/Tracks")

T.test("shortcuts save distance but never skip a lap checkpoint", function()
	for _, def in Tracks.List do
		local track = Track.build(def)
		for i, sc in def.shortcuts or {} do
			local fromSector = Track.sectorOf(track, sc.from * track.length)
			local toSector = Track.sectorOf(track, sc.to * track.length)
			T.ok((toSector - fromSector) % track.sectors <= 1, `{def.id} shortcut {i} skips a whole sector`)
			local a, b = Track.shortcutEnds(track, sc)
			local straight = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
			local road = (sc.to - sc.from) * track.length
			T.ok(straight < road * 0.85, `{def.id} shortcut {i} is not shorter ({math.floor(straight)} vs {math.floor(road)})`)
			-- Walking along the shortcut counts as being on it.
			for k = 0, 10 do
				local p = Track.v(a.x + (b.x - a.x) * k / 10, a.y, a.z + (b.z - a.z) * k / 10)
				T.eq(Track.shortcutAt(track, p), i, `{def.id} shortcut {i} gap at {k}`)
			end
			-- The middle of the shortcut is off the main road (it really cuts across).
			local mid = Track.v((a.x + b.x) / 2, a.y, (a.z + b.z) / 2)
			local proj = Track.project(track, mid)
			T.ok(math.abs(proj.lateral) > def.width / 2, `{def.id} shortcut {i} runs along the road`)
			T.eq(Track.surfaceAt(track, proj, mid, 0), sc.surface or "road")
		end
	end
end)

T.test("driving a shortcut still counts the lap", function()
	local def = Tracks.get("toyroom")
	local track = Track.build(def)
	local sc = def.shortcuts[1]
	local _, gridD = Track.gridSpot(track, 1)
	local p = Track.newProgress(track, gridD)
	local function go(pos)
		Track.updateProgress(track, p, Track.project(track, pos, p.index))
	end
	for d = gridD, track.length + 20, 6 do
		go(Track.spot(track, d, 0))
	end
	T.eq(p.lap, 1)
	for d = 20, sc.from * track.length, 6 do
		go(Track.spot(track, d, 0))
	end
	local a, b = Track.shortcutEnds(track, sc)
	for k = 0, 20 do
		go(Track.v(a.x + (b.x - a.x) * k / 20, a.y, a.z + (b.z - a.z) * k / 20))
	end
	for d = sc.to * track.length, track.length + 20, 6 do
		go(Track.spot(track, d, 0))
	end
	T.eq(p.lap, 2)
end)

T.test("timed zones switch on and off", function()
	local zone = { kind = "slippery", t = 0.5, length = 40, period = 6, duty = 0.5 }
	T.ok(Track.zoneActive(zone, 1))
	T.ok(not Track.zoneActive(zone, 4))
	T.ok(Track.zoneActive(zone, 7))
	T.ok(Track.zoneActive({ kind = "sticky", t = 0, length = 1 }, 123))
end)

T.test("zones are found where they are placed", function()
	for _, def in Tracks.List do
		local track = Track.build(def)
		for _, zone in def.zones or {} do
			local width = zone.width or def.width
			local offset = (zone.offset or 0) * (def.width / 2 - width / 2)
			local pos = Track.spot(track, zone.t * track.length, offset)
			local proj = Track.project(track, pos)
			-- Find a time when it is on.
			local onTime = 0
			while not Track.zoneActive(zone, onTime) do
				onTime += 0.5
			end
			local surface = Track.surfaceAt(track, proj, pos, onTime)
			T.ok(surface == zone.kind or surface == "boost", `{def.id}: expected {zone.kind}, got {surface}`)
		end
	end
end)

T.test("crossers sweep across the road and wait off it", function()
	local track = Track.build(Tracks.get("backyard"))
	local c = Tracks.get("backyard").crossers[1]
	local onRoad, offRoad = 0, 0
	local minLat, maxLat = math.huge, -math.huge
	for k = 0, 99 do
		local _, lat, active = Track.crosserAt(track, c, k / 100 * c.period)
		minLat, maxLat = math.min(minLat, lat), math.max(maxLat, lat)
		if active then
			onRoad += 1
		else
			offRoad += 1
		end
	end
	T.ok(minLat < -track.def.width / 2 and maxLat > track.def.width / 2, "crosses the whole road")
	T.ok(onRoad > 30 and offRoad > 20, `on {onRoad}, off {offRoad}`)
end)

T.test("every feature references sensible positions", function()
	local styles = { bed = true, hose = true, log = true, box = true, arch = true }
	for _, def in Tracks.List do
		for _, tn in def.tunnels or {} do
			T.ok(styles[tn.style], `{def.id}: unknown tunnel style {tn.style}`)
			T.ok(tn.from < tn.to and tn.to <= 1, `{def.id}: tunnel range`)
		end
		for _, z in def.zones or {} do
			T.ok(z.kind == "sticky" or z.kind == "slippery" or z.kind == "conveyor" or z.kind == "launch", `{def.id}: zone kind {z.kind}`)
		end
		for _, r in def.ramps or {} do
			T.ok(r.width < def.width, `{def.id}: ramp wider than the road`)
		end
	end
end)
