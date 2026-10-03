local T = require("./TestLib")
local Cosmetics = require("../src/shared/Cosmetics")
local PlayerData = require("../src/shared/PlayerData")
local Rewards = require("../src/shared/Rewards")

local function stats(overrides)
	local s = { id = "u1", name = "Me", place = 1, finished = true, time = 90, bestLap = 30, worstPlace = 1, hitsTaken = 0, shortcutsTaken = 0, jumps = 0, isCpu = false }
	for k, v in overrides or {} do
		s[k] = v
	end
	return s
end

T.test("new players start with coins and free items equipped", function()
	local d = PlayerData.new()
	T.eq(d.coins, PlayerData.StartingCoins)
	T.ok(PlayerData.owns(d, "wheels", "standard"))
	T.ok(not PlayerData.owns(d, "wheels", "monster"))
	T.eq(d.equipped.trail, "smoke")
end)

T.test("buying needs coins, can't double-buy, then can equip", function()
	local d = PlayerData.new()
	T.ok(not PlayerData.equip(d, "wheels", "monster"))
	d.coins = 100
	local ok, err = PlayerData.buy(d, "wheels", "monster")
	T.ok(not ok and string.find(err, "coins"))
	d.coins = 1000
	T.ok(PlayerData.buy(d, "wheels", "monster"))
	T.eq(d.coins, 1000 - Cosmetics.price("wheels", "monster"))
	T.ok(not PlayerData.buy(d, "wheels", "monster"))
	T.ok(PlayerData.equip(d, "wheels", "monster"))
	T.eq(d.equipped.wheels, "monster")
	T.ok(not PlayerData.buy(d, "wheels", "nope"))
	T.ok(not PlayerData.equip(d, "main", 99))
end)

T.test("race rewards: placement coins, awards, mastery, best laps", function()
	local d = PlayerData.new()
	local coins0 = d.coins
	local summary = PlayerData.applyRace(d, "toyroom", 2400, 6, stats({ place = 2, bestLap = 30 }), { "clean" })
	T.eq(summary.coins, Rewards.placeCoins(2, true) + Rewards.AwardCoins + 120) -- cleanRace challenge
	T.eq(d.coins, coins0 + summary.coins)
	T.eq(summary.badge, 2) -- podium -> silver
	T.eq(d.mastery.toyroom.bestLap, 30)
	local again = PlayerData.applyRace(d, "toyroom", 2400, 6, stats({ place = 1, bestLap = 24 }), {})
	T.ok(again.newBestLap)
	T.eq(d.mastery.toyroom.bestLap, 24)
	T.eq(again.badge, 3) -- won with a fast lap -> gold
	T.ok(d.challenges.firstWin and d.challenges.personalBest)
end)

T.test("challenges only pay once", function()
	local d = PlayerData.new()
	PlayerData.applyRace(d, "kitchen", 2700, 6, stats({ place = 1 }), {})
	local second = PlayerData.applyRace(d, "kitchen", 2700, 6, stats({ place = 1 }), {})
	for _, name in second.challenges do
		T.ok(name ~= "Win a race", "first-win challenge paid twice")
	end
end)

T.test("DNF still earns a little; no mastery finish", function()
	local d = PlayerData.new()
	local s = PlayerData.applyRace(d, "backyard", 2600, 6, stats({ finished = false, place = 8, time = nil, bestLap = nil }), {})
	T.eq(s.coins, Rewards.DnfCoins)
	T.eq(d.mastery.backyard.finishes, 0)
end)

T.test("golden tokens pay once each, plus a bonus for all", function()
	local d = PlayerData.new()
	local total = 0
	for i = 1, 3 do
		total += PlayerData.foundToken(d, tostring(i), 3)
	end
	T.eq(PlayerData.foundToken(d, "1", 3), 0)
	T.eq(total, Rewards.TokenCoins * 3 + 300)
	T.ok(d.challenges.tokens)
end)

T.test("awards go to the right racers", function()
	local rows = {
		stats({ id = "a", place = 1, worstPlace = 1, hitsTaken = 2, shortcutsTaken = 0 }),
		stats({ id = "b", place = 2, worstPlace = 7, hitsTaken = 0, shortcutsTaken = 3, jumps = 5 }),
		stats({ id = "c", place = 3, worstPlace = 3, hitsTaken = 0, shortcutsTaken = 3 }),
		stats({ id = "d", place = 4, finished = false, worstPlace = 8, hitsTaken = 0 }),
	}
	local won = {}
	for _, a in Rewards.awards(rows) do
		won[a.id] = a.winner
	end
	T.eq(won.comeback, "b")
	T.eq(won.clean, "b")
	T.eq(won.shortcut, "b") -- tie with c, better place wins
	T.eq(won.flyer, "b")
end)

T.test("old or broken saves are repaired", function()
	local d = PlayerData.migrate({ coins = 50, equipped = { body = "nope", wheels = "monster", main = 99 }, owned = { wheels = {} } })
	T.eq(d.coins, 50)
	T.eq(d.equipped.body, "classic")
	T.eq(d.equipped.wheels, "standard") -- not owned
	T.eq(d.equipped.main, 12)
	T.ok(PlayerData.owns(d, "wheels", "standard"))
	T.eq(PlayerData.migrate("garbage").coins, PlayerData.StartingCoins)
end)

T.test("plate and name text is cleaned", function()
	T.eq(Cosmetics.cleanText("  ZOOM!!  42 ", 8), "ZOOM 42")
	T.eq(Cosmetics.cleanText(nil, 8), "")
	T.eq(#Cosmetics.cleanText("ABCDEFGHIJKLMNOP", 8), 8)
end)
