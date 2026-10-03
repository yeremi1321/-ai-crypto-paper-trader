-- Runs one race: builds the track, puts karts on the grid, counts down,
-- tracks positions and laps, respawns fallen karts, drives the CPU karts,
-- runs items, and reports results. RoundService decides when races happen
-- and who is in them.
--
-- Players drive their own karts on their client. The server checks progress
-- (ordered sectors, so skipping the course never counts) and decides
-- placings, item hits and the finish.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local AIDriver = require(Shared.AIDriver)
local KartBodies = require(Shared.KartBodies)
local KartPhysics = require(Shared.KartPhysics)
local Karts = require(Shared.Karts)
local RaceRules = require(Shared.RaceRules)
local Track = require(Shared.Track)
local KartRig = require(ReplicatedStorage.Common.KartRig)

local ItemService = require(script.Parent.ItemService)
local Net = require(script.Parent.Net)
local TrackBuilder = require(script.Parent.TrackBuilder)

local RaceService = {}

local LOAD_TIME = 3 -- time for clients to see the track before the countdown
local END_GRACE = 4 -- after the last player finishes
local FINISH_TIMEOUT = 30 -- once any player finishes, the rest get this long
local FALL_DEPTH = 18
local TICK = 1 / 20
local RESPAWN_COOLDOWN = 2

export type Entrant = {
	id: string,
	name: string,
	isCpu: boolean,
	player: Player?,
	kartId: string,
	look: KartBodies.Look,
	profile: AIDriver.Profile,
}

export type Racer = {
	entrant: Entrant,
	model: Model,
	state: KartPhysics.State?, -- CPU karts (and players who finished); players simulate their own
	stats: Karts.KartStats,
	progress: Track.Progress,
	score: number,
	place: number,
	finishTime: number?,
	invincibleUntil: number,
	protectUntil: number, -- brief immunity after any hit, so nobody gets juggled
	speedFactor: number,
	lastRespawn: number,
	-- Stats for results and awards
	worstPlace: number,
	hitsTaken: number,
	-- Items (managed by ItemService)
	item: string?,
	uses: number,
	itemReadyAt: number,
	cpuUseAt: number,
}

export type ResultRow = {
	place: number,
	id: string,
	name: string,
	isCpu: boolean,
	userId: number?,
	time: number?,
	finished: boolean,
	kartId: string,
	look: KartBodies.Look,
	worstPlace: number,
	hitsTaken: number,
}

type Race = {
	trackId: string,
	track: Track.Built,
	racers: { Racer },
	goTime: number,
	endAt: number?,
	timeLimit: number,
	lastBroadcast: number,
	onEnded: (({ ResultRow }, string) -> ())?,
	ended: boolean,
}

local race: Race? = nil

local kartsFolder = Instance.new("Folder")
kartsFolder.Name = "Karts"
kartsFolder.Parent = Workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function vec(p: Vector3): Track.Vec
	return Track.v(p.X, p.Y, p.Z)
end

local function refreshRayFilter()
	local ignore: { Instance } = { kartsFolder }
	for _, name in { "Items", "PracticeKarts" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
end

---------------------------------------------------------------------------
-- Effects (also used by ItemService)
---------------------------------------------------------------------------
local Effects = {}
RaceService.Effects = Effects

local HIT_PROTECTION = 2.5

-- Returns true if the hit landed. Overdrive and the post-hit grace period block it.
function Effects.hit(racer: Racer, kind: string?): boolean
	local t = now()
	if t < racer.invincibleUntil or t < racer.protectUntil then
		return false
	end
	racer.protectUntil = t + HIT_PROTECTION
	racer.hitsTaken += 1
	local hitKind = kind or "spin"
	if racer.state then
		if hitKind == "slow" then
			KartPhysics.slow(racer.state, 2)
		else
			KartPhysics.hit(racer.state)
		end
		if hitKind == "launch" and racer.model.PrimaryPart then
			local root = racer.model.PrimaryPart
			root.AssemblyLinearVelocity += Vector3.new(0, 70, 0)
		end
	elseif racer.entrant.player then
		Net.KartEvent:FireClient(racer.entrant.player, hitKind)
	end
	return true
end

function Effects.boost(racer: Racer, seconds: number)
	if racer.state then
		KartPhysics.giveBoost(racer.state, seconds)
	elseif racer.entrant.player then
		Net.KartEvent:FireClient(racer.entrant.player, "boost", seconds)
	end
end

function Effects.overdrive(racer: Racer, seconds: number)
	racer.invincibleUntil = now() + seconds
	if racer.state then
		KartPhysics.overdrive(racer.state, seconds)
	elseif racer.entrant.player then
		Net.KartEvent:FireClient(racer.entrant.player, "overdrive", seconds)
	end
end

function Effects.warn(racer: Racer, text: string)
	if racer.entrant.player then
		Net.KartEvent:FireClient(racer.entrant.player, "warning", text)
	end
end

function Effects.itemChanged(racer: Racer)
	if racer.entrant.player then
		Net.ItemState:FireClient(racer.entrant.player, racer.item, racer.uses, racer.itemReadyAt)
	end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function yawFromTangent(tan: Track.Vec): number
	return math.atan2(-tan.x, -tan.z)
end

local function scaledStats(base: Karts.KartStats, factor: number): Karts.KartStats
	return { topSpeed = base.topSpeed * factor, accel = base.accel, handling = base.handling, weight = base.weight }
end

local function seatDriver(player: Player, model: Model)
	local character = player.Character
	if not character or not character.Parent then
		player:LoadCharacter()
		character = player.Character or player.CharacterAdded:Wait()
	end
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	local seat = model:FindFirstChild("DriverSeat") :: Seat
	if humanoid and seat then
		humanoid.Sit = false
		character:PivotTo(seat.CFrame + Vector3.new(0, 2, 0))
		seat:Sit(humanoid)
	end
end

local function respawn(r: Race, racer: Racer)
	racer.lastRespawn = now()
	local d = racer.progress.distance
	local pos = Track.spot(r.track, d, 0)
	local _, tan = Track.at(r.track, d)
	local yaw = yawFromTangent(tan)
	KartRig.place(racer.model, CFrame.new(pos.x, pos.y, pos.z) * CFrame.Angles(0, yaw, 0))
	if racer.state then
		racer.state.speed = 0
		racer.state.yaw = yaw
		racer.state.drift = 0
		racer.state.charge = 0
	end
	if racer.entrant.player then
		Net.KartEvent:FireClient(racer.entrant.player, "respawn", yaw)
	end
	-- A moment of protection so nothing hits you while getting going again.
	racer.protectUntil = math.max(racer.protectUntil, now() + 2)
end

local function standings(r: Race): { Racer }
	local entries = {}
	local byId = {}
	for _, racer in r.racers do
		table.insert(entries, { id = racer.entrant.id, finished = racer.finishTime ~= nil, finishTime = racer.finishTime, score = racer.score })
		byId[racer.entrant.id] = racer
	end
	local ranked = RaceRules.rank(entries)
	local out = {}
	for place, e in ranked do
		local racer = byId[e.id]
		racer.place = place
		table.insert(out, racer)
	end
	return out
end

local function rowsOf(ranked: { Racer })
	local rows = {}
	for _, racer in ranked do
		table.insert(rows, {
			name = racer.entrant.name,
			isCpu = racer.entrant.isCpu,
			finished = racer.finishTime ~= nil,
			kart = racer.model.Name,
		})
	end
	return rows
end

local function raceStateFor(r: Race, ranked: { Racer }, me: Racer)
	return {
		place = me.place,
		field = #ranked,
		lap = math.clamp(me.progress.lap, 1, r.track.def.laps),
		laps = r.track.def.laps,
		finishTime = me.finishTime,
		rows = rowsOf(ranked),
		endAt = r.endAt,
	}
end

-- A player who has finished keeps cruising under CPU control while they spectate.
local function autopilot(racer: Racer)
	local root = racer.model.PrimaryPart
	if racer.state or not root then
		return
	end
	local look = root.CFrame.LookVector
	local s = KartPhysics.newState(math.atan2(-look.X, -look.Z))
	s.speed = math.max(0, root.AssemblyLinearVelocity:Dot(Vector3.new(look.X, 0, look.Z)))
	racer.state = s
	if root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil)
	end
end

local function finishRace(r: Race)
	if r.ended then
		return
	end
	r.ended = true
	if race == r then
		race = nil
	end
	local ranked = standings(r)
	local rows: { ResultRow } = {}
	for place, racer in ranked do
		table.insert(rows, {
			place = place,
			id = racer.entrant.id,
			name = racer.entrant.name,
			isCpu = racer.entrant.isCpu,
			userId = racer.entrant.player and racer.entrant.player.UserId,
			time = racer.finishTime,
			finished = racer.finishTime ~= nil,
			kartId = racer.entrant.kartId,
			look = racer.entrant.look,
			worstPlace = racer.worstPlace,
			hitsTaken = racer.hitsTaken,
		})
	end
	ItemService.clear()
	kartsFolder:ClearAllChildren()
	if r.onEnded then
		r.onEnded(rows, r.trackId)
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Starts a race. `onEnded(rows, trackId)` is called once with the final placings.
function RaceService.startRace(trackId: string, entrants: { Entrant }, onEnded: ({ ResultRow }, string) -> ())
	if race then
		finishRace(race)
	end
	local _, track = TrackBuilder.build(trackId)
	kartsFolder:ClearAllChildren()

	-- Grid: CPUs at the front, players at the back, so players get to overtake.
	local order = table.clone(entrants)
	table.sort(order, function(a, b)
		if a.isCpu ~= b.isCpu then
			return a.isCpu
		end
		return a.id < b.id
	end)

	local r: Race = {
		trackId = trackId,
		track = track,
		racers = {},
		goTime = now() + LOAD_TIME + RaceRules.CountdownSeconds,
		timeLimit = track.def.laps * 150,
		lastBroadcast = 0,
		onEnded = onEnded,
		ended = false,
	}

	for slot, entrant in order do
		local pos, gridD = Track.gridSpot(track, slot)
		local _, tan = Track.at(track, gridD)
		local yaw = yawFromTangent(tan)
		local cf = CFrame.new(pos.x, pos.y, pos.z) * CFrame.Angles(0, yaw, 0)
		local model = KartRig.build(entrant.kartId, entrant.name, cf, kartsFolder, entrant.look)
		model.PrimaryPart.Anchored = true
		local racer: Racer = {
			entrant = entrant,
			model = model,
			state = if entrant.isCpu then KartPhysics.newState(yaw) else nil,
			stats = Karts.get(entrant.kartId).stats,
			progress = Track.newProgress(track, gridD),
			score = 0,
			place = slot,
			finishTime = nil,
			invincibleUntil = 0,
			protectUntil = 0,
			speedFactor = 1,
			lastRespawn = 0,
			worstPlace = slot,
			hitsTaken = 0,
			item = nil,
			uses = 0,
			itemReadyAt = 0,
			cpuUseAt = 0,
		}
		racer.score = Track.score(track, racer.progress)
		table.insert(r.racers, racer)
	end

	race = r
	ItemService.setup(track)
	refreshRayFilter()

	for _, racer in r.racers do
		local player = racer.entrant.player
		if player then
			task.spawn(function()
				seatDriver(player, racer.model)
				Net.ItemState:FireClient(player, nil, 0, 0)
				Net.RaceStart:FireClient(player, {
					trackId = trackId,
					trackName = track.def.name,
					theme = track.def.theme,
					kart = racer.model,
					kartId = racer.entrant.kartId,
					yaw = racer.state and racer.state.yaw or yawFromTangent(select(2, Track.at(track, racer.progress.distance))),
					goTime = r.goTime,
					laps = track.def.laps,
				})
			end)
		end
	end

	task.delay(r.goTime - now(), function()
		if race ~= r then
			return
		end
		for _, racer in r.racers do
			local root = racer.model.PrimaryPart
			if root then
				root.Anchored = false
				local player = racer.entrant.player
				if player and player.Parent and not racer.state then
					root:SetNetworkOwner(player)
				else
					root:SetNetworkOwner(nil)
				end
			end
		end
	end)
end

function RaceService.isRunning(): boolean
	return race ~= nil
end

function RaceService.isRacing(player: Player): boolean
	if race then
		for _, racer in race.racers do
			if racer.entrant.player == player then
				return true
			end
		end
	end
	return false
end

-- What lobby spectators see: track name and live standings.
function RaceService.spectatorInfo()
	local r = race
	if not r then
		return nil
	end
	local ranked = {}
	for _, racer in r.racers do
		table.insert(ranked, racer)
	end
	table.sort(ranked, function(a, b)
		return a.place < b.place
	end)
	return {
		trackName = r.track.def.name,
		theme = r.track.def.theme,
		rows = rowsOf(ranked),
		goTime = r.goTime,
	}
end

function RaceService.abort()
	if race then
		finishRace(race)
	end
end

local function findRacer(player: Player): Racer?
	if race then
		for _, racer in race.racers do
			if racer.entrant.player == player then
				return racer
			end
		end
	end
	return nil
end

function RaceService.useItem(player: Player, aimBack: boolean?)
	local racer = findRacer(player)
	if racer and race and now() >= race.goTime and not racer.finishTime then
		ItemService.use(race.track, race.racers, racer, Effects, aimBack == true)
	end
end

-- Manual recovery: puts a stuck kart back on the road (with a short cooldown).
function RaceService.requestRespawn(player: Player)
	local racer = findRacer(player)
	if racer and race and now() >= race.goTime and now() - racer.lastRespawn > RESPAWN_COOLDOWN and not racer.finishTime then
		respawn(race, racer)
	end
end

function RaceService.removePlayer(player: Player)
	local racer = findRacer(player)
	if racer and race then
		racer.model:Destroy()
		table.remove(race.racers, table.find(race.racers, racer) :: number)
	end
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function stepCpus(dt: number)
	local r = race
	if not r or now() < r.goTime then
		return
	end
	for _, racer in r.racers do
		local s = racer.state
		local root = racer.model.PrimaryPart
		if not s or not root or root.Anchored then
			continue
		end
		local sensed = KartRig.sense(racer.model, rayParams)
		local pos = vec(root.Position)
		local proj = Track.project(r.track, pos, racer.progress.index)
		local input = AIDriver.input(r.track, proj, pos, s, racer.stats, racer.entrant.profile)
		local surface = Track.surfaceAt(r.track, proj)
		input.surface = if surface == "wall" then "offroad" else surface
		input.grounded = sensed.grounded
		KartPhysics.step(scaledStats(racer.stats, racer.speedFactor), s, input, dt)
		KartRig.sync(racer.model, s)
		KartRig.apply(racer.model, s, sensed)
		KartRig.setEffects(racer.model, if s.drift ~= 0 then KartPhysics.chargeLevel(s.charge) else 0, s.boost > 0)
	end
end

local function tickRace(r: Race)
	local t = now()
	if t < r.goTime then
		return
	end
	local track = r.track
	local humansRacing, humansLeft = 0, 0

	for _, racer in r.racers do
		local root = racer.model.PrimaryPart
		if not root then
			continue
		end
		local player = racer.entrant.player
		local pos = vec(root.Position)
		local proj = Track.project(track, pos, racer.progress.index)
		local roadY = Track.spot(track, proj.distance, 0).y
		if proj.gap > track.def.width + Track.ShoulderWidth * 2 or root.Position.Y < roadY - FALL_DEPTH then
			respawn(r, racer)
		elseif Track.updateProgress(track, racer.progress, proj) then
			if racer.progress.lap > track.def.laps and not racer.finishTime then
				racer.finishTime = t - r.goTime
				if player then
					Net.Notify:FireClient(player, "FINISH!")
					autopilot(racer)
					-- Once any player finishes, the rest have a limited time left.
					if not r.endAt then
						r.endAt = t + FINISH_TIMEOUT
					end
				end
			elseif player and racer.progress.lap == track.def.laps then
				Net.Notify:FireClient(player, "FINAL LAP!")
			elseif player and racer.progress.lap > 1 then
				Net.Notify:FireClient(player, `Lap {racer.progress.lap}`)
			end
		end
		racer.score = Track.score(track, racer.progress)

		if player then
			if not player.Parent then
				continue
			end
			humansLeft += 1
			if not racer.finishTime then
				humansRacing += 1
			end
		end
	end

	local ranked = standings(r)
	for _, racer in ranked do
		racer.worstPlace = math.max(racer.worstPlace, racer.place)
	end

	-- CPU pace: catch up when far behind, ease off when running away from players.
	local leaderScore = ranked[1] and ranked[1].score or 0
	local bestHuman = -math.huge
	for _, racer in r.racers do
		if not racer.entrant.isCpu then
			bestHuman = math.max(bestHuman, racer.score)
		end
	end
	for _, racer in r.racers do
		if racer.entrant.isCpu then
			local lead = if bestHuman > -math.huge then racer.score - bestHuman else 0
			racer.speedFactor = RaceRules.cpuSpeedFactor(leaderScore - racer.score, lead, racer.entrant.profile.skill)
		end
	end

	ItemService.tick(r.track, r.racers, TICK, Effects)

	if t - r.lastBroadcast >= 0.2 then
		r.lastBroadcast = t
		for _, racer in r.racers do
			local player = racer.entrant.player
			if player and player.Parent then
				Net.RaceState:FireClient(player, raceStateFor(r, ranked, racer))
			end
		end
	end

	if humansLeft == 0 then
		finishRace(r)
		return
	end
	if humansRacing == 0 then
		r.endAt = math.min(r.endAt or math.huge, t + END_GRACE)
	end
	if (r.endAt and t >= r.endAt) or t - r.goTime > r.timeLimit then
		finishRace(r)
	end
end

function RaceService.start()
	task.spawn(function()
		while true do
			task.wait(TICK)
			local r = race
			if r and not r.ended then
				local ok, err = pcall(tickRace, r)
				if not ok then
					warn("[RaceService] race tick failed:", err)
				end
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(stepCpus, math.min(dt, 0.1))
		if not ok then
			warn("[RaceService] CPU step failed:", err)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.defer(refreshRayFilter)
		end)
	end)
	Players.PlayerRemoving:Connect(RaceService.removePlayer)
end

return RaceService
