--!strict
-- Decides where scenery goes around a track: trees and grandstands on Sunny
-- Loop, rocks and mesas in the canyon, towers and lamps in the neon city.
-- Placement is seeded by the track id, so every server builds the same
-- scenery, and nothing is ever placed on (or too close to) the road.
--
-- To get more or fewer props, change the counts in Scenery.Themes.

local Track = require("./Track")

export type Prop = {
	kind: string,
	x: number,
	y: number,
	z: number,
	size: number, -- 1 = normal, props scale from this
	yaw: number,
}

local Scenery = {}

-- kind = how many, how close to the barrier (min, max studs), size range, footprint radius.
type Rule = { kind: string, count: number, near: number, far: number, minSize: number, maxSize: number, radius: number }

Scenery.Themes = {
	fortress = {
		{ kind = "rock", count = 130, near = 15, far = 230, minSize = 0.8, maxSize = 2, radius = 8 },
		{ kind = "mesa", count = 18, near = 70, far = 300, minSize = 0.8, maxSize = 1.4, radius = 35 },
	},
	sunny = {
		{ kind = "tree", count = 150, near = 12, far = 220, minSize = 0.8, maxSize = 1.5, radius = 8 },
		{ kind = "pine", count = 60, near = 30, far = 260, minSize = 0.9, maxSize = 1.6, radius = 7 },
		{ kind = "farTree", count = 200, near = 260, far = 650, minSize = 1, maxSize = 1.8, radius = 9 },
		{ kind = "bush", count = 80, near = 6, far = 120, minSize = 0.7, maxSize = 1.3, radius = 4 },
		{ kind = "billboard", count = 8, near = 14, far = 30, minSize = 1, maxSize = 1, radius = 14 },
		{ kind = "flag", count = 18, near = 4, far = 10, minSize = 1, maxSize = 1, radius = 3 },
	},
	-- Mesas are terrain here (Landscape), so only the smaller things are props.
	canyon = {
		{ kind = "rock", count = 110, near = 8, far = 200, minSize = 0.6, maxSize = 1.8, radius = 9 },
		{ kind = "cactus", count = 70, near = 8, far = 160, minSize = 0.8, maxSize = 1.4, radius = 4 },
	},
	-- farTree = a cheap two-part tree for the distant forest (Props.luau).
	highland = {
		{ kind = "tree", count = 170, near = 10, far = 240, minSize = 0.9, maxSize = 1.6, radius = 8 },
		{ kind = "pine", count = 60, near = 20, far = 260, minSize = 0.9, maxSize = 1.6, radius = 7 },
		{ kind = "rock", count = 40, near = 12, far = 200, minSize = 0.6, maxSize = 1.6, radius = 8 },
		{ kind = "flag", count = 16, near = 4, far = 10, minSize = 1, maxSize = 1, radius = 3 },
		{ kind = "farTree", count = 280, near = 260, far = 700, minSize = 1, maxSize = 1.8, radius = 9 },
	},
	alpine = {
		{ kind = "pine", count = 240, near = 10, far = 260, minSize = 0.8, maxSize = 1.7, radius = 7 },
		{ kind = "farTree", count = 220, near = 260, far = 650, minSize = 1, maxSize = 1.8, radius = 9 },
		{ kind = "rock", count = 50, near = 12, far = 220, minSize = 0.6, maxSize = 1.6, radius = 8 },
		{ kind = "flag", count = 14, near = 4, far = 10, minSize = 1, maxSize = 1, radius = 3 },
	},
	-- Tiny racers, oversized world: everything here is giant.
	toyroom = {
		{ kind = "toyBlock", count = 70, near = 10, far = 220, minSize = 0.8, maxSize = 1.6, radius = 10 },
		{ kind = "toyBall", count = 30, near = 14, far = 240, minSize = 0.8, maxSize = 1.5, radius = 12 },
		{ kind = "crayon", count = 40, near = 6, far = 160, minSize = 0.9, maxSize = 1.3, radius = 6 },
		{ kind = "book", count = 24, near = 20, far = 240, minSize = 0.9, maxSize = 1.4, radius = 18 },
	},
	kitchen = {
		{ kind = "fruit", count = 60, near = 8, far = 200, minSize = 0.8, maxSize = 1.5, radius = 9 },
		{ kind = "jar", count = 26, near = 16, far = 220, minSize = 0.9, maxSize = 1.5, radius = 12 },
		{ kind = "cookie", count = 40, near = 6, far = 160, minSize = 0.8, maxSize = 1.3, radius = 7 },
		{ kind = "shaker", count = 20, near = 10, far = 180, minSize = 1, maxSize = 1.4, radius = 6 },
	},
	backyard = {
		{ kind = "grassBlade", count = 170, near = 4, far = 200, minSize = 0.7, maxSize = 1.6, radius = 3 },
		{ kind = "flower", count = 60, near = 8, far = 220, minSize = 0.8, maxSize = 1.5, radius = 7 },
		{ kind = "pebble", count = 50, near = 4, far = 180, minSize = 0.6, maxSize = 1.6, radius = 7 },
		{ kind = "mushroom", count = 26, near = 10, far = 200, minSize = 0.8, maxSize = 1.5, radius = 8 },
		{ kind = "clover", count = 50, near = 2, far = 120, minSize = 0.8, maxSize = 1.3, radius = 4 },
	},
	neon = {
		{ kind = "tower", count = 80, near = 30, far = 300, minSize = 0.7, maxSize = 2.2, radius = 24 },
		{ kind = "lamp", count = 60, near = 3, far = 6, minSize = 1, maxSize = 1, radius = 2 },
		{ kind = "billboard", count = 10, near = 14, far = 30, minSize = 1, maxSize = 1, radius = 14 },
	},
} :: { [string]: { Rule } }

-- Small deterministic random generator (exact in doubles).
local function rng(seedText: string): () -> number
	local seed = 1
	for i = 1, #seedText do
		seed = (seed * 31 + string.byte(seedText, i)) % 2147483647
	end
	return function(): number
		seed = (seed * 48271) % 2147483647
		return seed / 2147483647
	end
end

-- Distance from the centerline to just outside the barrier.
function Scenery.barrier(track: Track.Built): number
	return track.def.width / 2 + Track.ShoulderWidth + 1
end

Scenery.SetPieceRadius = 40

-- Where each landmark from the track's setPieces goes, and which way it faces
-- (toward the road). side 0 puts it over the road itself (e.g. an arch).
function Scenery.setPieceSpots(track: Track.Built): { Prop }
	local out = {}
	local barrier = Scenery.barrier(track)
	for _, sp in track.def.setPieces or {} do
		local d = sp.t * track.length
		local gap = sp.gap or 30
		local lateral = if sp.side == 0 then 0 else sp.side * (barrier + gap)
		local spot = Track.spot(track, d, lateral)
		local _, tan = Track.at(track, d)
		local faceRoad = math.atan2(tan.x, tan.z) + (if sp.side > 0 then math.pi / 2 else -math.pi / 2)
		table.insert(out, { kind = sp.kind, x = spot.x, y = spot.y, z = spot.z, size = 1, yaw = faceRoad })
	end
	return out
end

-- Flat distance from a point to a shortcut's path.
local function shortcutDistance(track: Track.Built, x: number, z: number): number
	local best = math.huge
	for _, sc in track.def.shortcuts or {} do
		local a, b = Track.shortcutEnds(track, sc)
		local abx, abz = b.x - a.x, b.z - a.z
		local t = math.clamp(((x - a.x) * abx + (z - a.z) * abz) / (abx * abx + abz * abz), 0, 1)
		local dx, dz = x - (a.x + abx * t), z - (a.z + abz * t)
		best = math.min(best, math.sqrt(dx * dx + dz * dz) - sc.width / 2)
	end
	return best
end
Scenery.shortcutDistance = shortcutDistance

function Scenery.place(track: Track.Built): { Prop }
	local rules = Scenery.Themes[track.def.theme] or {}
	local random = rng(track.def.id)
	local barrier = Scenery.barrier(track)
	local minY = math.huge
	for _, p in track.points do
		minY = math.min(minY, p.y)
	end

	local props: { Prop } = {}
	local placedRadius: { number } = {}
	local reserved = Scenery.setPieceSpots(track)

	local function clear(x: number, z: number, radius: number): boolean
		-- Away from every part of the track (matters where the track loops back).
		for _, p in track.points do
			local dx, dz = p.x - x, p.z - z
			local need = barrier + radius + 2
			if dx * dx + dz * dz < need * need then
				return false
			end
		end
		for i, other in props do
			local dx, dz = other.x - x, other.z - z
			local need = placedRadius[i] + radius
			if dx * dx + dz * dz < need * need then
				return false
			end
		end
		-- Keep shortcut paths and landmark spots clear.
		if shortcutDistance(track, x, z) < radius + 6 then
			return false
		end
		for _, sp in reserved do
			local dx, dz = sp.x - x, sp.z - z
			local need = Scenery.SetPieceRadius + radius
			if dx * dx + dz * dz < need * need then
				return false
			end
		end
		return true
	end

	for _, rule in rules do
		local placed, attempts = 0, 0
		while placed < rule.count and attempts < rule.count * 12 do
			attempts += 1
			local d = random() * track.length
			local side = if random() < 0.5 then -1 else 1
			local size = rule.minSize + random() * (rule.maxSize - rule.minSize)
			local radius = rule.radius * size
			local lateral = side * (barrier + radius + rule.near + random() * (rule.far - rule.near))
			local spot = Track.spot(track, d, lateral)
			if clear(spot.x, spot.z, radius) then
				local _, tan = Track.at(track, d)
				-- Billboards and flags face the road; everything else is random.
				local faceRoad = rule.kind == "billboard" or rule.kind == "flag" or rule.kind == "lamp"
				local yaw = if faceRoad then math.atan2(tan.x, tan.z) + (if side > 0 then math.pi / 2 else -math.pi / 2) else random() * math.pi * 2
				table.insert(props, { kind = rule.kind, x = spot.x, y = minY, z = spot.z, size = size, yaw = yaw })
				table.insert(placedRadius, radius)
				placed += 1
			end
		end
	end

	-- Grandstands either side of the start line.
	local _, tan = Track.at(track, 0)
	for _, side in { -1, 1 } do
		local lateral = side * (barrier + 18)
		local spot = Track.spot(track, 30, lateral)
		table.insert(props, {
			kind = "grandstand",
			x = spot.x,
			y = minY,
			z = spot.z,
			size = 1,
			yaw = math.atan2(tan.x, tan.z) + (if side > 0 then math.pi / 2 else -math.pi / 2),
		})
	end
	return props
end

return Scenery
