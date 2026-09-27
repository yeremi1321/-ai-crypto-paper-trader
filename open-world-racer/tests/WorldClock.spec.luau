local T = require("./TestLib")
local WorldClock = require("../src/shared/WorldClock")
local WorldMap = require("../src/shared/WorldMap")

T.test("hash is deterministic and spread out", function()
	T.eq(WorldClock.hash(42), WorldClock.hash(42))
	local buckets = { 0, 0, 0, 0 }
	for i = 1, 4000 do
		local b = WorldClock.hash(i) % 4 + 1
		buckets[b] += 1
	end
	for _, n in buckets do
		T.ok(n > 800 and n < 1200, `bucket {n}`)
	end
end)

T.test("clock time covers a full day", function()
	T.eq(WorldClock.clockTime(0), 0)
	T.eq(WorldClock.clockTime(WorldClock.DayLength / 2), 12)
	T.ok(WorldClock.isNight(0))
	T.ok(not WorldClock.isNight(WorldClock.DayLength / 2))
end)

T.test("flash races appear often and point at real events", function()
	local seen, open = 0, 0
	local base = 1_800_000_000
	for w = 0, 199 do
		local t = base + w * WorldClock.FlashWindow + 10
		local f = WorldClock.flashRace(t)
		if f then
			seen += 1
			T.ok(WorldMap.Events[f.eventId])
			T.ok(t >= f.opensAt and t < f.closesAt)
		end
		-- After the join window closes there is never a flash race.
		T.eq(WorldClock.flashRace(base + w * WorldClock.FlashWindow + WorldClock.FlashDuration + 1), nil)
		open += 1
	end
	T.ok(seen > open * 0.5 and seen < open * 0.9, `flash rate {seen}/{open}`)
end)

T.test("midnight meet phases and location stay fixed through the night", function()
	local day = 1_000_000
	local dayStart = day * WorldClock.DayLength
	local function at(hour)
		return dayStart + hour / 24 * WorldClock.DayLength
	end
	T.eq(WorldClock.midnightMeet(at(12)).phase, "hidden")
	local clue = WorldClock.midnightMeet(at(20))
	T.eq(clue.phase, "clue")
	T.ok(#clue.clue > 0)
	local late = WorldClock.midnightMeet(at(23.9))
	T.eq(late.phase, "open")
	-- After midnight it is the same meet (from yesterday's day index).
	local afterMidnight = WorldClock.midnightMeet(dayStart + WorldClock.DayLength + 0.5 / 24 * WorldClock.DayLength)
	T.eq(afterMidnight.phase, "open")
	T.eq(afterMidnight.spotId, late.spotId)
	T.eq(afterMidnight.dayIndex, day)
	T.eq(clue.spotId, late.spotId)
	T.ok(WorldMap.Events[late.featuredEventId])
end)

T.test("meet location rotates between nights", function()
	local spots = {}
	for d = 1, 40 do
		spots[WorldClock.meetForDay(d)] = true
	end
	local count = 0
	for _ in spots do
		count += 1
	end
	T.eq(count, #WorldMap.MidnightSpots)
end)

T.test("some days rain, most do not", function()
	local rainy = 0
	for d = 0, 299 do
		local day = d * WorldClock.DayLength
		for h = 0, 23 do
			if WorldClock.isRaining(day + h / 24 * WorldClock.DayLength) then
				rainy += 1
				break
			end
		end
	end
	T.ok(rainy > 40 and rainy < 140, `rainy days {rainy}/300`)
end)
