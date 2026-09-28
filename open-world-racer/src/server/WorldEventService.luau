-- Runs the living city: day/night, rain, flash races that pop up around the
-- map, and the nightly midnight meet. Everything comes from WorldClock, so all
-- servers agree on tonight's meet location.

local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local WorldClock = require(Shared.WorldClock)
local WorldMap = require(Shared.WorldMap)

local Net = require(script.Parent.Net)
local RaceService = require(script.Parent.RaceService)

local WorldEventService = {}

local MEET_GATHER_SECONDS = 120 -- time to show off builds before the featured race (meet window is ~150s)
local MEET_RADIUS = 80

-- Studio-only shortcut: shifts the world clock so testers can jump to dusk or
-- the midnight meet instead of waiting. Always 0 in live servers.
local timeOffset = 0

local lastFlashKey: string? = nil
local lastMeetKey: string? = nil
local lastState = ""

local function spotById(list: { any }, id: string): any
	for _, s in list do
		if s.id == id then
			return s
		end
	end
	return nil
end

-- `t` is world time (real time + offset); anything a player counts down to
-- must be converted back to real server time.
local function toReal(worldT: number): number
	return worldT - timeOffset
end

local function worldState(t: number)
	local flash = WorldClock.flashRace(t)
	local meet = WorldClock.midnightMeet(t)
	local state = {
		clock = WorldClock.clockTime(t),
		raining = WorldClock.isRaining(t),
		flash = nil :: any,
		meet = {
			phase = meet.phase,
			clue = if meet.phase ~= "hidden" then meet.clue else nil,
			-- The exact spot is only revealed once it opens; until then, follow the clue.
			spotName = if meet.phase == "open" then meet.spotName else nil,
			pos = nil :: any,
			featured = WorldMap.Events[meet.featuredEventId].name,
		},
	}
	if flash then
		local spot = spotById(WorldMap.FlashSpots, flash.spotId)
		state.flash = {
			name = spot.name,
			event = WorldMap.Events[flash.eventId].name,
			closesAt = toReal(flash.closesAt),
			pos = { x = spot.pos.x, z = spot.pos.z },
		}
	end
	if meet.phase == "open" then
		local spot = spotById(WorldMap.MidnightSpots, meet.spotId)
		state.meet.pos = { x = spot.pos.x, z = spot.pos.z }
	end
	return state, flash, meet
end

local function step()
	local realNow = Workspace:GetServerTimeNow()
	local t = realNow + timeOffset
	local state, flash, meet = worldState(t)

	Lighting.ClockTime = state.clock
	Workspace:SetAttribute("Raining", state.raining)

	if flash then
		local key = `flash:{flash.opensAt}`
		if key ~= lastFlashKey then
			lastFlashKey = key
			local spot = spotById(WorldMap.FlashSpots, flash.spotId)
			RaceService.openSpecial({
				key = key,
				eventId = flash.eventId,
				kind = "flash",
				zone = spot.pos,
				startsAt = toReal(flash.closesAt),
				name = `Flash: {spot.name}`,
			})
			for _, player in Players:GetPlayers() do
				Net.Notify:FireClient(player, `Flash race at {spot.name}! Get there before it starts.`, "flash")
			end
		end
	end

	if meet.phase == "open" then
		local key = `meet:{meet.dayIndex}`
		if key ~= lastMeetKey then
			lastMeetKey = key
			local spot = spotById(WorldMap.MidnightSpots, meet.spotId)
			RaceService.openSpecial({
				key = key,
				eventId = meet.featuredEventId,
				kind = "midnight",
				zone = spot.pos,
				zoneRadius = MEET_RADIUS,
				startsAt = realNow + MEET_GATHER_SECONDS,
				leadIn = true,
				name = `Midnight Meet: {WorldMap.Events[meet.featuredEventId].name}`,
			})
			for _, player in Players:GetPlayers() do
				Net.Notify:FireClient(player, `The midnight meet is live at {spot.name}.`, "meet")
			end
		end
	end

	-- Published as an attribute so late joiners read it too. The clock is left
	-- out so it only changes when something players care about changes.
	state.clock = nil
	local encoded = HttpService:JSONEncode(state)
	if encoded ~= lastState then
		lastState = encoded
		ReplicatedStorage:SetAttribute("WorldState", encoded)
	end
end

-- Studio testing: jump the world clock forward to the next time it reads `hour`.
function WorldEventService.skipToHour(hour: number)
	local t = Workspace:GetServerTimeNow() + timeOffset
	local ahead = (hour - WorldClock.clockTime(t)) % 24
	timeOffset += ahead / 24 * WorldClock.DayLength + 1
end

-- Studio testing: open a flash race right now at a random spot.
function WorldEventService.flashNow()
	local spot = WorldMap.FlashSpots[math.random(1, #WorldMap.FlashSpots)]
	local realNow = Workspace:GetServerTimeNow()
	RaceService.openSpecial({
		key = `flash:dev:{realNow}`,
		eventId = spot.eventId,
		kind = "flash",
		zone = spot.pos,
		startsAt = realNow + 60,
		name = `Flash: {spot.name}`,
	})
	for _, player in Players:GetPlayers() do
		Net.Notify:FireClient(player, `[Dev] Flash race at {spot.name}, starts in 60s.`, "flash")
	end
end

function WorldEventService.start()
	task.spawn(function()
		while true do
			local ok, err = pcall(step)
			if not ok then
				warn("[WorldEventService]", err)
			end
			task.wait(1)
		end
	end)
end

return WorldEventService
