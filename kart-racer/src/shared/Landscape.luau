--!strict
-- Plans the land around a track: the ground, earth banks under raised road,
-- rolling hills, lakes, distant snow-capped mountains and desert mesas.
-- It's pure data, so tests can check that nothing lands on the road;
-- server/TerrainBuilder turns the plan into Roblox Terrain.
--
-- Each theme's `terrain` table (in Tracks.Themes) sets the materials and
-- counts. A track can also place its own lakes (`lakes = { { x, z, r } }`)
-- and rivers (`rivers = { { r, points = { { x, z }, ... } } }`), in the same
-- units as its control points; the road may cross those on a bridge. A
-- river is a chain of overlapping round pools, which gives it natural,
-- wavy banks.
-- Placement is seeded by the track id, so every server builds the same land.

local RoadGeometry = require("./RoadGeometry")
local Scenery = require("./Scenery")
local Track = require("./Track")
local Tracks = require("./Tracks")

export type Ball = { x: number, y: number, z: number, r: number, material: string }
export type Mesa = { x: number, z: number, r: number, bottom: number, top: number, material: string, band: string? }
export type Lake = { x: number, z: number, r: number, surface: number, shore: string, liquid: string, bridged: boolean }
-- One earth block under the road, from top-centre point a to b, hanging `depth` down.
export type Bank = { ax: number, ay: number, az: number, bx: number, by: number, bz: number, width: number, depth: number }

export type Plan = {
	trackId: string,
	spec: any,
	groundTop: number,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	banks: { Bank },
	bankAt: { [number]: boolean }, -- road points whose verge is terrain
	hills: { Ball },
	mountains: { Ball },
	caps: { Ball },
	mesas: { Mesa },
	lakes: { Lake },
}

local Landscape = {}

Landscape.BankSpread = 1.8 -- each stud of bank height widens its foot by this much

local function rng(seedText: string): () -> number
	local seed = 7
	for i = 1, #seedText do
		seed = (seed * 31 + string.byte(seedText, i)) % 2147483647
	end
	return function(): number
		seed = (seed * 48271) % 2147483647
		return seed / 2147483647
	end
end

-- Flat distance from (x, z) to the nearest road point, and that point's index.
local function nearestRoad(track: Track.Built, x: number, z: number): (number, number)
	local best, index = math.huge, 1
	for i, p in track.points do
		local dx, dz = p.x - x, p.z - z
		local d = dx * dx + dz * dz
		if d < best then
			best, index = d, i
		end
	end
	return math.sqrt(best), index
end

function Landscape.plan(track: Track.Built): Plan?
	local def = track.def
	local theme = Tracks.Themes[def.theme]
	local spec = theme and theme.terrain
	if not spec then
		return nil
	end
	local random = rng(def.id .. ":land")
	local pts = track.points
	local n = #pts
	local half = def.width / 2
	local barrier = half + Track.ShoulderWidth + 1
	local drop = spec.drop or 0.7

	local minY, minX, maxX, minZ, maxZ = math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, p in pts do
		minY = math.min(minY, p.y)
		minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
		minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
	end
	local groundTop = minY - drop
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local extent = math.max(maxX - minX, maxZ - minZ) / 2

	local plan: Plan = {
		trackId = def.id,
		spec = spec,
		groundTop = groundTop,
		minX = 0,
		maxX = 0,
		minZ = 0,
		maxZ = 0,
		banks = {},
		bankAt = {},
		hills = {},
		mountains = {},
		caps = {},
		mesas = {},
		lakes = {},
	}

	-- How far a raised road's bank reaches sideways at point i.
	local function bankReach(i: number): number
		return barrier + (pts[i].y - minY) * Landscape.BankSpread / 2
	end
	local landmarks = Scenery.setPieceSpots(track)
	local function clearOfRoad(x: number, z: number, radius: number, margin: number): boolean
		local d, i = nearestRoad(track, x, z)
		if d <= radius + bankReach(i) + margin or Scenery.shortcutDistance(track, x, z) <= radius + margin then
			return false
		end
		for _, spot in landmarks do
			local dx, dz = spot.x - x, spot.z - z
			if math.sqrt(dx * dx + dz * dz) < radius + Scenery.SetPieceRadius + margin then
				return false
			end
		end
		return true
	end

	-- Lakes the track asks for (the road may bridge them), then random ones.
	local scale = def.scale or 1
	local ownLakes = table.clone((def :: any).lakes or {})
	for _, river in (def :: any).rivers or {} do
		local pts = river.points
		for k = 1, #pts - 1 do
			local ax, az, bx, bz = pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]
			local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
			local steps = math.max(1, math.ceil(length / (river.r * 0.9)))
			for step = 0, steps - (if k < #pts - 1 then 1 else 0) do
				local f = step / steps
				-- Alternate the width a little so the banks aren't ruler-straight.
				local wobble = 1 + 0.18 * math.sin((k * 7 + step) * 1.7)
				table.insert(ownLakes, { x = ax + (bx - ax) * f, z = az + (bz - az) * f, r = river.r * wobble })
			end
		end
	end
	for _, l in ownLakes do
		table.insert(plan.lakes, {
			x = l.x * scale,
			z = l.z * scale,
			r = l.r * scale,
			surface = groundTop - 1.4,
			shore = (spec.lakes and spec.lakes.shore) or "Sand",
			liquid = (spec.lakes and spec.lakes.liquid) or "Water",
			bridged = true,
		})
	end
	local function clearOfLakes(x: number, z: number, radius: number, margin: number): boolean
		for _, l in plan.lakes do
			local dx, dz = l.x - x, l.z - z
			if math.sqrt(dx * dx + dz * dz) < l.r + radius + margin then
				return false
			end
		end
		return true
	end
	local lakeRule = spec.lakes
	if lakeRule then
		local placed, tries = 0, 0
		while placed < (lakeRule.count or 0) and tries < 400 do
			tries += 1
			local r = lakeRule.min + random() * (lakeRule.max - lakeRule.min)
			local a = random() * math.pi * 2
			local dist = random() * (extent + 220)
			local x, z = cx + math.cos(a) * dist, cz + math.sin(a) * dist
			if clearOfRoad(x, z, r, 30) and clearOfLakes(x, z, r, 40) then
				placed += 1
				table.insert(plan.lakes, { x = x, z = z, r = r, surface = groundTop - 1.4, shore = lakeRule.shore or "Sand", liquid = lakeRule.liquid or "Water", bridged = false })
			end
		end
	end

	-- Earth banks: raised road sits on terrain instead of floating, except
	-- over other road (a bridge) or over a lake the track crosses.
	local overpass = RoadGeometry.overpasses(track, barrier + 40, 6)
	for i, p in pts do
		local overLake = false
		for _, l in plan.lakes do
			if l.bridged then
				local dx, dz = l.x - p.x, l.z - p.z
				if math.sqrt(dx * dx + dz * dz) < l.r + barrier + 8 then
					overLake = true
				end
			end
		end
		plan.bankAt[i] = spec.embank ~= false and not overpass[i] and not overLake
	end
	if spec.embank ~= false then
		local frames = RoadGeometry.frames(track)
		for i = 1, n do
			local j = i % n + 1
			if plan.bankAt[i] and plan.bankAt[j] then
				local a, b = frames[i], frames[j]
				local height = math.max(a.y, b.y) - minY
				-- Road at ground level needs nothing: the slab is its verge.
				local tiers = if height < 0.5 then 0 elseif height < 3 then 1 else 3
				local mx, mz = (a.x + b.x) / 2, (a.z + b.z) / 2
				for k = 0, tiers - 1 do
					local lower = height * k / 3
					local width = (barrier + 4) * 2 + lower * Landscape.BankSpread
					-- Stop short of any other stretch of road lower than this tier,
					-- so a hill section's bank never buries the road beside it.
					local tierTop = math.max(a.y, b.y) - drop - lower
					for q = 1, n do
						local apart = math.min(math.abs(q - i), n - math.abs(q - i))
						local other = pts[q]
						if apart > 6 and other.y < tierTop + 2 then
							local dx, dz = other.x - mx, other.z - mz
							local room = math.sqrt(dx * dx + dz * dz) - barrier - 6
							width = math.min(width, math.max((barrier + 4) * 2, room * 2))
						end
					end
					table.insert(plan.banks, {
						ax = a.x,
						ay = a.y - drop - lower,
						az = a.z,
						bx = b.x,
						by = b.y - drop - lower,
						bz = b.z,
						width = width,
						depth = math.max(4, a.y - drop - lower - groundTop + 6),
					})
				end
			end
		end
	end

	-- Earth under shortcut paths, so a shortcut across a valley sits on a
	-- ridge instead of floating.
	for _, sc in def.shortcuts or {} do
		local a, b = Track.shortcutEnds(track, sc)
		local top = math.min(a.y, b.y) - drop
		if top > groundTop + 0.5 then
			table.insert(plan.banks, { ax = a.x, ay = a.y - drop, az = a.z, bx = b.x, by = b.y - drop, bz = b.z, width = sc.width + 12, depth = top - groundTop + 6 })
		end
	end

	-- Rolling hills, clear of the road and its banks.
	local hillRule = spec.hills
	if hillRule then
		local placed, tries = 0, 0
		while placed < hillRule.count and tries < hillRule.count * 30 do
			tries += 1
			local r = hillRule.min + random() * (hillRule.max - hillRule.min)
			local a = random() * math.pi * 2
			local dist = random() * (extent + 320)
			local x, z = cx + math.cos(a) * dist, cz + math.sin(a) * dist
			local foot = r * 0.79 -- footprint radius of a cap 0.38r tall
			if clearOfRoad(x, z, foot, 25) and clearOfLakes(x, z, foot, 15) then
				placed += 1
				table.insert(plan.hills, { x = x, y = groundTop - r * 0.62, z = z, r = r, material = hillRule.material or spec.ground })
			end
		end
	end

	-- Desert mesas: flat-topped rock with a coloured band.
	local mesaRule = spec.mesas
	if mesaRule then
		local placed, tries = 0, 0
		while placed < mesaRule.count and tries < mesaRule.count * 40 do
			tries += 1
			local r = mesaRule.min + random() * (mesaRule.max - mesaRule.min)
			local a = random() * math.pi * 2
			local dist = extent * 0.3 + random() * (extent + (mesaRule.ring or 300))
			local x, z = cx + math.cos(a) * dist, cz + math.sin(a) * dist
			if clearOfRoad(x, z, r, 40) and clearOfLakes(x, z, r, 20) then
				placed += 1
				local height = mesaRule.minHeight + random() * (mesaRule.maxHeight - mesaRule.minHeight)
				table.insert(plan.mesas, { x = x, z = z, r = r, bottom = groundTop - 4, top = groundTop + height, material = mesaRule.material, band = mesaRule.band })
			end
		end
	end

	-- Distant mountains in a ring: a main mass, two shoulders, a peak and a cap.
	-- An optional `outer` ring sits further out: bigger, hazier peaks behind.
	local reach = extent + 200
	local rings = {}
	if spec.mountains then
		table.insert(rings, spec.mountains)
		if spec.mountains.outer then
			local outer = table.clone(spec.mountains.outer)
			outer.material = outer.material or spec.mountains.material
			outer.cap = if outer.cap ~= nil then outer.cap else spec.mountains.cap
			table.insert(rings, outer)
		end
	end
	for _, mountainRule in rings do
		local count = mountainRule.count
		for k = 0, count - 1 do
			local r = mountainRule.min + random() * (mountainRule.max - mountainRule.min)
			local a = (k + random() * 0.6) / count * math.pi * 2
			local dist = extent + (mountainRule.ring or 400) + random() * 260
			local x, z = cx + math.cos(a) * dist, cz + math.sin(a) * dist
			if clearOfRoad(x, z, r * 1.25, 60) then
				local material = mountainRule.material or "Rock"
				local baseY = groundTop - r * 0.35
				table.insert(plan.mountains, { x = x, y = baseY, z = z, r = r, material = material })
				local sx, sz = -math.sin(a), math.cos(a)
				for _, side in { -1, 1 } do
					local o = r * (0.65 + random() * 0.2)
					table.insert(plan.mountains, { x = x + sx * side * o, y = groundTop - r * 0.25, z = z + sz * side * o, r = r * (0.5 + random() * 0.15), material = material })
				end
				local peakY = baseY + r * 0.72
				table.insert(plan.mountains, { x = x + (random() - 0.5) * r * 0.2, y = peakY, z = z + (random() - 0.5) * r * 0.2, r = r * 0.45, material = material })
				if mountainRule.cap then
					table.insert(plan.caps, { x = x, y = baseY + r * 0.98, z = z, r = r * 0.3, material = mountainRule.cap })
				end
				reach = math.max(reach, dist + r * 1.3)
			end
		end
	end

	-- Ground slab out to the horizon features.
	local margin = math.max(reach - extent, 400) + 60
	plan.minX, plan.maxX = cx - extent - margin, cx + extent + margin
	plan.minZ, plan.maxZ = cz - extent - margin, cz + extent + margin
	return plan
end

-- Height of the land at (x, z), or nil over water (props skip those spots).
function Landscape.groundAt(plan: Plan, x: number, z: number): number?
	for _, l in plan.lakes do
		local dx, dz = l.x - x, l.z - z
		if dx * dx + dz * dz < l.r * l.r then
			return nil
		end
	end
	local h = plan.groundTop
	for _, bank in plan.banks do
		local abx, abz = bank.bx - bank.ax, bank.bz - bank.az
		local len2 = abx * abx + abz * abz
		if len2 > 0 then
			-- The block spans its segment plus 2 studs at each end (TerrainBuilder).
			local len = math.sqrt(len2)
			local t = ((x - bank.ax) * abx + (z - bank.az) * abz) / len2
			if t * len >= -2 and t * len <= len + 2 then
				local px, pz = bank.ax + abx * t, bank.az + abz * t
				local dx, dz = x - px, z - pz
				if dx * dx + dz * dz < (bank.width / 2) ^ 2 then
					h = math.max(h, bank.ay + (bank.by - bank.ay) * math.clamp(t, 0, 1))
				end
			end
		end
	end
	local function ball(b: Ball)
		local dx, dz = b.x - x, b.z - z
		local d2 = dx * dx + dz * dz
		if d2 < b.r * b.r then
			h = math.max(h, b.y + math.sqrt(b.r * b.r - d2))
		end
	end
	for _, b in plan.hills do
		ball(b)
	end
	for _, b in plan.mountains do
		ball(b)
	end
	for _, m in plan.mesas do
		local dx, dz = m.x - x, m.z - z
		if dx * dx + dz * dz < m.r * m.r then
			h = math.max(h, m.top)
		end
	end
	return h
end

return Landscape
