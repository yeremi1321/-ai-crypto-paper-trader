--!strict
-- Local leaderboards posted at each racing spot: best race time per player,
-- or best score (speed trap, drift zone) when `descending` is set.

export type Entry = { userId: number, name: string, time: number, carId: string }

local Records = {}

Records.MaxEntries = 10

-- Inserts or improves a player's entry. Returns the new 1-based rank, or nil if
-- it did not make the board (or was not a personal best).
function Records.submit(board: { Entry }, entry: Entry, maxEntries: number?, descending: boolean?): number?
	local limit = maxEntries or Records.MaxEntries
	local function better(a: number, b: number): boolean
		if descending then
			return a > b
		end
		return a < b
	end

	for i, e in board do
		if e.userId == entry.userId then
			if not better(entry.time, e.time) then
				return nil
			end
			table.remove(board, i)
			break
		end
	end

	local rank = #board + 1
	for i, e in board do
		if better(entry.time, e.time) then
			rank = i
			break
		end
	end

	if rank > limit then
		return nil
	end

	table.insert(board, rank, entry)
	while #board > limit do
		table.remove(board)
	end
	return rank
end

function Records.formatTime(seconds: number): string
	local m = math.floor(seconds / 60)
	local s = seconds - m * 60
	return string.format("%d:%06.3f", m, s)
end

return Records
