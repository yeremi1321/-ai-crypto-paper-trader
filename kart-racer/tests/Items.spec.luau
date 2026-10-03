local T = require("./TestLib")
local Items = require("../src/shared/Items")

T.test("six starting items, each with an icon", function()
	T.eq(#Items.Order, 6)
	for _, id in Items.Order do
		local def = Items.Defs[id]
		T.ok(def and def.icon ~= "" and def.name ~= "", id)
	end
end)

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

T.test("front gets more defence, back gets more recovery and attacks", function()
	local first, middle, last = Items.odds(1, 8), Items.odds(4, 8), Items.odds(8, 8)
	local function sum(odds, set)
		local s = 0
		for id in set do
			s += odds[id]
		end
		return s
	end
	T.ok(sum(first, Items.Defensive) > sum(last, Items.Defensive))
	T.ok(sum(last, Items.Recovery) > sum(first, Items.Recovery))
	-- The middle is a genuine mix.
	T.ok(sum(middle, Items.Defensive) > 0.3 and sum(middle, Items.Recovery) > 0.3)
end)

T.test("roll covers every item somewhere in the field", function()
	local seen = {}
	for _, place in { 1, 4, 8 } do
		for i = 0, 999 do
			seen[Items.roll(place, 8, i / 1000)] = true
		end
	end
	for _, id in Items.Order do
		T.ok(seen[id], `never rolled {id}`)
	end
end)
