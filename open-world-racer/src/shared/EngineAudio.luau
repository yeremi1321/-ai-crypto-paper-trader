--!strict
-- Simulated gearbox and engine sound parameters. The client feeds in speed and
-- throttle; this returns gear, RPM and the pitch/volume to play, so engines
-- rise with RPM, drop on upshifts and change character with upgrades.

export type Profile = {
	idleRpm: number,
	redline: number,
	gears: number,
	basePitch: number, -- pitch at idle
	pitchRange: number, -- extra pitch at redline
	soundId: string,
}

local EngineAudio = {}

-- Set soundId to an uploaded engine loop (rbxassetid://...). Empty = silent.
EngineAudio.Profiles = {
	inline4 = { idleRpm = 900, redline = 7200, gears = 5, basePitch = 0.9, pitchRange = 1.1, soundId = "" },
	v6 = { idleRpm = 800, redline = 6800, gears = 6, basePitch = 0.8, pitchRange = 1.0, soundId = "" },
	inline6turbo = { idleRpm = 850, redline = 7800, gears = 6, basePitch = 0.85, pitchRange = 1.15, soundId = "" },
	v8 = { idleRpm = 700, redline = 6500, gears = 6, basePitch = 0.7, pitchRange = 0.9, soundId = "" },
	v10 = { idleRpm = 1000, redline = 8700, gears = 7, basePitch = 0.95, pitchRange = 1.3, soundId = "" },
} :: { [string]: Profile }

export type EngineState = { gear: number, rpm: number, pitch: number, volume: number }

-- Each gear covers a growing slice of top speed (short first gear, long top gear).
function EngineAudio.gearFor(speedFrac: number, gears: number): (number, number)
	speedFrac = math.clamp(speedFrac, 0, 1)
	local total = 0
	for g = 1, gears do
		total += g
	end
	local upper = 0
	for g = 1, gears do
		local lower = upper
		upper += g / total
		if speedFrac <= upper or g == gears then
			-- Fraction through this gear, starting at ~35% of the rev range after a shift.
			local within = (speedFrac - lower) / (upper - lower)
			local low = if g == 1 then 0 else 0.35
			return g, low + (1 - low) * math.clamp(within, 0, 1)
		end
	end
	return gears, 1
end

function EngineAudio.state(profile: Profile, speed: number, topSpeed: number, throttle: number, hasTurbo: boolean?): EngineState
	local gear, revFrac = EngineAudio.gearFor(math.abs(speed) / math.max(topSpeed, 1), profile.gears)
	-- Blipping the throttle at standstill still revs the engine.
	revFrac = math.max(revFrac, math.abs(throttle) * 0.3)
	local rpm = profile.idleRpm + (profile.redline - profile.idleRpm) * revFrac
	local pitch = profile.basePitch + profile.pitchRange * revFrac + (if hasTurbo then 0.05 else 0)
	local volume = 0.35 + 0.35 * revFrac + 0.3 * math.abs(throttle)
	return { gear = gear, rpm = math.floor(rpm), pitch = pitch, volume = math.clamp(volume, 0, 1) }
end

return EngineAudio
