--!strict
-- Arcade kart handling as a pure step function. The same code drives player
-- karts (on their client) and CPU karts (on the server), and runs in tests.
--
-- Drifting: hold drift while turning at speed. The longer you hold it (and the
-- harder you steer into it), the bigger the mini-turbo when you let go:
-- level 1 (blue sparks), 2 (orange), 3 (purple).

local Karts = require("./Karts")

export type State = {
	speed: number, -- forward speed, studs/s (negative = reversing)
	yaw: number, -- heading in radians; forward = (-sin yaw, 0, -cos yaw)
	drift: number, -- 0 = not drifting, -1 = drifting left, 1 = right
	charge: number, -- mini-turbo charge while drifting
	boost: number, -- seconds of boost left
	spin: number, -- seconds left spinning out after a hit
	invincible: number, -- seconds of Overdrive left
	slow: number, -- seconds left stuck in something sticky (jelly, syrup)
	draft: number, -- slipstream charge built up behind another kart
	air: number, -- seconds airborne in the current jump
	trick: number, -- 0 = none, else seconds since a trick started in this jump
}

export type Input = {
	throttle: number, -- -1..1
	steer: number, -- -1 (left) .. 1 (right)
	drift: boolean,
	grounded: boolean,
	surface: string, -- "road" | "offroad" | "boost"
	trick: boolean?, -- drift button pressed this frame (does a trick when airborne)
	drafting: boolean?, -- tucked in behind another kart this frame
}

local KartPhysics = {}

KartPhysics.OffroadFactor = 0.55
KartPhysics.BoostFactor = 1.35
KartPhysics.ReverseFactor = 0.35
KartPhysics.BoostPadTime = 1.0
KartPhysics.ChargeLevels = { 0.9, 1.8, 2.9 } -- charge needed for each mini-turbo
KartPhysics.TurboTimes = { 0.6, 1.1, 1.7 } -- boost seconds each level gives
KartPhysics.SlowFactor = 0.5
KartPhysics.ConveyorFactor = 1.15
KartPhysics.SlipperyGrip = 0.55 -- normal steering on wet ground
KartPhysics.LaunchBoost = 1.2
-- Slipstream: stay behind someone this long to get a boost.
KartPhysics.DraftTime = 1.1
KartPhysics.DraftBoost = 0.9
KartPhysics.DraftRange = { 6, 38 } -- studs behind the kart ahead
KartPhysics.DraftWidth = 5 -- how far off their line you can be
-- Tricks: press drift soon after leaving a ramp, land for a boost.
KartPhysics.TrickWindow = 0.6
KartPhysics.TrickMinAir = 0.25
KartPhysics.TrickBoost = 0.8
KartPhysics.TrickSpinTime = 0.45
KartPhysics.SpinTime = 1.2
KartPhysics.SpinSpeedKeep = 0.3
KartPhysics.DriftSlide = 0.35 -- radians the body swings out while drifting (visual)

function KartPhysics.newState(yaw: number): State
	return { speed = 0, yaw = yaw, drift = 0, charge = 0, boost = 0, spin = 0, invincible = 0, slow = 0, draft = 0, air = 0, trick = 0 }
end

function KartPhysics.chargeLevel(charge: number): number
	local level = 0
	for i, need in KartPhysics.ChargeLevels do
		if charge >= need then
			level = i
		end
	end
	return level
end

function KartPhysics.forward(yaw: number): (number, number)
	return -math.sin(yaw), -math.cos(yaw)
end

-- Top speed for the current surface and boost state.
function KartPhysics.targetTop(stats: Karts.KartStats, s: State, surface: string): number
	local top = stats.topSpeed
	if s.boost > 0 then
		top *= KartPhysics.BoostFactor
	elseif surface == "offroad" then
		top *= KartPhysics.OffroadFactor
	end
	if surface == "sticky" then
		top *= KartPhysics.OffroadFactor
	elseif surface == "conveyor" then
		top *= KartPhysics.ConveyorFactor
	end
	if s.slow > 0 then
		top *= KartPhysics.SlowFactor
	end
	return top
end

-- Where the kart body points: the travel heading plus the drift swing and
-- two full turns while spinning out. Travel direction never changes on a spin.
function KartPhysics.visualYaw(s: State): number
	local spinAngle = 0
	if s.spin > 0 then
		spinAngle = (1 - s.spin / KartPhysics.SpinTime) * math.pi * 4
	end
	-- Drifting right (drift = 1) swings the nose further right, i.e. lower yaw.
	return s.yaw - s.drift * KartPhysics.DriftSlide + spinAngle
end

-- A hit from an item. Overdrive makes you immune.
function KartPhysics.hit(s: State): boolean
	if s.invincible > 0 or s.spin > 0 then
		return false
	end
	s.spin = KartPhysics.SpinTime
	s.speed *= KartPhysics.SpinSpeedKeep
	s.drift = 0
	s.charge = 0
	s.boost = 0
	return true
end

-- Sticky traps: half speed for a while, no spin.
function KartPhysics.slow(s: State, seconds: number)
	if s.invincible > 0 then
		return
	end
	s.slow = math.max(s.slow, seconds)
	s.boost = 0
end

function KartPhysics.giveBoost(s: State, seconds: number)
	s.boost = math.max(s.boost, seconds)
end

function KartPhysics.overdrive(s: State, seconds: number)
	s.invincible = math.max(s.invincible, seconds)
	s.boost = math.max(s.boost, seconds)
	s.spin = 0
end

local function approach(value: number, target: number, rate: number): number
	if value < target then
		return math.min(value + rate, target)
	end
	return math.max(value - rate, target)
end

-- Is a kart at (px, pz) heading `yaw` tucked in behind any of `others`?
function KartPhysics.isDrafting(px: number, pz: number, yaw: number, others: { { x: number, z: number } }): boolean
	local fx, fz = KartPhysics.forward(yaw)
	for _, o in others do
		local dx, dz = o.x - px, o.z - pz
		local ahead = dx * fx + dz * fz
		local side = math.abs(dx * -fz + dz * fx)
		if ahead >= KartPhysics.DraftRange[1] and ahead <= KartPhysics.DraftRange[2] and side <= KartPhysics.DraftWidth then
			return true
		end
	end
	return false
end

-- Extra roll (radians) for the trick animation: one full barrel roll.
function KartPhysics.trickRoll(s: State): number
	if s.trick <= 0 then
		return 0
	end
	return math.clamp(s.trick / KartPhysics.TrickSpinTime, 0, 1) * math.pi * 2
end

-- Events returned by step: mini-turbo levels 1..3 as numbers, plus these.
KartPhysics.Events = { Trick = 10, Draft = 11 }

-- Advances the kart by dt. Mutates and returns the state, plus what happened
-- this step for sound/effects: a mini-turbo level (1..3), Events.Trick when a
-- trick lands, Events.Draft when a slipstream boost kicks in, or 0.
function KartPhysics.step(stats: Karts.KartStats, s: State, input: Input, dt: number): (State, number)
	local released = 0
	s.boost = math.max(0, s.boost - dt)
	s.invincible = math.max(0, s.invincible - dt)
	s.slow = math.max(0, s.slow - dt)

	-- Jumps and tricks.
	if not input.grounded then
		s.air += dt
		if s.trick > 0 then
			s.trick += dt
		elseif input.trick and s.air <= KartPhysics.TrickWindow and s.spin <= 0 then
			s.trick = dt
		end
	else
		if s.trick > 0 and s.air >= KartPhysics.TrickMinAir and s.spin <= 0 then
			KartPhysics.giveBoost(s, KartPhysics.TrickBoost)
			released = KartPhysics.Events.Trick
		end
		s.air = 0
		s.trick = 0
	end

	-- Slipstream.
	if input.drafting and input.grounded and s.speed > stats.topSpeed * 0.6 then
		s.draft += dt
		if s.draft >= KartPhysics.DraftTime then
			s.draft = 0
			KartPhysics.giveBoost(s, KartPhysics.DraftBoost)
			released = KartPhysics.Events.Draft
		end
	else
		s.draft = math.max(0, s.draft - dt * 2)
	end

	if input.surface == "boost" then
		KartPhysics.giveBoost(s, KartPhysics.BoostPadTime)
	elseif input.surface == "launch" then
		KartPhysics.giveBoost(s, KartPhysics.LaunchBoost)
	end

	if s.spin > 0 then
		s.spin = math.max(0, s.spin - dt)
		s.speed = approach(s.speed, 0, stats.accel * 1.5 * dt)
		return s, released
	end

	local top = KartPhysics.targetTop(stats, s, input.surface)
	local throttle = math.clamp(input.throttle, -1, 1)
	local steer = math.clamp(input.steer, -1, 1)

	-- Speed ----------------------------------------------------------------
	if s.boost > 0 then
		s.speed = approach(s.speed, top, stats.accel * 3 * dt)
	elseif not input.grounded then
		-- Airborne: hold speed.
	elseif s.speed > top then
		s.speed = approach(s.speed, top, stats.accel * 1.5 * dt)
	elseif throttle > 0 then
		s.speed = approach(s.speed, top * throttle, stats.accel * dt)
	elseif throttle < 0 then
		if s.speed > 0 then
			s.speed = approach(s.speed, 0, stats.accel * 2.5 * dt)
		else
			s.speed = approach(s.speed, -top * KartPhysics.ReverseFactor, stats.accel * 0.8 * dt)
		end
	else
		s.speed = approach(s.speed, 0, stats.accel * 0.6 * dt)
	end

	-- Drift start / release ------------------------------------------------
	if s.drift == 0 then
		if input.drift and input.grounded and math.abs(steer) > 0.3 and s.speed > stats.topSpeed * 0.4 then
			s.drift = if steer > 0 then 1 else -1
			s.charge = 0
		end
	elseif not input.drift or s.speed < stats.topSpeed * 0.3 then
		local level = KartPhysics.chargeLevel(s.charge)
		if level > 0 then
			released = level
			KartPhysics.giveBoost(s, KartPhysics.TurboTimes[level])
		end
		s.drift = 0
		s.charge = 0
	end

	-- Turning ----------------------------------------------------------------
	local turn: number
	if s.drift ~= 0 then
		-- Always turning into the drift; steering into it tightens, against widens.
		turn = s.drift * stats.handling * (0.7 + 0.45 * steer * s.drift)
		if input.grounded then
			s.charge += dt * (1 + math.max(0, steer * s.drift))
		end
	else
		local grip = math.clamp(math.abs(s.speed) / (stats.topSpeed * 0.25), 0, 1)
		if input.surface == "slippery" then
			grip *= KartPhysics.SlipperyGrip
		end
		turn = steer * stats.handling * grip * (if s.speed < 0 then -1 else 1)
	end
	if not input.grounded then
		turn *= 0.4
	end
	-- Positive steer turns right, which is clockwise seen from above: yaw goes down.
	s.yaw -= turn * dt

	return s, released
end

return KartPhysics
