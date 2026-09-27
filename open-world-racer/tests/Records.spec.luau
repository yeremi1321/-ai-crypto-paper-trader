local T = require("./TestLib")
local Records = require("../src/shared/Records")

local function e(id, time)
	return { userId = id, name = `p{id}`, time = time, carId = "kestrel" }
end

T.test("board stays sorted and capped", function()
	local board = {}
	T.eq(Records.submit(board, e(1, 50), 3), 1)
	T.eq(Records.submit(board, e(2, 40), 3), 1)
	T.eq(Records.submit(board, e(3, 60), 3), 3)
	T.eq(Records.submit(board, e(4, 70), 3), nil)
	T.eq(Records.submit(board, e(5, 45), 3), 2)
	T.eq(#board, 3)
	T.eq(board[1].userId, 2)
	T.eq(board[2].userId, 5)
	T.eq(board[3].userId, 1)
end)

T.test("only personal bests replace a player's entry", function()
	local board = {}
	Records.submit(board, e(1, 50))
	T.eq(Records.submit(board, e(1, 55)), nil)
	T.eq(Records.submit(board, e(1, 45)), 1)
	T.eq(#board, 1)
	T.eq(board[1].time, 45)
end)

T.test("descending boards keep the highest score", function()
	local board = {}
	Records.submit(board, e(1, 120), 10, true)
	T.eq(Records.submit(board, e(2, 180), 10, true), 1)
	T.eq(Records.submit(board, e(2, 150), 10, true), nil)
	T.eq(board[1].time, 180)
end)

T.test("time formatting", function()
	T.eq(Records.formatTime(83.5), "1:23.500")
	T.eq(Records.formatTime(9.25), "0:09.250")
end)
