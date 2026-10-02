--!strict
-- Item definitions and the item box roll. Drivers near the back get stronger
-- catch-up items; the leader mostly gets defensive ones.

export type ItemDef = {
	id: string,
	name: string,
	description: string,
	uses: number,
	front: number, -- roll weight when in 1st
	back: number, -- roll weight when in last
}

local Items = {}

Items.RouletteTime = 1.5 -- seconds of spinning before an item can be used
Items.BoxRespawn = 3

Items.Defs = {
	nitro = { id = "nitro", name = "Nitro", description = "A quick speed boost.", uses = 1, front = 10, back = 22 },
	tripleNitro = { id = "tripleNitro", name = "Triple Nitro", description = "Three boosts.", uses = 3, front = 0, back = 18 },
	oil = { id = "oil", name = "Oil Slick", description = "Drop it behind you. Anyone who drives over it spins out.", uses = 1, front = 35, back = 4 },
	bouncer = { id = "bouncer", name = "Bouncer", description = "Fires straight ahead and bounces off walls.", uses = 1, front = 35, back = 10 },
	homing = { id = "homing", name = "Homing Rocket", description = "Chases the racer just ahead of you.", uses = 1, front = 0, back = 24 },
	leaderBolt = { id = "leaderBolt", name = "Leader Bolt", description = "Flies over everyone and strikes 1st place.", uses = 1, front = 0, back = 7 },
	overdrive = { id = "overdrive", name = "Overdrive", description = "Six seconds of speed. Nothing can hit you.", uses = 1, front = 0, back = 15 },
} :: { [string]: ItemDef }

Items.Order = { "nitro", "tripleNitro", "oil", "bouncer", "homing", "leaderBolt", "overdrive" }

-- Weight of one item for a racer at `place` of `field`.
function Items.weight(id: string, place: number, field: number): number
	local def = Items.Defs[id]
	local f = if field > 1 then (place - 1) / (field - 1) else 0.5
	local w = def.front + (def.back - def.front) * f
	if place == 1 and (id == "homing" or id == "leaderBolt") then
		return 0 -- nobody ahead to hit
	end
	if id == "leaderBolt" and f < 0.5 then
		return 0
	end
	return math.max(w, 0)
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
	return "nitro"
end

-- Odds (0..1) of each item, for tests and a future "item odds" screen.
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

return Items
