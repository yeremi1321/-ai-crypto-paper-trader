--!strict
-- Coins, end-of-race awards, challenges and track mastery badges. Everything
-- here is computed by the server from what it saw happen in the race (place,
-- hits, shortcuts, jumps, lap times), never from what a client claims.

local Rewards = {}

Rewards.PlaceCoins = { 120, 100, 85, 70, 60, 50, 45, 40 }
Rewards.DnfCoins = 20
Rewards.AwardCoins = 40
Rewards.TokenCoins = 25

export type RaceStats = {
	id: string, -- racer id
	name: string,
	place: number,
	finished: boolean,
	time: number?,
	bestLap: number?,
	worstPlace: number,
	hitsTaken: number,
	shortcutsTaken: number,
	jumps: number,
	isCpu: boolean,
}

export type Award = { id: string, name: string, icon: string, winner: string }

function Rewards.placeCoins(place: number, finished: boolean): number
	if not finished then
		return Rewards.DnfCoins
	end
	return Rewards.PlaceCoins[place] or Rewards.PlaceCoins[#Rewards.PlaceCoins]
end

Rewards.AwardInfo = {
	comeback = { name = "Best Comeback", icon = "🔥" },
	clean = { name = "Cleanest Driver", icon = "🧼" },
	shortcut = { name = "Shortcut Expert", icon = "🗺️" },
	flyer = { name = "High Flyer", icon = "🦅" },
}

-- Picks award winners for a finished race. Ties go to the better placing.
function Rewards.awards(rows: { RaceStats }): { Award }
	local out: { Award } = {}
	local function best(score: (RaceStats) -> number?, minimum: number): RaceStats?
		local winner: RaceStats? = nil
		local winnerScore = -math.huge
		for _, r in rows do
			local s = score(r)
			if s and s >= minimum and (s > winnerScore or (s == winnerScore and winner and r.place < winner.place)) then
				winner, winnerScore = r, s
			end
		end
		return winner
	end
	local function add(id: string, r: RaceStats?)
		if r then
			local info = Rewards.AwardInfo[id]
			table.insert(out, { id = id, name = info.name, icon = info.icon, winner = r.id })
		end
	end
	add("comeback", best(function(r)
		return if r.finished then r.worstPlace - r.place else nil
	end, 3))
	add("clean", best(function(r)
		-- Only clean finishers; better place scores higher.
		return if r.finished and r.hitsTaken == 0 then 100 - r.place else nil
	end, 0))
	add("shortcut", best(function(r)
		return r.shortcutsTaken
	end, 1))
	add("flyer", best(function(r)
		return r.jumps
	end, 4))
	return out
end

-- One-time challenges. `check` reads the lifetime stats in the save data.
Rewards.Challenges = {
	{ id = "firstWin", name = "Win a race", reward = 150, check = function(s) return s.wins >= 1 end },
	{ id = "podium3", name = "Finish on the podium 3 times", reward = 150, check = function(s) return s.podiums >= 3 end },
	{ id = "shortcut3", name = "Take 3 shortcuts", reward = 100, check = function(s) return s.shortcuts >= 3 end },
	{ id = "cleanRace", name = "Finish a race without being hit", reward = 120, check = function(s) return s.cleanRaces >= 1 end },
	{ id = "jumps10", name = "Land 10 big jumps", reward = 100, check = function(s) return s.jumps >= 10 end },
	{ id = "personalBest", name = "Beat one of your best lap times", reward = 80, check = function(s) return s.improvedLaps >= 1 end },
	{ id = "explorer", name = "Race on every track", reward = 200, check = function(s) return s.tracksRaced >= s.trackCount end },
	{ id = "tokens", name = "Find all golden tokens in the lobby", reward = 300, check = function(s) return s.tokens >= s.tokenCount end },
}

-- Mastery badge for a track: 1 bronze (finished a race), 2 silver (podium),
-- 3 gold (won, with a best lap under the gold time).
function Rewards.goldLap(trackLength: number): number
	return trackLength / 92
end

function Rewards.badge(mastery: { finishes: number, podiums: number, wins: number, bestLap: number? }, trackLength: number): number
	if mastery.wins >= 1 and mastery.bestLap and mastery.bestLap <= Rewards.goldLap(trackLength) then
		return 3
	elseif mastery.podiums >= 1 then
		return 2
	elseif mastery.finishes >= 1 then
		return 1
	end
	return 0
end

Rewards.BadgeNames = { "Bronze", "Silver", "Gold" }
Rewards.BadgeIcons = { "🥉", "🥈", "🥇" }

return Rewards
