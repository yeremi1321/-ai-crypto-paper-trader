--!strict
-- Placings, Grand Prix points, the start boost, and how hard CPU drivers push.

local RaceRules = {}

RaceRules.MaxRacers = 8
RaceRules.Points = { 15, 12, 10, 8, 6, 4, 2, 1 }
RaceRules.CountdownSeconds = 3
-- Press the throttle in this window before GO for a rocket start.
RaceRules.StartBoostWindow = { -1.0, -0.35 }
RaceRules.StartBoostTime = 1.0

export type Entry = {
	id: string,
	finished: boolean,
	finishTime: number?,
	score: number, -- Track.score: higher is further ahead
}

-- Finishers by time, then everyone else by how far along they are.
function RaceRules.rank(entries: { Entry }): { Entry }
	local list = table.clone(entries)
	table.sort(list, function(a: Entry, b: Entry): boolean
		if a.finished ~= b.finished then
			return a.finished
		end
		if a.finished and a.finishTime ~= b.finishTime then
			return (a.finishTime :: number) < (b.finishTime :: number)
		end
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.id < b.id
	end)
	return list
end

function RaceRules.pointsFor(place: number): number
	return RaceRules.Points[place] or 0
end

-- `pressedAt` is when the throttle went down, in seconds relative to GO
-- (negative = before GO). Returns boost seconds (0 = no rocket start).
function RaceRules.startBoost(pressedAt: number?): number
	if not pressedAt then
		return 0
	end
	local lo, hi = RaceRules.StartBoostWindow[1], RaceRules.StartBoostWindow[2]
	if pressedAt >= lo and pressedAt <= hi then
		return RaceRules.StartBoostTime
	end
	return 0
end

-- Top-speed multiplier for a CPU driver. CPUs far behind the leader speed up a
-- little; a CPU running away from every human eases off. Humans never get this.
function RaceRules.cpuSpeedFactor(gapToLeader: number, leadOverBestHuman: number, skill: number): number
	local factor = 0.93 + 0.07 * math.clamp(skill, 0, 1)
	factor += math.clamp(gapToLeader / 600, 0, 1) * 0.1
	if leadOverBestHuman > 120 then
		factor -= math.clamp((leadOverBestHuman - 120) / 400, 0, 1) * 0.08
	end
	return factor
end

export type CupRow = { id: string, name: string, points: number, lastPlace: number }

-- Overall cup standings; ties go to whoever placed better in the last race.
function RaceRules.cupStandings(rows: { CupRow }): { CupRow }
	local list = table.clone(rows)
	table.sort(list, function(a: CupRow, b: CupRow): boolean
		if a.points ~= b.points then
			return a.points > b.points
		end
		return a.lastPlace < b.lastPlace
	end)
	return list
end

return RaceRules
