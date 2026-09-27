--!strict
-- Engine-agnostic race state: checkpoint order, laps, standings and results.
-- The server feeds it checkpoint touches; it never touches Roblox instances,
-- so it can be unit tested outside Studio.

export type Racer = {
	id: number, -- UserId
	name: string,
	nextCheckpoint: number, -- 1-based index into the lap's checkpoints
	lap: number,
	progress: number, -- total checkpoints passed
	lastCheckpointTime: number,
	finishTime: number?, -- seconds since race start
	dnf: boolean,
}

export type Race = {
	eventId: string,
	checkpointCount: number,
	laps: number,
	startTime: number,
	timeLimit: number,
	racers: { [number]: Racer },
	finishOrder: { number },
}

export type Placing = { id: number, name: string, place: number, time: number?, dnf: boolean }

local RaceLogic = {}

function RaceLogic.new(eventId: string, checkpointCount: number, laps: number?, startTime: number, timeLimit: number?): Race
	assert(checkpointCount >= 1, "race needs at least one checkpoint")
	return {
		eventId = eventId,
		checkpointCount = checkpointCount,
		laps = laps or 1,
		startTime = startTime,
		timeLimit = timeLimit or 300,
		racers = {},
		finishOrder = {},
	}
end

function RaceLogic.addRacer(race: Race, id: number, name: string)
	race.racers[id] = {
		id = id,
		name = name,
		nextCheckpoint = 1,
		lap = 1,
		progress = 0,
		lastCheckpointTime = race.startTime,
		dnf = false,
	}
end

function RaceLogic.removeRacer(race: Race, id: number)
	local r = race.racers[id]
	if r and not r.finishTime then
		r.dnf = true
	end
end

-- Returns "ignored" | "checkpoint" | "lap" | "finished".
-- Only the expected next checkpoint counts, so skipping one is impossible.
function RaceLogic.hitCheckpoint(race: Race, id: number, index: number, now: number): string
	local r = race.racers[id]
	if not r or r.dnf or r.finishTime or index ~= r.nextCheckpoint then
		return "ignored"
	end

	r.progress += 1
	r.lastCheckpointTime = now

	if index < race.checkpointCount then
		r.nextCheckpoint += 1
		return "checkpoint"
	end

	if r.lap < race.laps then
		r.lap += 1
		r.nextCheckpoint = 1
		return "lap"
	end

	r.finishTime = now - race.startTime
	table.insert(race.finishOrder, id)
	return "finished"
end

-- Marks everyone still driving past the time limit as DNF.
function RaceLogic.tick(race: Race, now: number)
	if now - race.startTime < race.timeLimit then
		return
	end
	for _, r in race.racers do
		if not r.finishTime then
			r.dnf = true
		end
	end
end

function RaceLogic.isOver(race: Race): boolean
	for _, r in race.racers do
		if not r.finishTime and not r.dnf then
			return false
		end
	end
	return true
end

-- Live standings: finishers by finish order, then drivers still racing by
-- progress (ties broken by who reached the checkpoint first), then DNFs.
function RaceLogic.standings(race: Race): { Placing }
	local list: { Racer } = {}
	for _, r in race.racers do
		table.insert(list, r)
	end

	local finishIndex: { [number]: number } = {}
	for i, id in race.finishOrder do
		finishIndex[id] = i
	end

	table.sort(list, function(a: Racer, b: Racer): boolean
		local fa, fb = finishIndex[a.id], finishIndex[b.id]
		if fa and fb then
			return fa < fb
		elseif fa or fb then
			return fa ~= nil
		end
		if a.dnf ~= b.dnf then
			return not a.dnf
		end
		if a.progress ~= b.progress then
			return a.progress > b.progress
		end
		if a.lastCheckpointTime ~= b.lastCheckpointTime then
			return a.lastCheckpointTime < b.lastCheckpointTime
		end
		return a.id < b.id
	end)

	local out: { Placing } = {}
	for i, r in list do
		table.insert(out, { id = r.id, name = r.name, place = i, time = r.finishTime, dnf = r.dnf })
	end
	return out
end

function RaceLogic.totalCheckpoints(race: Race): number
	return race.checkpointCount * race.laps
end

return RaceLogic
