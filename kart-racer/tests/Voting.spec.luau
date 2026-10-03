local T = require("./TestLib")
local Voting = require("../src/shared/Voting")

local function seq(values)
	local i = 0
	return function()
		i = i % #values + 1
		return values[i]
	end
end

T.test("three different options, avoiding the last track", function()
	local pool = { "a", "b", "c", "d", "e" }
	for trial = 1, 30 do
		local opts = Voting.pickOptions(pool, 3, math.random, "c")
		T.eq(#opts, 3)
		T.ok(not table.find(opts, "c"), "repeated the last track")
		T.ok(opts[1] ~= opts[2] and opts[2] ~= opts[3] and opts[1] ~= opts[3], `duplicate in trial {trial}`)
	end
end)

T.test("small pools still offer the last track when needed", function()
	local opts = Voting.pickOptions({ "a", "b", "c" }, 3, math.random, "a")
	T.eq(#opts, 3)
	T.ok(table.find(opts, "a"))
end)

T.test("most votes wins; changing your vote moves it", function()
	local votes = { [1] = "b", [2] = "b", [3] = "a" }
	T.eq(Voting.winner({ "a", "b", "c" }, votes, math.random), "b")
	votes[2] = "a"
	votes[4] = "a"
	T.eq(Voting.winner({ "a", "b", "c" }, votes, math.random), "a")
end)

T.test("ties are broken at random among the tied tracks only", function()
	local votes = { [1] = "a", [2] = "c" }
	local seen = {}
	for _, r in { 0, 0.49, 0.51, 0.99 } do
		seen[Voting.winner({ "a", "b", "c" }, votes, seq({ r }))] = true
	end
	T.ok(seen.a and seen.c and not seen.b)
end)

T.test("no votes picks any option; votes for other tracks are ignored", function()
	local w = Voting.winner({ "a", "b", "c" }, { [1] = "zzz" }, seq({ 0.7 }))
	T.ok(w == "a" or w == "b" or w == "c")
	T.eq(Voting.tally({ "a" }, { [1] = "zzz" }).a, 0)
end)

T.test("voters per option", function()
	local voters = Voting.votersFor({ [10] = "a", [11] = "b", [12] = "a" }, "a")
	table.sort(voters)
	T.eq(#voters, 2)
	T.eq(voters[1], 10)
end)
