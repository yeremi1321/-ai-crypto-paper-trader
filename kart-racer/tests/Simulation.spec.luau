-- Full race simulation: eight CPU drivers race every track using the real
-- handling, track and AI code. Positions move kinematically (no Roblox
-- physics), walls stop karts at the barrier. Catches corners that are too
-- tight, broken lap counting and AI that can't get round.
local T = require("./TestLib")
local AIDriver = require("../src/shared/AIDriver")
local KartPhysics = require("../src/shared/KartPhysics")
local Karts = require("../src/shared/Karts")
local RaceRules = require("../src/shared/RaceRules")
local Track = require("../src/shared/Track")
local Tracks = require("../src/shared/Tracks")

local DT = 1 / 30

local function simulate(def)
	local track = Track.build(def)
	local racers = {}
	for slot = 1, 8 do
		local driver = Karts.CpuDrivers[slot]
		local pos, gridD = Track.gridSpot(track, slot)
		local _, tan = Track.at(track, gridD)
		local yaw = math.atan2(-tan.x, -tan.z)
		table.insert(racers, {
			id = driver.name,
			stats = Karts.get(driver.kart).stats,
			profile = { lane = ((slot % 3) - 1) * 0.6, skill = 0.5 + (slot % 4) * 0.15 },
			pos = pos,
			state = KartPhysics.newState(yaw),
			progress = Track.newProgress(track, gridD),
			finishTime = nil,
			wallTime = 0,
			offroadTime = 0,
			drifts = 0,
		})
	end

	local t = 0
	while t < 400 do
		t += DT
		local allDone = true
		for _, r in racers do
			if r.finishTime then
				continue
			end
			allDone = false
			local proj = Track.project(track, r.pos, r.progress.index)
			local surface = Track.surfaceAt(track, proj)
			local input = AIDriver.input(track, proj, r.pos, r.state, r.stats, r.profile)
			input.surface = if surface == "wall" then "offroad" else surface
			local before = r.state.drift
			KartPhysics.step(r.stats, r.state, input, DT)
			if before == 0 and r.state.drift ~= 0 then
				r.drifts += 1
			end

			local fx, fz = KartPhysics.forward(r.state.yaw)
			local nx, nz = r.pos.x + fx * r.state.speed * DT, r.pos.z + fz * r.state.speed * DT
			local nextProj = Track.project(track, Track.v(nx, r.pos.y, nz), proj.index)
			local limit = def.width / 2 + Track.ShoulderWidth
			if math.abs(nextProj.lateral) > limit then
				-- Barrier: slide along it and lose speed.
				local spot = Track.spot(track, nextProj.distance, math.sign(nextProj.lateral) * (limit - 0.5))
				nx, nz = spot.x, spot.z
				r.state.speed *= 0.97
				r.wallTime += DT
			end
			if surface == "offroad" then
				r.offroadTime += DT
			end
			local ground = Track.spot(track, nextProj.distance, nextProj.lateral)
			r.pos = Track.v(nx, ground.y, nz)

			if Track.updateProgress(track, r.progress, Track.project(track, r.pos, r.progress.index)) then
				if r.progress.lap > def.laps then
					r.finishTime = t
				end
			end
		end
		if allDone then
			break
		end
	end
	return track, racers
end

for _, def in Tracks.List do
	T.test(`8 CPU drivers finish {def.laps} laps of {def.name}`, function()
		local _, racers = simulate(def)
		local entries = {}
		for _, r in racers do
			T.ok(r.finishTime, `{r.id} did not finish (lap {r.progress.lap}, sector {r.progress.sector})`)
			local lapTime = r.finishTime / def.laps
			T.ok(lapTime > 15 and lapTime < 60, `{r.id} lap time {lapTime}`)
			T.ok(r.wallTime < r.finishTime * 0.08, `{r.id} scraped the wall for {r.wallTime}s`)
			T.ok(r.offroadTime < r.finishTime * 0.15, `{r.id} offroad for {r.offroadTime}s`)
			table.insert(entries, { id = r.id, finished = true, finishTime = r.finishTime, score = 0 })
		end
		local ranked = RaceRules.rank(entries)
		print(`     {def.name}: winner {ranked[1].id} {string.format("%.1f", ranked[1].finishTime)}s, last {string.format("%.1f", ranked[8].finishTime)}s`)
	end)
end

T.test("CPU drivers actually drift", function()
	local _, racers = simulate(Tracks.List[1])
	local total = 0
	for _, r in racers do
		total += r.drifts
	end
	T.ok(total >= 8, `only {total} drifts`)
end)
