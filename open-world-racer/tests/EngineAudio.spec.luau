local T = require("./TestLib")
local EngineAudio = require("../src/shared/EngineAudio")

T.test("gears climb with speed", function()
	local last = 0
	for i = 0, 20 do
		local g = EngineAudio.gearFor(i / 20, 6)
		T.ok(g >= last)
		last = g
	end
	T.eq(EngineAudio.gearFor(0, 6), 1)
	T.eq(EngineAudio.gearFor(1, 6), 6)
end)

T.test("rpm drops right after an upshift", function()
	local p = EngineAudio.Profiles.v8
	local before = EngineAudio.state(p, 1 / 21 * 100 - 0.01, 100, 1)
	local after = EngineAudio.state(p, 1 / 21 * 100 + 0.01, 100, 1)
	T.eq(before.gear, 1)
	T.eq(after.gear, 2)
	T.ok(after.rpm < before.rpm, `{after.rpm} < {before.rpm}`)
end)

T.test("rpm stays within idle and redline", function()
	for _, p in EngineAudio.Profiles do
		for s = 0, 300, 7 do
			local st = EngineAudio.state(p, s, 200, 1)
			T.ok(st.rpm >= p.idleRpm and st.rpm <= p.redline)
			T.ok(st.volume >= 0 and st.volume <= 1)
		end
	end
end)
