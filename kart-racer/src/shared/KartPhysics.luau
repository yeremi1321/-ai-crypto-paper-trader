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
}

export type Input = {
	throttle: number, -- -1..1
	steer: number, -- -1 (left) .. 1 (right)
	drift: boolean,
	grounded: boolean,
	surface: string, -- "road" | "offroad" | "boost"
}

local KartPhysics = {}

KartPhysics.OffroadFactor = 0.55
KartPhysics.BoostFactor = 1.35
KartPhysics.ReverseFactor = 0.35
KartPhysics.BoostPadTime = 1.0
KartPhysics.ChargeLevels = { 0.9, 1.8, 2.9 } -- charge needed for each mini-turbo
KartPhysics.TurboTimes = { 0.6, 1.1, 1.7 } -- boost seconds each level gives
KartPhysics.SpinTime = 1.2
KartPhysics.SpinSpeedKeep = 0.3
KartPhysics.DriftSlide = 0.35 -- radians the body swings out while drifting (visual)

function KartPhysics.newState(yaw: number): State
	return { speed = 0, yaw = yaw, drift = 0, charge = 0, boost = 0, spin = 0, invincible = 0 }
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

-- Advances the kart by dt. Mutates and returns the state, plus the mini-turbo
-- level released this step (0 if none) for sound/effects.
function KartPhysics.step(stats: Karts.KartStats, s: State, input: Input, dt: number): (State, number)
	local released = 0
	s.boost = math.max(0, s.boost - dt)
	s.invincible = math.max(0, s.invincible - dt)

	if input.surface == "boost" then
		KartPhysics.giveBoost(s, KartPhysics.BoostPadTime)
	end

	if s.spin > 0 then
		s.spin = math.max(0, s.spin - dt)
		s.speed = approach(s.speed, 0, stats.accel * 1.5 * dt)
		return s, 0
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
		released = KartPhysics.chargeLevel(s.charge)
		if released > 0 then
			KartPhysics.giveBoost(s, KartPhysics.TurboTimes[released])
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
