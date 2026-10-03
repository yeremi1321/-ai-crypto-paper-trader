--!strict
-- Item definitions and the item box roll. Front runners mostly get defensive
-- items and modest traps; the middle gets a mix; the back gets more recovery
-- boosts and stronger attacks.
--
-- Every attack has a warning and a counter: rockets can be blocked with a
-- Bubble Shield or dodged sideways, bombs show a fuse, traps sit still where
-- you can see them, and a hit gives a few seconds of protection so nobody
-- gets juggled.

export type ItemDef = {
	id: string,
	name: string,
	icon: string,
	description: string,
	uses: number,
	front: number, -- roll weight in 1st
	back: number, -- roll weight in last
}

local Items = {}

Items.RouletteTime = 1.5 -- seconds of spinning before an item can be used
Items.BoxRespawn = 3
Items.MaxActiveHazards = 16 -- traps and projectiles on the track at once
Items.MaxTrapsPerRacer = 3

-- Tuning shared by server effects and tests.
Items.SodaBoost = 1.4
Items.ShieldTime = 12
Items.RocketSpeed = 170
Items.RocketLife = 6
Items.BombThrow = 45 -- studs ahead it lands
Items.BombFuse = 1.6
Items.BombRadius = 14
Items.JellyLife = 20
Items.JellyHits = 2
Items.JellySlow = 2
Items.MineLife = 25

Items.Defs = {
	turboSoda = { id = "turboSoda", name = "Turbo Soda", icon = "🥤", description = "A fizzy speed boost.", uses = 1, front = 8, back = 30 },
	windupRocket = { id = "windupRocket", name = "Wind-up Rocket", icon = "🚀", description = "Zooms along the road and pops on the first kart it meets. Hold back to fire it behind you.", uses = 1, front = 10, back = 26 },
	popcornBomb = { id = "popcornBomb", name = "Popcorn Bomb", icon = "🍿", description = "Throw it ahead (or drop it behind). Pops after a short fuse.", uses = 1, front = 14, back = 20 },
	jellyPuddle = { id = "jellyPuddle", name = "Jelly Puddle", icon = "🍮", description = "A sticky wobbly trap dropped behind you. Slows whoever drives in.", uses = 1, front = 26, back = 8 },
	bubbleShield = { id = "bubbleShield", name = "Bubble Shield", icon = "🫧", description = "Blocks one attack, then pops.", uses = 1, front = 24, back = 10 },
	springMine = { id = "springMine", name = "Spring Mine", icon = "🌀", description = "A springy trap dropped behind you. Boings karts into the air.", uses = 1, front = 18, back = 6 },
} :: { [string]: ItemDef }

Items.Order = { "turboSoda", "windupRocket", "popcornBomb", "jellyPuddle", "bubbleShield", "springMine" }

-- Weight of one item for a racer at `place` of `field`.
function Items.weight(id: string, place: number, field: number): number
	local def = Items.Defs[id]
	local f = if field > 1 then (place - 1) / (field - 1) else 0.5
	return math.max(def.front + (def.back - def.front) * f, 0)
end

-- r is a random number in [0, 1).
function Items.roll(place: number, field: number, r: number): string
	local total = 0
	for _, id in Items.Order do
		total += Items.weight(id, place, field)
	end
	local pick = r * total
	for _, id in Items.Order do
		pick -= Items.weight(id, place, field)
		if pick < 0 then
			return id
		end
	end
	return Items.Order[1]
end

-- Odds (0..1) of each item, for tests and an "item odds" screen.
function Items.odds(place: number, field: number): { [string]: number }
	local total = 0
	for _, id in Items.Order do
		total += Items.weight(id, place, field)
	end
	local out = {}
	for _, id in Items.Order do
		out[id] = Items.weight(id, place, field) / total
	end
	return out
end

-- Defensive = shield or trap; used to check the front gets more of them.
Items.Defensive = { bubbleShield = true, jellyPuddle = true, springMine = true }
Items.Recovery = { turboSoda = true, windupRocket = true }

return Items
