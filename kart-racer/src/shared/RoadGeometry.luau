--!strict
-- The road's cross-section, shared by the road builder and its tests.
--
-- Every centreline point gets one frame: its position and a level sideways
-- unit vector (positive = right of travel, the same sign Track.spot uses).
-- The road, curbs, lines, shoulders and barriers all take their edges from
-- these frames, so each piece ends exactly where the next one starts: no
-- gaps on the outside of a bend, no overlapping slabs on the inside.

local Track = require("./Track")

export type Frame = {
	x: number,
	y: number,
	z: number,
	rx: number, -- sideways unit vector (level)
	rz: number,
	turn: number, -- smoothed signed turn here (radians per point, + = right)
}

local RoadGeometry = {}

local function heading(ax: number, az: number, bx: number, bz: number): number
	return math.atan2(bx - ax, bz - az)
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

function RoadGeometry.frames(track: Track.Built): { Frame }
	local pts = track.points
	local n = #pts
	local raw = {}
	for i = 1, n do
		local a, b, c = pts[(i - 2) % n + 1], pts[i], pts[i % n + 1]
		raw[i] = wrapAngle(heading(b.x, b.z, c.x, c.z) - heading(a.x, a.z, b.x, b.z))
	end
	local frames = {}
	for i = 1, n do
		local prev, nextPoint = pts[(i - 2) % n + 1], pts[i % n + 1]
		local tx, tz = nextPoint.x - prev.x, nextPoint.z - prev.z
		local l = math.sqrt(tx * tx + tz * tz)
		tx, tz = tx / l, tz / l
		local sum = 0
		for k = -2, 2 do
			sum += raw[(i - 1 + k) % n + 1]
		end
		local p = pts[i]
		-- heading() grows to the left of travel, so flip it: + = turning right.
		frames[i] = { x = p.x, y = p.y, z = p.z, rx = -tz, rz = tx, turn = -sum / 5 }
	end
	return frames
end

-- A point `lateral` studs to the right of frame f, `lift` above the road.
function RoadGeometry.edge(f: Frame, lateral: number, lift: number?): Track.Vec
	return Track.v(f.x + f.rx * lateral, f.y + (lift or 0), f.z + f.rz * lateral)
end

-- Segments where an edge at `lateral` runs backwards (the bend is tighter
-- than the offset, so a strip there would fold over itself).
function RoadGeometry.folds(frames: { Frame }, lateral: number): { number }
	local out = {}
	local n = #frames
	for i = 1, n do
		local a, b = frames[i], frames[i % n + 1]
		local ea, eb = RoadGeometry.edge(a, lateral), RoadGeometry.edge(b, lateral)
		local dot = (eb.x - ea.x) * (b.x - a.x) + (eb.z - ea.z) * (b.z - a.z)
		if dot <= 0 then
			table.insert(out, i)
		end
	end
	return out
end

-- Corners get red-and-white curbs; straights get painted edge lines.
RoadGeometry.CurbTurn = 0.035 -- about a 340-stud radius at 12-stud spacing
function RoadGeometry.isCorner(f: Frame): boolean
	return math.abs(f.turn) > RoadGeometry.CurbTurn
end

-- Points carrying road over other road (a bridge): something lower passes
-- underneath within `reach` studs. Embankments and pillars skip these.
function RoadGeometry.overpasses(track: Track.Built, reach: number, clearance: number): { [number]: boolean }
	local pts = track.points
	local n = #pts
	local out = {}
	for i, p in pts do
		for j, q in pts do
			local apart = math.min(math.abs(i - j), n - math.abs(i - j))
			if apart > 12 and q.y < p.y - clearance then
				local dx, dz = q.x - p.x, q.z - p.z
				if dx * dx + dz * dz < reach * reach then
					out[i] = true
					break
				end
			end
		end
	end
	return out
end

return RoadGeometry
