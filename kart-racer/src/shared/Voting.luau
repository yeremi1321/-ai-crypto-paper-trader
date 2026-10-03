--!strict
-- Map voting: pick three track options each round, count votes, choose the
-- winner. Pure logic so it can be tested; the server owns the actual votes.

local Voting = {}

Voting.OptionCount = 3
Voting.VoteSeconds = 20

-- Picks `count` different tracks from `pool` (a list of ids), avoiding the
-- track that was just raced when there are enough others. `random` returns 0..1.
function Voting.pickOptions(pool: { string }, count: number, random: () -> number, lastTrack: string?): { string }
	local candidates = {}
	for _, id in pool do
		if id ~= lastTrack then
			table.insert(candidates, id)
		end
	end
	if #candidates < count and lastTrack and table.find(pool, lastTrack) then
		table.insert(candidates, lastTrack)
	end
	-- Fisher-Yates shuffle, then take the first `count`.
	for i = #candidates, 2, -1 do
		local j = math.floor(random() * i) + 1
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end
	local out = {}
	for i = 1, math.min(count, #candidates) do
		out[i] = candidates[i]
	end
	return out
end

-- votes: voter id -> track id. Only votes for listed options count.
function Voting.tally(options: { string }, votes: { [any]: string }): { [string]: number }
	local counts = {}
	for _, id in options do
		counts[id] = 0
	end
	for _, choice in votes do
		if counts[choice] ~= nil then
			counts[choice] += 1
		end
	end
	return counts
end

-- Highest vote count wins; ties (including nobody voting) are broken at random.
function Voting.winner(options: { string }, votes: { [any]: string }, random: () -> number): string
	assert(#options > 0, "no options to vote on")
	local counts = Voting.tally(options, votes)
	local best, tied = -1, {}
	for _, id in options do
		local n = counts[id]
		if n > best then
			best, tied = n, { id }
		elseif n == best then
			table.insert(tied, id)
		end
	end
	return tied[math.floor(random() * #tied) + 1]
end

-- Who voted for what, for the voter icons on each option.
function Voting.votersFor(votes: { [any]: string }, option: string): { any }
	local out = {}
	for voter, choice in votes do
		if choice == option then
			table.insert(out, voter)
		end
	end
	return out
end

return Voting
