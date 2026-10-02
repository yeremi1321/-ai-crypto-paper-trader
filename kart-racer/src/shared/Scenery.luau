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
	sunny = {
		{ kind = "tree", count = 170, near = 12, far = 220, minSize = 0.8, maxSize = 1.5, radius = 8 },
		{ kind = "bush", count = 80, near = 6, far = 120, minSize = 0.7, maxSize = 1.3, radius = 4 },
		{ kind = "billboard", count = 8, near = 14, far = 30, minSize = 1, maxSize = 1, radius = 14 },
		{ kind = "flag", count = 18, near = 4, far = 10, minSize = 1, maxSize = 1, radius = 3 },
	},
	canyon = {
		{ kind = "mesa", count = 22, near = 60, far = 320, minSize = 0.8, maxSize = 1.8, radius = 40 },
		{ kind = "rock", count = 110, near = 8, far = 200, minSize = 0.6, maxSize = 1.8, radius = 9 },
		{ kind = "cactus", count = 70, near = 8, far = 160, minSize = 0.8, maxSize = 1.4, radius = 4 },
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
