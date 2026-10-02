--!strict
-- CPU driving: look ahead along the centerline, steer toward a point in the
-- driver's preferred lane, drift through long corners, ease off in hairpins.

local KartPhysics = require("./KartPhysics")
local Karts = require("./Karts")
local Track = require("./Track")

export type Profile = {
	lane: number, -- -1..1 preferred side of the road
	skill: number, -- 0..1
}

local AIDriver = {}

-- Signed angle from the kart's heading to a world direction; positive = turn right.
function AIDriver.angleTo(yaw: number, dx: number, dz: number): number
	local fx, fz = KartPhysics.forward(yaw)
	return math.atan2(fx * dz - fz * dx, fx * dx + fz * dz)
end

function AIDriver.input(
	track: Track.Built,
	proj: Track.Projection,
	pos: Track.Vec,
	s: KartPhysics.State,
	stats: Karts.KartStats,
	profile: Profile
): KartPhysics.Input
	local lookahead = 28 + math.max(s.speed, 0) * 0.42
	local target, tangent = Track.at(track, proj.distance + lookahead)
	-- Lane offset: right of travel is (-tz, tx) in this coordinate frame.
	local tl = math.sqrt(tangent.x * tangent.x + tangent.z * tangent.z)
	local rx, rz = -tangent.z / tl, tangent.x / tl
	local laneOffset = profile.lane * track.def.width * 0.28
	local tx = target.x + rx * laneOffset - pos.x
	local tz = target.z + rz * laneOffset - pos.z

	local angle = AIDriver.angleTo(s.yaw, tx, tz)
	local steer = math.clamp(angle * 2.4, -1, 1)

	local throttle = 1
	if math.abs(angle) > 0.7 and s.speed > stats.topSpeed * 0.6 then
		throttle = 0.2
	end

	-- Drift through bends that will last a while; skilled drivers drift more.
	local drift = false
	local farTarget = Track.at(track, proj.distance + lookahead * 2)
	local farAngle = AIDriver.angleTo(s.yaw, farTarget.x - pos.x, farTarget.z - pos.z)
	if s.drift ~= 0 then
		drift = math.sign(angle) == s.drift and math.abs(angle) > 0.06
	elseif math.abs(farAngle) > 0.35 - 0.12 * profile.skill and math.abs(angle) > 0.12 and math.sign(farAngle) == math.sign(angle) then
		drift = true
	end

	return { throttle = throttle, steer = steer, drift = drift, grounded = true, surface = "road" }
end

return AIDriver
