-- The game loop: lobby → Grand Prix (every track in the cup) → results → lobby.
-- Empty grid slots are filled with CPU drivers so solo play works. Players
-- drive their own karts on their client; the server tracks positions, laps,
-- respawns, items and points, and drives the CPU karts itself.

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
local Tracks = require(Shared.Tracks)
local KartRig = require(ReplicatedStorage.Common.KartRig)

local ItemService = require(script.Parent.ItemService)
local Net = require(script.Parent.Net)
local TrackBuilder = require(script.Parent.TrackBuilder)

local RaceService = {}

local LOBBY_WAIT = 15 -- seconds after the first player readies up
local LOAD_TIME = 3 -- time for clients to see the track before the countdown
local RESULTS_TIME = 9
local CUP_RESULTS_TIME = 14
local END_GRACE = 4 -- after the last player finishes
local FALL_DEPTH = 18
local TICK = 1 / 20

export type Entrant = {
	id: string,
	name: string,
	isCpu: boolean,
	player: Player?,
	kartId: string,
	look: KartBodies.Look,
	points: number,
	lastPlace: number,
	profile: AIDriver.Profile,
}

export type Racer = {
	entrant: Entrant,
	model: Model,
	state: KartPhysics.State?, -- CPU karts only; players simulate their own
	stats: Karts.KartStats,
	progress: Track.Progress,
	score: number,
	place: number,
	finishTime: number?,
	invincibleUntil: number,
	speedFactor: number,
	-- Items (managed by ItemService)
	item: string?,
	uses: number,
	itemReadyAt: number,
	cpuUseAt: number,
}

type Race = {
	trackId: string,
	track: Track.Built,
	racers: { Racer },
	goTime: number,
	endAt: number?,
	timeLimit: number,
	lastBroadcast: number,
}

local phase = "lobby"
local choices: { [Player]: { kart: string, look: KartBodies.Look, ready: boolean } } = {}

local function newChoice(): { kart: string, look: KartBodies.Look, ready: boolean }
	return { kart = Karts.Default, look = KartBodies.sanitize(nil), ready = false }
end
local firstReadyAt: number? = nil
local cup: { trackIndex: number, entrants: { Entrant } }? = nil
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
	local items = Workspace:FindFirstChild("Items")
	if items then
		table.insert(ignore, items)
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

function Effects.hit(racer: Racer): boolean
	if now() < racer.invincibleUntil then
		return false
	end
	if racer.state then
		return KartPhysics.hit(racer.state)
	end
	if racer.entrant.player then
		Net.KartEvent:FireClient(racer.entrant.player, "hit")
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

function Effects.itemChanged(racer: Racer)
	if racer.entrant.player then
		Net.ItemState:FireClient(racer.entrant.player, racer.item, racer.uses, racer.itemReadyAt)
	end
end

---------------------------------------------------------------------------
-- Lobby
---------------------------------------------------------------------------
local function buildLobby()
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(120, 2, 120)
	floor.Position = Vector3.new(0, 400, 1200)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = Color3.fromRGB(40, 44, 60)
	floor.Parent = lobby
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = floor.Position + Vector3.new(0, 1.5, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(255, 200, 40)
	spawn.Material = Enum.Material.Neon
	spawn.Parent = lobby
	-- Showroom: every body design on display.
	local count = #KartBodies.List
	for i, body in KartBodies.List do
		local x = (i - (count + 1) / 2) * 14
		local cf = CFrame.new(floor.Position + Vector3.new(x, 1, -26)) * CFrame.Angles(0, math.pi, 0)
		local look = KartBodies.cpuLook(i)
		look.body = body.id
		local display = KartRig.build(Karts.Default, body.name, cf, lobby, look)
		display.PrimaryPart.Anchored = true
	end
	lobby.Parent = Workspace
end

local function lobbyState()
	local list = {}
	for player, c in choices do
		table.insert(list, { name = player.DisplayName, kart = c.kart, body = c.look.body, ready = c.ready })
	end
	return {
		phase = phase,
		players = list,
		startsAt = if firstReadyAt then firstReadyAt + LOBBY_WAIT else nil,
		cupName = Tracks.Cup.name,
		raceNumber = cup and cup.trackIndex,
		raceCount = #Tracks.Cup.tracks,
	}
end

local function broadcastLobby()
	Net.Lobby:FireAllClients(lobbyState())
end

---------------------------------------------------------------------------
-- Racing
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
		character:PivotTo(seat.CFrame + Vector3.new(0, 2, 0))
		seat:Sit(humanoid)
	end
end

local function startRace(index: number)
	assert(cup, "no cup")
	cup.trackIndex = index
	local trackId = Tracks.Cup.tracks[index]
	local _, track = TrackBuilder.build(trackId)
	kartsFolder:ClearAllChildren()

	-- Grid: race 1 puts players at the back; later races reverse the standings.
	local order = table.clone(cup.entrants)
	if index == 1 then
		table.sort(order, function(a, b)
			if a.isCpu ~= b.isCpu then
				return a.isCpu
			end
			return a.id < b.id
		end)
	else
		table.sort(order, function(a, b)
			if a.points ~= b.points then
				return a.points < b.points
			end
			return a.id < b.id
		end)
	end

	local r: Race = {
		trackId = trackId,
		track = track,
		racers = {},
		goTime = now() + LOAD_TIME + RaceRules.CountdownSeconds,
		timeLimit = track.def.laps * 120,
		lastBroadcast = 0,
	}

	for slot, entrant in order do
		local pos, gridD = Track.gridSpot(track, slot)
		local _, tan = Track.at(track, gridD)
		local yaw = yawFromTangent(tan)
		local cf = CFrame.new(pos.x, pos.y, pos.z) * CFrame.Angles(0, yaw, 0)
		local model = KartRig.build(entrant.kartId, entrant.name, cf, kartsFolder, entrant.look)
		model.PrimaryPart.Anchored = true
		local stats = Karts.get(entrant.kartId).stats
		local racer: Racer = {
			entrant = entrant,
			model = model,
			state = if entrant.isCpu then KartPhysics.newState(yaw) else nil,
			stats = stats,
			progress = Track.newProgress(track, gridD),
			score = 0,
			place = slot,
			finishTime = nil,
			invincibleUntil = 0,
			speedFactor = 1,
			item = nil,
			uses = 0,
			itemReadyAt = 0,
			cpuUseAt = 0,
		}
		racer.score = Track.score(track, racer.progress)
		table.insert(r.racers, racer)

		if entrant.player then
			seatDriver(entrant.player, model)
			Net.ItemState:FireClient(entrant.player, nil, 0, 0)
			Net.RaceStart:FireClient(entrant.player, {
				trackId = trackId,
				trackName = track.def.name,
				kart = model,
				kartId = entrant.kartId,
				yaw = yaw,
				goTime = r.goTime,
				laps = track.def.laps,
				raceNumber = index,
				raceCount = #Tracks.Cup.tracks,
			})
		end
	end

	ItemService.setup(track)
	race = r
	phase = "racing"
	refreshRayFilter()
	broadcastLobby()

	task.delay(r.goTime - now(), function()
		if race ~= r then
			return
		end
		for _, racer in r.racers do
			local root = racer.model.PrimaryPart
			if root then
				root.Anchored = false
				local player = racer.entrant.player
				if player and player.Parent then
					root:SetNetworkOwner(player)
				else
					root:SetNetworkOwner(nil)
				end
			end
		end
	end)
end

local function respawn(r: Race, racer: Racer)
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
	elseif racer.entrant.player then
		Net.KartEvent:FireClient(racer.entrant.player, "respawn", yaw)
	end
end

local function standings(r: Race)
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

local function raceStateFor(r: Race, ranked: { Racer }, me: Racer)
	local rows = {}
	for _, racer in ranked do
		table.insert(rows, { name = racer.entrant.name, isCpu = racer.entrant.isCpu, finished = racer.finishTime ~= nil })
	end
	return {
		place = me.place,
		field = #ranked,
		lap = math.clamp(me.progress.lap, 1, r.track.def.laps),
		laps = r.track.def.laps,
		finishTime = me.finishTime,
		rows = rows,
	}
end

local function endRace(r: Race)
	if race ~= r or not cup then
		return
	end
	race = nil
	phase = "results"
	local ranked = standings(r)
	local rows = {}
	for place, racer in ranked do
		local gained = RaceRules.pointsFor(place)
		racer.entrant.points += gained
		racer.entrant.lastPlace = place
		table.insert(rows, {
			place = place,
			name = racer.entrant.name,
			isCpu = racer.entrant.isCpu,
			time = racer.finishTime,
			gained = gained,
			total = racer.entrant.points,
		})
	end
	ItemService.clear()
	kartsFolder:ClearAllChildren()

	local lastRace = cup.trackIndex >= #Tracks.Cup.tracks
	Net.Results:FireAllClients({ kind = "race", trackName = r.track.def.name, rows = rows, lastRace = lastRace })
	for _, entrant in cup.entrants do
		if entrant.player and entrant.player.Parent then
			entrant.player:LoadCharacter()
		end
	end

	task.wait(RESULTS_TIME)
	if not lastRace and cup and RaceService.humansInCup() > 0 then
		startRace(cup.trackIndex + 1)
		return
	end

	-- Final cup standings.
	if cup then
		local cupRows = {}
		for _, e in cup.entrants do
			table.insert(cupRows, { id = e.id, name = e.name, points = e.points, lastPlace = e.lastPlace })
		end
		local final = RaceRules.cupStandings(cupRows)
		local out = {}
		for i, row in final do
			table.insert(out, { place = i, name = row.name, total = row.points })
		end
		Net.Results:FireAllClients({ kind = "cup", cupName = Tracks.Cup.name, rows = out })
		task.wait(CUP_RESULTS_TIME)
	end
	RaceService.toLobby()
end

function RaceService.humansInCup(): number
	local count = 0
	if cup then
		for _, e in cup.entrants do
			if e.player and e.player.Parent then
				count += 1
			end
		end
	end
	return count
end

function RaceService.toLobby()
	race = nil
	cup = nil
	phase = "lobby"
	firstReadyAt = nil
	ItemService.clear()
	kartsFolder:ClearAllChildren()
	local track = Workspace:FindFirstChild("Track")
	if track then
		track:Destroy()
	end
	for player, c in choices do
		c.ready = false
		if player.Character == nil then
			player:LoadCharacter()
		end
	end
	broadcastLobby()
end

local function startCup()
	local entrants: { Entrant } = {}
	for player, c in choices do
		if c.ready then
			table.insert(entrants, {
				id = `u{player.UserId}`,
				name = player.DisplayName,
				isCpu = false,
				player = player,
				kartId = c.kart,
				look = c.look,
				points = 0,
				lastPlace = 0,
				profile = { lane = 0, skill = 1 },
			})
		end
	end
	local cpuIndex = 0
	while #entrants < RaceRules.MaxRacers do
		cpuIndex += 1
		local driver = Karts.CpuDrivers[cpuIndex]
		table.insert(entrants, {
			id = `cpu{cpuIndex}`,
			name = driver.name,
			isCpu = true,
			kartId = driver.kart,
			look = KartBodies.cpuLook(cpuIndex),
			points = 0,
			lastPlace = 0,
			profile = { lane = ((cpuIndex % 3) - 1) * 0.6, skill = 0.45 + (cpuIndex % 4) * 0.15 },
		})
	end
	cup = { trackIndex = 1, entrants = entrants }
	firstReadyAt = nil
	startRace(1)
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
		local pos = vec(root.Position)
		local proj = Track.project(track, pos, racer.progress.index)
		local roadY = Track.spot(track, proj.distance, 0).y
		if proj.gap > track.def.width + Track.ShoulderWidth * 2 or root.Position.Y < roadY - FALL_DEPTH then
			respawn(r, racer)
		elseif Track.updateProgress(track, racer.progress, proj) then
			local player = racer.entrant.player
			if racer.progress.lap > track.def.laps and not racer.finishTime then
				racer.finishTime = t - r.goTime
				if player then
					Net.Notify:FireClient(player, "FINISH!")
				end
			elseif player and racer.progress.lap == track.def.laps then
				Net.Notify:FireClient(player, "FINAL LAP!")
			elseif player and racer.progress.lap > 1 then
				Net.Notify:FireClient(player, `Lap {racer.progress.lap}`)
			end
		end
		racer.score = Track.score(track, racer.progress)

		local player = racer.entrant.player
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
		task.spawn(RaceService.toLobby)
		return
	end
	if humansRacing == 0 and not r.endAt then
		r.endAt = t + END_GRACE
	end
	if (r.endAt and t >= r.endAt) or t - r.goTime > r.timeLimit then
		task.spawn(endRace, r)
	end
end

---------------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------------
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

function RaceService.start()
	buildLobby()

	Players.PlayerAdded:Connect(function(player)
		choices[player] = newChoice()
		task.delay(1, broadcastLobby)
	end)
	for _, player in Players:GetPlayers() do
		choices[player] = newChoice()
	end
	Players.PlayerRemoving:Connect(function(player)
		choices[player] = nil
		local racer = findRacer(player)
		if racer then
			racer.model:Destroy()
			table.remove(race.racers, table.find(race.racers, racer) :: number)
		end
		broadcastLobby()
	end)

	Net.ChooseKart.OnServerEvent:Connect(function(player, kartId)
		local c = choices[player]
		if c and phase == "lobby" then
			c.kart = Karts.get(tostring(kartId)).id
			broadcastLobby()
		end
	end)
	Net.ChooseLook.OnServerEvent:Connect(function(player, look)
		local c = choices[player]
		if c and phase == "lobby" then
			c.look = KartBodies.sanitize(look)
			broadcastLobby()
		end
	end)
	Net.Ready.OnServerEvent:Connect(function(player, isReady)
		local c = choices[player]
		if c and phase == "lobby" then
			c.ready = isReady == true
			if c.ready and not firstReadyAt then
				firstReadyAt = now()
			end
			broadcastLobby()
		end
	end)
	Net.UseItem.OnServerEvent:Connect(function(player)
		local racer = findRacer(player)
		if racer and race and now() >= race.goTime then
			ItemService.use(race.track, race.racers, racer, Effects)
		end
	end)

	-- Lobby: start when everyone is ready, or LOBBY_WAIT after the first ready.
	task.spawn(function()
		while true do
			task.wait(1)
			if phase == "lobby" then
				local total, ready = 0, 0
				for _, c in choices do
					total += 1
					if c.ready then
						ready += 1
					end
				end
				if ready == 0 then
					firstReadyAt = nil
				elseif ready == total or (firstReadyAt and now() >= firstReadyAt + LOBBY_WAIT) then
					local ok, err = pcall(startCup)
					if not ok then
						warn("[RaceService] could not start the cup:", err)
						RaceService.toLobby()
					end
				end
				broadcastLobby()
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			local r = race
			if r then
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
end

return RaceService
