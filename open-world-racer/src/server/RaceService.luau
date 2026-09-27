-- Races happen on the map itself. Drive into an event's start zone to join its
-- lobby; flash races and the midnight meet open temporary zones; any two
-- drivers can challenge each other to a race to a landmark across the city.
-- Lobbies are capped at the class of the first car in, so builds stay fair.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Performance = require(Shared.Performance)
local PlayerProfile = require(Shared.PlayerProfile)
local RaceLogic = require(Shared.RaceLogic)
local Records = require(Shared.Records)
local WorldMap = require(Shared.WorldMap)

local DataService = require(script.Parent.DataService)
local GarageService = require(script.Parent.GarageService)
local Net = require(script.Parent.Net)

local RaceService = {}

local LOBBY_WAIT = 20 -- seconds a fixed event lobby waits for more drivers
local COUNTDOWN = 3
local ZONE_RADIUS = 30
local CHECKPOINT_RADIUS = 40
local FINISH_GRACE = 45 -- once someone finishes, the rest get this long
local MAX_RACERS = 8
local CHALLENGE_RANGE = 150
local CHALLENGE_TIMEOUT = 20

type Lobby = {
	key: string,
	eventId: string?,
	name: string,
	kind: string, -- "event" | "flash" | "midnight" | "challenge"
	payoutKind: string,
	district: string,
	zone: Vector3?,
	zoneRadius: number,
	classCap: string?,
	members: { Player },
	startsAt: number,
	route: { WorldMap.Point },
	laps: number,
	gridStart: WorldMap.Point?,
	gridHeading: WorldMap.Point?,
	boardId: string?,
	persistent: boolean, -- fixed event lobbies vanish when empty
}

type ActiveRace = {
	lobby: Lobby,
	race: RaceLogic.Race,
	members: { [number]: Player },
	lastBroadcast: number,
}

local lobbies: { [string]: Lobby } = {}
local races: { ActiveRace } = {}
local playerLobby: { [Player]: Lobby } = {}
local playerRace: { [Player]: ActiveRace } = {}
local pendingChallenges: { [Player]: { from: Player, expires: number, dest: WorldMap.Place } } = {}
local rejectedUntil: { [Player]: number } = {} -- stops repeat class-cap messages
local boardGuis: { [string]: TextLabel } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function flat(pt: WorldMap.Point): Vector3
	return Vector3.new(pt.x, 0, pt.z)
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function carClass(player: Player): (string?, number?)
	local car = GarageService.getCar(player)
	if not car then
		return nil
	end
	return car:GetAttribute("Class"), car:GetAttribute("Rating")
end

---------------------------------------------------------------------------
-- Lobbies
---------------------------------------------------------------------------

local function eventLobby(eventId: string, key: string, kind: string, startsAt: number): Lobby
	local ev = WorldMap.Events[eventId]
	return {
		key = key,
		eventId = eventId,
		name = ev.name,
		kind = kind,
		payoutKind = if kind == "event" then ev.kind else kind,
		district = ev.district,
		zone = flat(ev.start),
		zoneRadius = ZONE_RADIUS,
		members = {},
		startsAt = startsAt,
		route = ev.checkpoints,
		laps = ev.laps or 1,
		gridStart = ev.start,
		gridHeading = ev.heading,
		boardId = `event:{eventId}`,
		persistent = kind == "event",
	}
end

local function leaveLobby(player: Player, reason: string?)
	local lobby = playerLobby[player]
	if not lobby then
		return
	end
	local i = table.find(lobby.members, player)
	if i then
		table.remove(lobby.members, i)
	end
	playerLobby[player] = nil
	Net.RaceState:FireClient(player, nil)
	if reason then
		Net.Notify:FireClient(player, reason, "info")
	end
	if lobby.persistent and #lobby.members == 0 then
		lobbies[lobby.key] = nil
	end
end

local function lobbyState(lobby: Lobby)
	return {
		phase = "lobby",
		name = lobby.name,
		kind = lobby.kind,
		classCap = lobby.classCap,
		startsAt = lobby.startsAt,
		drivers = #lobby.members,
	}
end

local function joinLobby(player: Player, lobby: Lobby): boolean
	if #lobby.members >= MAX_RACERS then
		return false
	end
	local class = carClass(player)
	if not class then
		return false
	end
	if lobby.classCap and Performance.classRank(class) > Performance.classRank(lobby.classCap) then
		rejectedUntil[player] = now() + 6
		Net.Notify:FireClient(player, `{lobby.name} is running Class {lobby.classCap}. Your car is Class {class}.`, "error")
		return false
	end
	lobby.classCap = lobby.classCap or class
	table.insert(lobby.members, player)
	playerLobby[player] = lobby
	Net.Notify:FireClient(player, `Joined {lobby.name} (Class {lobby.classCap}). Stay in the zone.`, "race")
	for _, member in lobby.members do
		Net.RaceState:FireClient(member, lobbyState(lobby))
	end
	return true
end

-- Opens a temporary lobby (flash race or midnight meet). Returns the lobby.
function RaceService.openSpecial(opts: {
	key: string,
	eventId: string,
	kind: string,
	zone: WorldMap.Point,
	zoneRadius: number?,
	startsAt: number,
	leadIn: boolean?,
	name: string?,
}): Lobby
	if lobbies[opts.key] then
		return lobbies[opts.key]
	end
	local lobby = eventLobby(opts.eventId, opts.key, opts.kind, opts.startsAt)
	lobby.zone = flat(opts.zone)
	lobby.zoneRadius = opts.zoneRadius or ZONE_RADIUS
	lobby.name = opts.name or lobby.name
	if opts.leadIn then
		-- Meet-to-race: everyone drives together from the meet to the start line.
		local ev = WorldMap.Events[opts.eventId]
		local route = { ev.start }
		for _, cp in ev.checkpoints do
			table.insert(route, cp)
		end
		lobby.route = route
		lobby.laps = 1
		lobby.gridStart = nil
		lobby.boardId = nil
	end
	lobbies[opts.key] = lobby
	return lobby
end

function RaceService.hasLobby(key: string): boolean
	return lobbies[key] ~= nil
end

---------------------------------------------------------------------------
-- Racing
---------------------------------------------------------------------------

local function placeOnGrid(lobby: Lobby)
	local start, heading = lobby.gridStart, lobby.gridHeading
	if not start or not heading then
		return
	end
	local dir = Vector3.new(heading.x, 0, heading.z).Unit
	local side = dir:Cross(Vector3.yAxis)
	for i, player in lobby.members do
		local car = GarageService.getCar(player)
		if car and car.PrimaryPart then
			local row, col = (i - 1) // 2, (i - 1) % 2
			local pos = flat(start) - dir * (row * 18) + side * (col * 12 - 6) + Vector3.new(0, 2.3, 0)
			car:PivotTo(CFrame.lookAt(pos, pos + dir))
			car.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
			car.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
			car.PrimaryPart.Anchored = true
		end
	end
end

local function releaseGrid(active: ActiveRace)
	for _, player in active.members do
		local car = GarageService.getCar(player)
		if car and car.PrimaryPart then
			car.PrimaryPart.Anchored = false
		end
	end
end

local function startRace(lobby: Lobby)
	lobbies[lobby.key] = nil
	local startTime = now() + COUNTDOWN
	local race = RaceLogic.new(lobby.key, #lobby.route, lobby.laps, startTime, 300)
	local active: ActiveRace = { lobby = lobby, race = race, members = {}, lastBroadcast = 0 }

	for _, player in lobby.members do
		playerLobby[player] = nil
		playerRace[player] = active
		active.members[player.UserId] = player
		RaceLogic.addRacer(race, player.UserId, player.DisplayName)
		GarageService.setBusy(player, true)
	end
	placeOnGrid(lobby)
	task.delay(COUNTDOWN, releaseGrid, active)
	table.insert(races, active)
end

local function raceState(active: ActiveRace, player: Player)
	local race, lobby = active.race, active.lobby
	local racer = race.racers[player.UserId]
	local standings = RaceLogic.standings(race)
	local place, top = 0, {}
	for _, s in standings do
		if s.id == player.UserId then
			place = s.place
		end
		if #top < 8 then
			table.insert(top, { name = s.name, time = s.time, dnf = s.dnf })
		end
	end
	local nextPt = lobby.route[racer.nextCheckpoint]
	local afterPt = lobby.route[racer.nextCheckpoint + 1]
	return {
		phase = "racing",
		name = lobby.name,
		kind = lobby.kind,
		startTime = race.startTime,
		timeLimit = race.startTime + race.timeLimit,
		lap = racer.lap,
		laps = race.laps,
		checkpoint = racer.nextCheckpoint,
		checkpoints = race.checkpointCount,
		isFinishNext = racer.nextCheckpoint == race.checkpointCount and racer.lap == race.laps,
		next = nextPt and { x = nextPt.x, z = nextPt.z },
		after = afterPt and { x = afterPt.x, z = afterPt.z },
		place = place,
		field = #standings,
		standings = top,
		finished = racer.finishTime,
		dnf = racer.dnf,
	}
end

local function updateBoardGui(boardId: string)
	local label = boardGuis[boardId]
	if not label then
		return
	end
	local lines = {}
	for i, e in DataService.getBoard(boardId) do
		if i > 5 then
			break
		end
		table.insert(lines, `{i}. {e.name}  {Records.formatTime(e.time)}`)
	end
	label.Text = if #lines == 0 then "No times yet.\nBe the first." else table.concat(lines, "\n")
end

local function finishRace(active: ActiveRace)
	local lobby, race = active.lobby, active.race
	local standings = RaceLogic.standings(race)
	local field = #standings
	local summary = {}
	for _, s in standings do
		table.insert(summary, { name = s.name, place = s.place, time = s.time, dnf = s.dnf })
	end

	for _, s in standings do
		local player = active.members[s.id]
		playerRace[player] = nil
		if player.Parent then
			GarageService.setBusy(player, false)
			local profile = DataService.get(player)
			local cash, rep = 0, 0
			if profile then
				cash, rep = PlayerProfile.recordResult(profile, lobby.district, lobby.payoutKind, s.place, field, s.dnf)
			end
			local recordRank = nil
			if not s.dnf and s.time and lobby.boardId then
				local car = GarageService.getCar(player)
				recordRank = DataService.submitRecord(lobby.boardId, {
					userId = player.UserId,
					name = player.DisplayName,
					time = s.time,
					carId = if car then car:GetAttribute("CarId") else "",
				})
			end
			Net.RaceState:FireClient(player, {
				phase = "results",
				name = lobby.name,
				results = summary,
				place = s.place,
				cash = cash,
				rep = rep,
				district = WorldMap.Districts[lobby.district].name,
				recordRank = recordRank,
			})
			GarageService.pushProfile(player)
		end
	end
	if lobby.boardId then
		updateBoardGui(lobby.boardId)
	end
end

local function stepRaces()
	local t = now()
	for i = #races, 1, -1 do
		local active = races[i]
		local race = active.race
		if t >= race.startTime then
			for userId, player in active.members do
				local racer = race.racers[userId]
				if not player.Parent then
					RaceLogic.removeRacer(race, userId)
				elseif not racer.finishTime and not racer.dnf then
					local car = GarageService.getCar(player)
					local target = active.lobby.route[racer.nextCheckpoint]
					if car and car.PrimaryPart and target and flatDist(car.PrimaryPart.Position, flat(target)) <= CHECKPOINT_RADIUS then
						local result = RaceLogic.hitCheckpoint(race, userId, racer.nextCheckpoint, t)
						if result == "finished" then
							race.timeLimit = math.min(race.timeLimit, (t - race.startTime) + FINISH_GRACE)
							Net.Notify:FireClient(player, `Finished! {Records.formatTime(racer.finishTime :: number)}`, "race")
						end
					end
				end
			end
			RaceLogic.tick(race, t)
		end

		if RaceLogic.isOver(race) then
			table.remove(races, i)
			finishRace(active)
		elseif t - active.lastBroadcast >= 0.25 then
			active.lastBroadcast = t
			for _, player in active.members do
				if player.Parent then
					Net.RaceState:FireClient(player, raceState(active, player))
				end
			end
		end
	end
end

local function stepLobbies()
	local t = now()

	for _, player in Players:GetPlayers() do
		if playerRace[player] then
			continue
		end
		local driving = GarageService.isDriving(player)
		local pos = GarageService.position(player)
		local lobby = playerLobby[player]

		if lobby then
			if not driving then
				leaveLobby(player, "You left your car, so you left the lobby.")
			elseif lobby.zone and pos and flatDist(pos, lobby.zone) > lobby.zoneRadius * 2.5 then
				leaveLobby(player, `Left {lobby.name}.`)
			end
		elseif driving and pos and t >= (rejectedUntil[player] or 0) then
			-- Temporary lobbies (flash, meet) win over fixed event zones.
			local best: Lobby? = nil
			for _, l in lobbies do
				if l.zone and flatDist(pos, l.zone) <= l.zoneRadius and (not best or best.persistent) then
					best = l
				end
			end
			if not best then
				for id, ev in WorldMap.Events do
					if flatDist(pos, flat(ev.start)) <= ZONE_RADIUS then
						best = lobbies[`event:{id}`]
						if not best then
							best = eventLobby(id, `event:{id}`, "event", t + LOBBY_WAIT)
							lobbies[best.key] = best
						end
						break
					end
				end
			end
			if best and t < best.startsAt then
				joinLobby(player, best)
				if best.persistent and #best.members == 0 then
					lobbies[best.key] = nil
				end
			end
		end
	end

	for key, lobby in lobbies do
		if t >= lobby.startsAt then
			if #lobby.members > 0 then
				startRace(lobby)
			else
				lobbies[key] = nil
			end
		end
	end
end

---------------------------------------------------------------------------
-- Challenges: race anyone nearby to a landmark across the city
---------------------------------------------------------------------------

local function pickDestination(from: Vector3): WorldMap.Place
	local options, farthest, farthestDist = {}, nil, -1
	for _, place in WorldMap.Places do
		local d = flatDist(from, flat(place.pos))
		if d >= 500 and d <= 1600 then
			table.insert(options, place)
		end
		if d > farthestDist then
			farthest, farthestDist = place, d
		end
	end
	if #options > 0 then
		return options[math.random(1, #options)]
	end
	return farthest
end

local function canRace(player: Player): boolean
	return GarageService.isDriving(player) and not playerRace[player] and not playerLobby[player]
end

local function onChallenge(player: Player, targetUserId: any)
	local target = Players:GetPlayerByUserId(tonumber(targetUserId) or 0)
	if not target or target == player then
		return
	end
	if not canRace(player) or not canRace(target) then
		Net.Notify:FireClient(player, "Both drivers need to be in their cars and not racing.", "error")
		return
	end
	local a, b = GarageService.position(player), GarageService.position(target)
	if not a or not b or flatDist(a, b) > CHALLENGE_RANGE then
		Net.Notify:FireClient(player, "Pull up closer to challenge them.", "error")
		return
	end
	local dest = pickDestination((a + b) / 2)
	pendingChallenges[target] = { from = player, expires = now() + CHALLENGE_TIMEOUT, dest = dest }
	Net.ChallengeReceived:FireClient(target, player.UserId, player.DisplayName, dest.name)
	Net.Notify:FireClient(player, `Challenge sent to {target.DisplayName}.`, "info")
end

local function onChallengeReply(target: Player, fromUserId: any, accepted: any)
	local pending = pendingChallenges[target]
	pendingChallenges[target] = nil
	if not pending or pending.from.UserId ~= tonumber(fromUserId) or now() > pending.expires then
		return
	end
	local challenger = pending.from
	if not accepted then
		Net.Notify:FireClient(challenger, `{target.DisplayName} passed on your challenge.`, "info")
		return
	end
	if not canRace(challenger) or not canRace(target) then
		Net.Notify:FireClient(target, "The challenge fell through.", "error")
		return
	end
	local dest = pending.dest
	local lobby: Lobby = {
		key = `challenge:{challenger.UserId}:{target.UserId}:{now()}`,
		name = `Race to {dest.name}`,
		kind = "challenge",
		payoutKind = "sprint",
		district = WorldMap.districtAt(dest.pos),
		zoneRadius = 0,
		members = {},
		startsAt = now(),
		route = { dest.pos },
		laps = 1,
		persistent = false,
	}
	for _, p in { challenger, target } do
		table.insert(lobby.members, p)
		Net.Notify:FireClient(p, `Race to {dest.name}! Any route you like.`, "race")
	end
	startRace(lobby)
end

---------------------------------------------------------------------------
-- Start zones and leaderboard signs
---------------------------------------------------------------------------

local function buildEventMarkers()
	local folder = Instance.new("Folder")
	folder.Name = "EventStarts"
	for id, ev in WorldMap.Events do
		local disc = Instance.new("Part")
		disc.Name = `Start_{id}`
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.2, ZONE_RADIUS * 2, ZONE_RADIUS * 2)
		disc.CFrame = CFrame.new(ev.start.x, 0.35, ev.start.z) * CFrame.Angles(0, 0, math.rad(90))
		disc.Anchored = true
		disc.CanCollide = false
		disc.Material = Enum.Material.Neon
		disc.Color = Color3.fromRGB(255, 200, 40)
		disc.Transparency = 0.6
		disc.Parent = folder

		-- Local records posted right at the spot.
		local dir = Vector3.new(ev.heading.x, 0, ev.heading.z).Unit
		local side = dir:Cross(Vector3.yAxis)
		local signPos = Vector3.new(ev.start.x, 9, ev.start.z) + side * (ZONE_RADIUS + 6)
		local sign = Instance.new("Part")
		sign.Name = `Board_{id}`
		sign.Size = Vector3.new(16, 12, 0.6)
		sign.CFrame = CFrame.lookAt(signPos, signPos - side)
		sign.Anchored = true
		sign.Color = Color3.fromRGB(20, 20, 26)
		sign.Parent = folder

		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.Parent = sign
		local title = Instance.new("TextLabel")
		title.Size = UDim2.fromScale(1, 0.22)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(255, 200, 40)
		title.Text = `{ev.name} records`
		title.Parent = gui
		local body = Instance.new("TextLabel")
		body.Position = UDim2.fromScale(0.05, 0.25)
		body.Size = UDim2.fromScale(0.9, 0.7)
		body.BackgroundTransparency = 1
		body.Font = Enum.Font.GothamMedium
		body.TextScaled = true
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.TextColor3 = Color3.new(1, 1, 1)
		body.Parent = gui
		boardGuis[`event:{id}`] = body
		task.spawn(updateBoardGui, `event:{id}`)
	end
	folder.Parent = Workspace:WaitForChild("World")
end

function RaceService.isRacing(player: Player): boolean
	return playerRace[player] ~= nil
end

function RaceService.start()
	buildEventMarkers()
	Net.Challenge.OnServerEvent:Connect(onChallenge)
	Net.ChallengeReply.OnServerEvent:Connect(onChallengeReply)

	Players.PlayerRemoving:Connect(function(player)
		leaveLobby(player)
		pendingChallenges[player] = nil
		rejectedUntil[player] = nil
		local active = playerRace[player]
		if active then
			RaceLogic.removeRacer(active.race, player.UserId)
			playerRace[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(stepRaces)
			if not ok then
				warn("[RaceService] race step failed:", err)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(stepLobbies)
			if not ok then
				warn("[RaceService] lobby step failed:", err)
			end
		end
	end)
end

return RaceService
