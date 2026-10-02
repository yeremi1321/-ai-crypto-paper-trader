local T = require("./TestLib")
local Items = require("../src/shared/Items")

T.test("odds sum to one everywhere", function()
	for field = 1, 8 do
		for place = 1, field do
			local total = 0
			for _, p in Items.odds(place, field) do
				total += p
			end
			T.ok(math.abs(total - 1) < 1e-9)
		end
	end
end)

T.test("the leader never gets chasing items", function()
	local odds = Items.odds(1, 8)
	T.eq(odds.homing, 0)
	T.eq(odds.leaderBolt, 0)
	T.eq(odds.overdrive, 0)
end)

T.test("last place gets more catch-up items than 1st", function()
	local first, last = Items.odds(1, 8), Items.odds(8, 8)
	T.ok(last.overdrive > first.overdrive)
	T.ok(last.nitro > first.nitro)
	T.ok(first.oil > last.oil)
	T.ok(last.leaderBolt > 0)
end)

T.test("roll covers the whole range", function()
	local seen = {}
	for i = 0, 999 do
		seen[Items.roll(8, 8, i / 1000)] = true
	end
	for _, id in { "nitro", "tripleNitro", "homing", "overdrive", "leaderBolt" } do
		T.ok(seen[id], `never rolled {id}`)
	end
	T.ok(Items.Defs[Items.roll(1, 1, 0.999)])
end)
