--!strict
-- Turns a track's control points into a smooth closed centerline, and answers
-- "where along the track is this kart?" for positions, laps, CPU steering and
-- respawning. Pure math on {x, y, z} tables.

export type Vec = { x: number, y: number, z: number }

export type TrackDef = {
	id: string,
	name: string,
	width: number, -- road width in studs
	laps: number,
	controls: { Vec }, -- closed loop, driven in list order; first point is the finish line
	boostPads: { { t: number, offset: number } }, -- t = 0..1 along the lap, offset = -1..1 across
	itemRows: { number }, -- t values for rows of item boxes
	theme: string,
	-- Multiplies every control point (x, y and z), so the whole layout grows
	-- without changing its shape or how steep the hills are. Default 1.
	scale: number?,
}

export type Built = {
	def: TrackDef,
	points: { Vec }, -- dense samples; points[1] is on the finish line
	cum: { number }, -- distance from the finish line to each point
	length: number,
	sectors: number,
}

local Track = {}

Track.Spacing = 12
Track.Sectors = 12
Track.ShoulderWidth = 10

local function v(x: number, y: number, z: number): Vec
	return { x = x, y = y, z = z }
end
Track.v = v

local function sub(a: Vec, b: Vec): Vec
	return v(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function len(a: Vec): number
	return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
end

local function lerp(a: Vec, b: Vec, t: number): Vec
	return v(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
end

-- Uniform Catmull-Rom between p1 and p2.
local function catmull(p0: Vec, p1: Vec, p2: Vec, p3: Vec, t: number): Vec
	local t2, t3 = t * t, t * t * t
	local function c(a: number, b: number, cc: number, d: number): number
		return 0.5 * ((2 * b) + (-a + cc) * t + (2 * a - 5 * b + 4 * cc - d) * t2 + (-a + 3 * b - 3 * cc + d) * t3)
	end
	return v(c(p0.x, p1.x, p2.x, p3.x), c(p0.y, p1.y, p2.y, p3.y), c(p0.z, p1.z, p2.z, p3.z))
end

function Track.build(def: TrackDef): Built
	local scale = def.scale or 1
	local ctrl = {}
	for i, c in def.controls do
		ctrl[i] = v(c.x * scale, c.y * scale, c.z * scale)
	end
	local n = #ctrl
	-- Fine samples first, then resample evenly by distance.
	local fine: { Vec } = {}
	for i = 1, n do
		local p0, p1 = ctrl[(i - 2) % n + 1], ctrl[i]
		local p2, p3 = ctrl[i % n + 1], ctrl[(i + 1) % n + 1]
		for s = 0, 19 do
			table.insert(fine, catmull(p0, p1, p2, p3, s / 20))
		end
	end
	table.insert(fine, fine[1])

	local fineCum = { 0 }
	for i = 2, #fine do
		fineCum[i] = fineCum[i - 1] + len(sub(fine[i], fine[i - 1]))
	end
	local total = fineCum[#fine]
	local count = math.max(8, math.floor(total / Track.Spacing + 0.5))
	local step = total / count

	local points: { Vec } = {}
	local cum: { number } = {}
	local j = 1
	for k = 0, count - 1 do
		local d = k * step
		while fineCum[j + 1] < d do
			j += 1
		end
		local segLen = fineCum[j + 1] - fineCum[j]
		local t = if segLen > 0 then (d - fineCum[j]) / segLen else 0
		table.insert(points, lerp(fine[j], fine[j + 1], t))
		table.insert(cum, d)
	end

	return { def = def, points = points, cum = cum, length = total, sectors = Track.Sectors }
end

function Track.pointCount(track: Built): number
	return #track.points
end

-- Point and unit tangent at distance d along the lap (wraps).
function Track.at(track: Built, d: number): (Vec, Vec)
	local n = #track.points
	d %= track.length
	local step = track.length / n
	local i = math.floor(d / step) + 1
	local a, b = track.points[i], track.points[i % n + 1]
	local t = (d - track.cum[i]) / step
	local dir = sub(b, a)
	local l = len(dir)
	return lerp(a, b, t), v(dir.x / l, dir.y / l, dir.z / l)
end

export type Projection = { index: number, distance: number, lateral: number, gap: number }

-- Nearest spot on the centerline. `hint` (a previous index) keeps the search
-- local so crossing bridges don't snap to the road below.
function Track.project(track: Built, pos: Vec, hint: number?): Projection
	local n = #track.points
	local function test(i: number, best: Projection?): Projection?
		local a, b = track.points[i], track.points[i % n + 1]
		local ab = sub(b, a)
		local ap = sub(pos, a)
		local abLen2 = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z
		local t = math.clamp((ap.x * ab.x + ap.y * ab.y + ap.z * ab.z) / abLen2, 0, 1)
		local closest = lerp(a, b, t)
		local gap = len(sub(pos, closest))
		if best and gap >= best.gap then
			return best
		end
		-- Lateral: positive = right of travel direction (flat cross product).
		local fx, fz = ab.x, ab.z
		local fl = math.sqrt(fx * fx + fz * fz)
		local lateral = if fl > 0 then ((pos.x - closest.x) * -fz + (pos.z - closest.z) * fx) / fl else 0
		return { index = i, distance = track.cum[i] + t * math.sqrt(abLen2), lateral = lateral, gap = gap }
	end

	local best: Projection? = nil
	if hint then
		for k = -12, 12 do
			best = test((hint - 1 + k) % n + 1, best)
		end
		if best and best.gap <= track.def.width * 1.5 then
			return best
		end
	end
	for i = 1, n do
		best = test(i, best)
	end
	return best :: Projection
end

function Track.sectorOf(track: Built, d: number): number
	return math.floor((d % track.length) / track.length * track.sectors)
end

function Track.sectorStart(track: Built, sector: number): number
	return sector / track.sectors * track.length
end

---------------------------------------------------------------------------
-- Layout shared by the builder, the server and the tests.
---------------------------------------------------------------------------
Track.PadLength = 24
Track.PadWidth = 16

export type Pad = { distance: number, lateral: number }

function Track.pads(track: Built): { Pad }
	local out = {}
	local half = track.def.width / 2 - Track.PadWidth / 2 - 2
	for _, pad in track.def.boostPads do
		table.insert(out, { distance = pad.t * track.length, lateral = pad.offset * half })
	end
	return out
end

-- Four item boxes across the road for each row.
function Track.itemBoxes(track: Built): { Pad }
	local out = {}
	local spread = track.def.width / 2 - 8
	for _, t in track.def.itemRows do
		for i = 0, 3 do
			table.insert(out, { distance = t * track.length, lateral = -spread + i * (spread * 2 / 3) })
		end
	end
	return out
end

-- World position of a spot given by distance along the lap and lateral offset.
function Track.spot(track: Built, distance: number, lateral: number): Vec
	local p, tan = Track.at(track, distance)
	local tl = math.sqrt(tan.x * tan.x + tan.z * tan.z)
	return v(p.x - tan.z / tl * lateral, p.y, p.z + tan.x / tl * lateral)
end

-- "road" | "boost" | "offroad" (the grass shoulder) | "wall" (past the barrier).
function Track.surfaceAt(track: Built, proj: Projection): string
	local half = track.def.width / 2
	local lat = math.abs(proj.lateral)
	if lat > half + Track.ShoulderWidth then
		return "wall"
	elseif lat > half then
		return "offroad"
	end
	for _, pad in Track.pads(track) do
		local along = (proj.distance - pad.distance + track.length / 2) % track.length - track.length / 2
		if math.abs(along) <= Track.PadLength / 2 and math.abs(proj.lateral - pad.lateral) <= Track.PadWidth / 2 then
			return "boost"
		end
	end
	return "road"
end

-- Starting grid: two columns behind the finish line, staggered.
function Track.gridSpot(track: Built, slot: number): (Vec, number)
	local row = (slot - 1) // 2
	local col = (slot - 1) % 2
	local distance = track.length - 16 - row * 14 - col * 7
	local lateral = (col * 2 - 1) * track.def.width * 0.22
	return Track.spot(track, distance, lateral), distance
end

---------------------------------------------------------------------------
-- Lap progress. Laps only count when every sector is passed in order, so
-- cutting across the infield or reversing over the line never helps.
---------------------------------------------------------------------------
export type Progress = {
	lap: number, -- 0 on the grid (behind the line), 1 after first crossing...
	sector: number,
	distance: number, -- distance along the lap, kept inside the current sector
	index: number, -- last projected point, used as the next search hint
}

function Track.newProgress(track: Built, gridDistance: number): Progress
	return {
		lap = 0,
		sector = Track.sectorOf(track, gridDistance),
		distance = gridDistance % track.length,
		index = 1,
	}
end

-- Returns true when this update crossed the finish line forwards.
function Track.updateProgress(track: Built, p: Progress, proj: Projection): boolean
	local k = track.sectors
	local s = Track.sectorOf(track, proj.distance)
	p.index = proj.index
	local crossed = false
	if s == (p.sector + 1) % k then
		if s == 0 then
			p.lap += 1
			crossed = true
		end
		p.sector = s
	elseif s == (p.sector - 1) % k then
		if p.sector == 0 then
			p.lap -= 1 -- backed over the line
		end
		p.sector = s
	end
	if s == p.sector then
		p.distance = proj.distance
	end
	return crossed
end

-- One number for ranking racers: higher is further ahead.
function Track.score(track: Built, p: Progress): number
	return p.lap * track.length + p.distance
end

-- Is the kart driving the wrong way? heading is a flat unit vector.
function Track.wrongWay(track: Built, proj: Projection, hx: number, hz: number): boolean
	local _, tan = Track.at(track, proj.distance)
	local tl = math.sqrt(tan.x * tan.x + tan.z * tan.z)
	if tl == 0 then
		return false
	end
	return (hx * tan.x + hz * tan.z) / tl < -0.5
end

return Track
