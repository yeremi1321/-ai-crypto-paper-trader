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
			closesAt = flash.closesAt,
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
	local t = Workspace:GetServerTimeNow()
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
				startsAt = flash.closesAt,
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
				startsAt = t + MEET_GATHER_SECONDS,
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
