local T = require("./TestLib")
local RaceRules = require("../src/shared/RaceRules")

T.test("finishers rank by time, then the rest by progress", function()
	local ranked = RaceRules.rank({
		{ id = "a", finished = false, score = 900 },
		{ id = "b", finished = true, finishTime = 95, score = 0 },
		{ id = "c", finished = true, finishTime = 90, score = 0 },
		{ id = "d", finished = false, score = 1200 },
	})
	T.eq(ranked[1].id, "c")
	T.eq(ranked[2].id, "b")
	T.eq(ranked[3].id, "d")
	T.eq(ranked[4].id, "a")
end)

T.test("points table", function()
	T.eq(RaceRules.pointsFor(1), 15)
	T.eq(RaceRules.pointsFor(8), 1)
	T.eq(RaceRules.pointsFor(9), 0)
end)

T.test("rocket start window", function()
	T.eq(RaceRules.startBoost(-0.6), RaceRules.StartBoostTime)
	T.eq(RaceRules.startBoost(-2), 0)
	T.eq(RaceRules.startBoost(0.1), 0)
	T.eq(RaceRules.startBoost(nil), 0)
end)

T.test("CPU catch-up stays mild", function()
	local base = RaceRules.cpuSpeedFactor(0, 0, 1)
	T.ok(RaceRules.cpuSpeedFactor(2000, 0, 1) > base)
	T.ok(RaceRules.cpuSpeedFactor(2000, 0, 1) <= 1.1)
	T.ok(RaceRules.cpuSpeedFactor(0, 900, 1) < base)
end)

T.test("cup standings break ties by last race", function()
	local s = RaceRules.cupStandings({
		{ id = "a", name = "a", points = 30, lastPlace = 3 },
		{ id = "b", name = "b", points = 30, lastPlace = 1 },
		{ id = "c", name = "c", points = 40, lastPlace = 5 },
	})
	T.eq(s[1].id, "c")
	T.eq(s[2].id, "b")
end)
