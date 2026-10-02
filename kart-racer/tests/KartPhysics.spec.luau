local T = require("./TestLib")
local KartPhysics = require("../src/shared/KartPhysics")
local Karts = require("../src/shared/Karts")

local stats = Karts.get("classic").stats
local function input(overrides)
	local i = { throttle = 1, steer = 0, drift = false, grounded = true, surface = "road" }
	for k, val in overrides or {} do
		i[k] = val
	end
	return i
end
local function run(s, inp, seconds)
	local released = 0
	for _ = 1, math.floor(seconds * 60) do
		local _, r = KartPhysics.step(stats, s, inp, 1 / 60)
		if r > 0 then
			released = r
		end
	end
	return released
end

T.test("accelerates to top speed and no further", function()
	local s = KartPhysics.newState(0)
	run(s, input(), 6)
	T.ok(math.abs(s.speed - stats.topSpeed) < 0.01, `speed {s.speed}`)
end)

T.test("offroad caps speed", function()
	local s = KartPhysics.newState(0)
	run(s, input(), 6)
	run(s, input({ surface = "offroad" }), 3)
	T.ok(math.abs(s.speed - stats.topSpeed * KartPhysics.OffroadFactor) < 0.5, `speed {s.speed}`)
end)

T.test("boost pads push past top speed", function()
	local s = KartPhysics.newState(0)
	run(s, input(), 6)
	KartPhysics.step(stats, s, input({ surface = "boost" }), 1 / 60)
	run(s, input(), 0.5)
	T.ok(s.speed > stats.topSpeed * 1.2, `speed {s.speed}`)
end)

T.test("steering right turns clockwise (yaw down)", function()
	local s = KartPhysics.newState(0)
	run(s, input(), 2)
	run(s, input({ steer = 1 }), 0.2)
	T.ok(s.yaw < 0)
end)

T.test("short drift gives nothing, long drifts give bigger mini-turbos", function()
	local function driftFor(seconds)
		local s = KartPhysics.newState(0)
		run(s, input(), 3)
		run(s, input({ steer = 1, drift = true }), seconds)
		T.ok(s.drift == 1, "should be drifting")
		local level = run(s, input({ steer = 0, drift = false }), 1 / 60)
		return level, s
	end
	T.eq((driftFor(0.3)), 0)
	T.eq((driftFor(0.8)), 1)
	T.eq((driftFor(1.2)), 2)
	local level, s = driftFor(2.0)
	T.eq(level, 3)
	T.ok(s.boost > 1.5)
end)

T.test("no drifting from a standstill", function()
	local s = KartPhysics.newState(0)
	run(s, input({ throttle = 0, steer = 1, drift = true }), 1)
	T.eq(s.drift, 0)
end)

T.test("hits spin you out but keep your heading; overdrive blocks hits", function()
	local s = KartPhysics.newState(1.25)
	run(s, input(), 4)
	T.ok(KartPhysics.hit(s))
	T.ok(s.speed < stats.topSpeed * 0.5)
	run(s, input({ steer = 1 }), KartPhysics.SpinTime)
	T.eq(s.yaw, 1.25)
	KartPhysics.overdrive(s, 5)
	T.ok(not KartPhysics.hit(s))
end)

T.test("braking then reversing", function()
	local s = KartPhysics.newState(0)
	run(s, input(), 3)
	run(s, input({ throttle = -1 }), 4)
	T.ok(s.speed < 0 and s.speed >= -stats.topSpeed * KartPhysics.ReverseFactor - 0.01)
end)

T.test("all karts have equal stat budgets", function()
	local function budget(k)
		local st = k.stats
		return (st.topSpeed - 90) / 15 + (st.accel - 40) / 30 + (st.handling - 1.8) / 0.7
	end
	local first = budget(Karts.List[1])
	for _, k in Karts.List do
		T.ok(math.abs(budget(k) - first) < 0.25, `{k.id} budget {budget(k)} vs {first}`)
	end
end)
