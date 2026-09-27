--!strict
-- Deterministic world schedule derived from Unix time: time of day, weather,
-- flash races and the nightly midnight meet. Every server computes the same
-- answer for the same moment, so friends in different servers can compare
-- clues and all servers agree on where tonight's meet is.

local WorldMap = require("./WorldMap")

local WorldClock = {}

WorldClock.DayLength = 20 * 60 -- real seconds per in-game day
WorldClock.FlashWindow = 150 -- a flash race may appear once per window
WorldClock.FlashDuration = 90 -- how long it stays open to join
WorldClock.FlashChance = 0.7
WorldClock.MeetOpensAt = 23.5 -- game hour
WorldClock.MeetClosesAt = 2.5 -- game hour (next day)
WorldClock.ClueFrom = 18 -- game hour when the day's clue is posted

local MOD = 2147483647

-- Small integer hash (MINSTD steps plus xor mixing), exact in doubles.
function WorldClock.hash(n: number): number
	local x = (math.floor(math.abs(n)) % (MOD - 1)) + 1
	x = (x * 48271) % MOD
	x = bit32.bxor(x, bit32.rshift(x, 11))
	x = (x * 48271) % MOD
	x = bit32.bxor(x, bit32.rshift(x, 7))
	return (x * 48271) % MOD
end

-- 0..1 pseudo-random value for a seed.
function WorldClock.unit(n: number): number
	return (WorldClock.hash(n) % 100000) / 100000
end

function WorldClock.dayIndex(t: number): number
	return math.floor(t / WorldClock.DayLength)
end

function WorldClock.clockTime(t: number): number
	return (t % WorldClock.DayLength) / WorldClock.DayLength * 24
end

function WorldClock.isNight(t: number): boolean
	local h = WorldClock.clockTime(t)
	return h >= 19 or h < 6
end

function WorldClock.isRaining(t: number): boolean
	local day = WorldClock.dayIndex(t)
	if WorldClock.unit(day * 31 + 5) > 0.3 then
		return false
	end
	-- Rainy days get one shower from the day's start hour for 5 game hours.
	local startHour = math.floor(WorldClock.unit(day * 31 + 6) * 19)
	local h = WorldClock.clockTime(t)
	return h >= startHour and h < startHour + 5
end

export type Flash = {
	spotId: string,
	spotName: string,
	eventId: string,
	opensAt: number,
	closesAt: number,
}

-- The flash race active at time t, if any.
function WorldClock.flashRace(t: number): Flash?
	local window = math.floor(t / WorldClock.FlashWindow)
	local opensAt = window * WorldClock.FlashWindow
	if t >= opensAt + WorldClock.FlashDuration then
		return nil
	end
	if WorldClock.unit(window * 13 + 1) > WorldClock.FlashChance then
		return nil
	end
	local spots = WorldMap.FlashSpots
	local spot = spots[WorldClock.hash(window * 13 + 2) % #spots + 1]
	return {
		spotId = spot.id,
		spotName = spot.name,
		eventId = spot.eventId,
		opensAt = opensAt,
		closesAt = opensAt + WorldClock.FlashDuration,
	}
end

export type Meet = {
	spotId: string,
	spotName: string,
	clue: string,
	featuredEventId: string,
	dayIndex: number,
	phase: "hidden" | "clue" | "open",
}

local function sortedEventIds(): { string }
	local ids = {}
	for id in WorldMap.Events do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function WorldClock.meetForDay(dayIndex: number): (string, string)
	local spots = WorldMap.MidnightSpots
	local spot = spots[WorldClock.hash(dayIndex * 7 + 3) % #spots + 1]
	local ids = sortedEventIds()
	local eventId = ids[WorldClock.hash(dayIndex * 7 + 4) % #ids + 1]
	return spot.id, eventId
end

-- Tonight's meet as seen at time t. The meet that opens late on day N keeps
-- running into the early hours of day N+1.
function WorldClock.midnightMeet(t: number): Meet
	local h = WorldClock.clockTime(t)
	local day = WorldClock.dayIndex(t)
	local phase: "hidden" | "clue" | "open" = "hidden"

	if h < WorldClock.MeetClosesAt then
		day -= 1
		phase = "open"
	elseif h >= WorldClock.MeetOpensAt then
		phase = "open"
	elseif h >= WorldClock.ClueFrom then
		phase = "clue"
	end

	local spotId, eventId = WorldClock.meetForDay(day)
	local spotName, clue = spotId, ""
	for _, s in WorldMap.MidnightSpots do
		if s.id == spotId then
			spotName, clue = s.name, s.clue
		end
	end

	return {
		spotId = spotId,
		spotName = spotName,
		clue = clue,
		featuredEventId = eventId,
		dayIndex = day,
		phase = phase,
	}
end

return WorldClock
