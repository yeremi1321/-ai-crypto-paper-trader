-- The round loop:
--   lobby → (someone readies up) → ready countdown → map voting (20s)
--   → race → results → back to the lobby
--
-- Players explore the Kart Carnival freely. Only players who ready up race
-- and vote; everyone else can keep practising or watch. Late joiners spawn in
-- the lobby and can ready up for the next race. Empty grid slots are filled
-- with CPU drivers, so one player can race alone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local KartBodies = require(Shared.KartBodies)
local Karts = require(Shared.Karts)
local PlayerData = require(Shared.PlayerData)
local Rewards = require(Shared.Rewards)
local Track = require(Shared.Track)
local LobbyLayout = require(Shared.LobbyLayout)
local RaceRules = require(Shared.RaceRules)
local Tracks = require(Shared.Tracks)
local Voting = require(Shared.Voting)

local DataService = require(script.Parent.DataService)
local LobbyBuilder = require(script.Parent.LobbyBuilder)
local Net = require(script.Parent.Net)
local PracticeService = require(script.Parent.PracticeService)
local RaceService = require(script.Parent.RaceService)

local RoundService = {}

local READY_WAIT = 10 -- seconds after the first ready-up before voting opens
local RESULTS_TIME = 10
local TICK = 0.25

type Choice = { ready: boolean }

local phase: "lobby" | "voting" | "racing" | "results" = "lobby"
local deadline: number? = nil
local choices: { [Player]: Choice } = {}
local options: { string } = {}
local votes: { [number]: string } = {} -- UserId -> track id
local voters: { [Player]: boolean } = {}
local lastTrack: string? = nil
local lastResults: { any } = {}
local winner: string? = nil
local handles: LobbyBuilder.Handles
local dirty = true

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function choiceOf(player: Player): Choice
	local c = choices[player]
	if not c then
		c = { ready = false }
		choices[player] = c
	end
	return c
end

-- The player's equipped kart class and look (from their saved data).
local function kartOf(player: Player): (string, any)
	local data = DataService.get(player)
	if not data then
		return Karts.Default, KartBodies.sanitize(nil)
	end
	return data.equipped.kart, PlayerData.look(data)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

---------------------------------------------------------------------------
-- State for clients and signs
---------------------------------------------------------------------------
local function optionInfo(id: string)
	local def = Tracks.get(id)
	local voterIds = Voting.votersFor(votes, id)
	return {
		id = id,
		name = def.name,
		icon = def.icon or "🏁",
		difficulty = def.difficulty or "Medium",
		feature = def.feature or "",
		theme = def.theme,
		votes = #voterIds,
		voters = voterIds,
	}
end

local function roundState()
	local players = {}
	for player, c in choices do
		if player.Parent then
			table.insert(players, {
				userId = player.UserId,
				name = player.DisplayName,
				ready = c.ready,
				racing = RaceService.isRacing(player),
				voter = voters[player] == true,
			})
		end
	end
	local opts = {}
	for _, id in options do
		table.insert(opts, optionInfo(id))
	end
	return {
		phase = phase,
		deadline = deadline,
		players = players,
		options = opts,
		winner = winner,
		spectate = RaceService.spectatorInfo(),
		lastResults = lastResults,
	}
end

local function countReady(): (number, number)
	local total, ready = 0, 0
	for player, c in choices do
		if player.Parent then
			total += 1
			if c.ready and not RaceService.isRacing(player) then
				ready += 1
			end
		end
	end
	return total, ready
end

local function secondsLeft(): number
	return if deadline then math.max(0, math.ceil(deadline - now())) else 0
end

local function updateSigns()
	local _, ready = countReady()
	if phase == "lobby" then
		if deadline then
			handles.setStatus("GET READY!", `{ready} racer{if ready == 1 then "" else "s"} ready\nVoting opens in {secondsLeft()}s`)
		else
			handles.setStatus("KART CARNIVAL", "Step under the READY arch\n(or press READY) to join the next race")
		end
	elseif phase == "voting" then
		handles.setStatus("VOTE FOR A TRACK!", `Stand on a pad or use the menu\n{secondsLeft()}s left`)
	elseif phase == "racing" then
		local info = RaceService.spectatorInfo()
		handles.setStatus("RACE IN PROGRESS", if info then `{info.trackName}\nReady up to join the next one` else "")
	elseif phase == "results" then
		handles.setStatus("RESULTS", `Back to the lobby in {secondsLeft()}s`)
	end

	for i = 1, #LobbyLayout.VotePads do
		local id = options[i]
		handles.setVoteOption(i, if id and (phase == "voting" or phase == "racing") then optionInfo(id) else nil)
	end

	local info = RaceService.spectatorInfo()
	if info then
		local lines = {}
		for place, row in info.rows do
			if place > 8 then
				break
			end
			table.insert(lines, `{place}. {row.name}{if row.finished then " ✓" else ""}`)
		end
		handles.setSpectator(`LIVE: {info.trackName}`, table.concat(lines, "\n"))
	else
		handles.setSpectator("LIVE RACE", "No race running.\nReady up to start one!")
	end
end

local function broadcast()
	dirty = false
	Net.Round:FireAllClients(roundState())
	updateSigns()
end

local function refreshDisplays()
	local slot = 0
	for player in choices do
		if player.Parent then
			slot += 1
			if slot <= #LobbyLayout.KartDisplays then
				local kartId, look = kartOf(player)
				handles.setKartDisplay(slot, player.DisplayName, kartId, look)
			end
		end
	end
	for s = slot + 1, #LobbyLayout.KartDisplays do
		handles.setKartDisplay(s, nil)
	end
end

---------------------------------------------------------------------------
-- Phases
---------------------------------------------------------------------------
local function toLobby()
	phase = "lobby"
	deadline = nil
	options = {}
	votes = {}
	voters = {}
	winner = nil
	dirty = true
end

local function startVoting()
	phase = "voting"
	deadline = now() + Voting.VoteSeconds
	votes = {}
	voters = {}
	options = Voting.pickOptions(Tracks.VotePool, Voting.OptionCount, math.random, lastTrack)
	for player, c in choices do
		if c.ready and player.Parent then
			voters[player] = true
		end
	end
	for player in voters do
		Net.Notify:FireClient(player, "Vote for a track!")
	end
	dirty = true
end

local function onRaceEnded(rows: { any }, trackId: string)
	phase = "results"
	deadline = now() + RESULTS_TIME
	lastTrack = trackId
	lastResults = {}
	for i, row in rows do
		if i <= 3 then
			table.insert(lastResults, { name = row.name, kartId = row.kartId, look = row.look })
		end
	end
	handles.setPodium(lastResults)

	local def = Tracks.get(trackId)
	local trackLength = Track.build(def).length
	local out = {}
	local statRows = {}
	for _, row in rows do
		table.insert(out, {
			place = row.place,
			name = row.name,
			isCpu = row.isCpu,
			userId = row.userId,
			time = row.time,
			finished = row.finished,
			bestLap = row.bestLap,
		})
		table.insert(statRows, {
			id = row.id,
			name = row.name,
			place = row.place,
			finished = row.finished,
			time = row.time,
			bestLap = row.bestLap,
			worstPlace = row.worstPlace,
			hitsTaken = row.hitsTaken,
			shortcutsTaken = row.shortcutsTaken,
			jumps = row.jumps,
			isCpu = row.isCpu,
		})
	end

	-- Awards for everyone to see; coins only go to players.
	local awards = Rewards.awards(statRows)
	local awardLines = {}
	local nameOf = {}
	for _, r in statRows do
		nameOf[r.id] = r.name
	end
	for _, a in awards do
		table.insert(awardLines, { icon = a.icon, name = a.name, winner = nameOf[a.winner] })
	end

	for i, row in rows do
		local player = row.userId and Players:GetPlayerByUserId(row.userId)
		if player then
			local data = DataService.get(player)
			local mine = nil
			if data then
				local myAwards = {}
				for _, a in awards do
					if a.winner == row.id then
						table.insert(myAwards, a.id)
					end
				end
				mine = PlayerData.applyRace(data, trackId, trackLength, #Tracks.VotePool, statRows[i], myAwards)
				DataService.markDirty(player)
				DataService.push(player)
			end
			Net.Results:FireClient(player, { trackName = def.name, rows = out, awards = awardLines, me = mine })
		end
	end
	-- Everyone else in the lobby sees the results too (no personal rewards).
	for _, player in Players:GetPlayers() do
		local raced = false
		for _, row in rows do
			if row.userId == player.UserId then
				raced = true
			end
		end
		if not raced then
			Net.Results:FireClient(player, { trackName = def.name, rows = out, awards = awardLines })
		end
	end

	-- Racers go back to the lobby; they ready up again for the next race.
	-- The top three players stand on the podium and celebrate.
	for _, row in rows do
		if row.userId then
			local player = Players:GetPlayerByUserId(row.userId)
			if player then
				choiceOf(player).ready = false
				task.defer(function()
					if not player.Parent then
						return
					end
					player:LoadCharacter()
					if row.place <= 3 then
						local character = player.Character or player.CharacterAdded:Wait()
						task.wait(0.3)
						handles.celebrate(row.place, character)
					end
				end)
			end
		end
	end
	dirty = true
end

local function startRace()
	-- Highest vote wins; ties are broken at random.
	local trackId = Voting.winner(options, votes, math.random)
	winner = trackId
	local entrants = {}
	for player in voters do
		if player.Parent then
			local kartId, look = kartOf(player)
			PracticeService.stop(player)
			table.insert(entrants, {
				id = `u{player.UserId}`,
				name = player.DisplayName,
				isCpu = false,
				player = player,
				kartId = kartId,
				look = look,
				profile = { lane = 0, skill = 1 },
			})
		end
	end
	if #entrants == 0 then
		toLobby()
		return
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
			profile = { lane = ((cpuIndex % 3) - 1) * 0.6, skill = 0.45 + (cpuIndex % 4) * 0.15 },
		})
	end
	phase = "racing"
	deadline = nil
	-- Voters are now racers; their ready flag is spent.
	for player in voters do
		choiceOf(player).ready = false
	end
	voters = {}
	dirty = true
	local ok, err = pcall(RaceService.startRace, trackId, entrants, onRaceEnded)
	if not ok then
		warn("[RoundService] could not start the race:", err)
		RaceService.abort()
		toLobby()
	end
end

local function step()
	local t = now()
	local _, ready = countReady()

	if phase == "lobby" then
		if ready == 0 then
			if deadline then
				deadline = nil
				dirty = true
			end
		else
			if not deadline then
				deadline = t + READY_WAIT
				dirty = true
			end
			-- Everyone in the server ready? No need to wait.
			local total = 0
			for player in choices do
				if player.Parent and not RaceService.isRacing(player) then
					total += 1
				end
			end
			if t >= (deadline :: number) or ready == total then
				startVoting()
			end
		end
	elseif phase == "voting" then
		-- Standing on a vote pad counts as a vote.
		for player in voters do
			local root = rootOf(player)
			if root then
				local pad = LobbyLayout.padAt(root.Position.X, root.Position.Z)
				if pad and options[pad] and votes[player.UserId] ~= options[pad] then
					votes[player.UserId] = options[pad]
					dirty = true
				end
			end
		end
		local anyVoter = next(voters) ~= nil
		if not anyVoter then
			toLobby()
		elseif t >= (deadline :: number) then
			startRace()
		end
	elseif phase == "racing" then
		if not RaceService.isRunning() and phase == "racing" then
			-- The race ended without results (everyone left).
			toLobby()
		end
	elseif phase == "results" then
		if t >= (deadline :: number) then
			toLobby()
		end
	end

	-- Hidden golden tokens in the lobby (saved, paid once each).
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local data = DataService.get(player)
		if root and data then
			for _, token in handles.collectibles do
				local id = tostring(token:GetAttribute("TokenId"))
				if not data.tokens[id] and (token.Position - root.Position).Magnitude < 7 then
					local coins, all = PlayerData.foundToken(data, id, #handles.collectibles)
					local count = 0
					for _ in data.tokens do
						count += 1
					end
					Net.Notify:FireClient(player, `Golden token! +{coins} 🪙 ({count}/{#handles.collectibles})` .. (if all then " All found!" else ""))
					DataService.markDirty(player)
					DataService.push(player)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Remotes and setup
---------------------------------------------------------------------------
local function setReady(player: Player, isReady: boolean)
	if RaceService.isRacing(player) then
		return
	end
	local c = choiceOf(player)
	if c.ready == isReady then
		return
	end
	c.ready = isReady
	if phase == "voting" then
		if isReady then
			voters[player] = true
		else
			voters[player] = nil
			votes[player.UserId] = nil
		end
	end
	Net.Notify:FireClient(player, if isReady then "You're in the next race!" else "You left the next race.")
	dirty = true
end

function RoundService.start()
	handles = LobbyBuilder.build()
	PracticeService.init()

	local function onPlayer(player: Player)
		choiceOf(player)
		dirty = true
		task.spawn(function()
			DataService.waitFor(player)
			refreshDisplays()
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		choices[player] = nil
		voters[player] = nil
		votes[player.UserId] = nil
		dirty = true
		task.defer(refreshDisplays)
	end)

	Net.Ready.OnServerEvent:Connect(function(player, isReady)
		setReady(player, isReady == true)
	end)
	handles.readyPrompt.Triggered:Connect(function(player)
		setReady(player, not choiceOf(player).ready)
	end)
	Net.Vote.OnServerEvent:Connect(function(player, trackId)
		if phase == "voting" and voters[player] and table.find(options, trackId) then
			votes[player.UserId] = trackId
			dirty = true
		end
	end)
	-- Garage: everything is checked here; the client only asks.
	local textCooldown: { [Player]: number } = {}
	Net.GarageAction.OnServerEvent:Connect(function(player, action, kind, value)
		local data = DataService.get(player)
		if not data or type(action) ~= "string" or type(kind) ~= "string" then
			return
		end
		local ok, err = false, nil
		if action == "buy" then
			ok, err = PlayerData.buy(data, kind, tostring(value))
			if ok then
				ok, err = PlayerData.equip(data, kind, tostring(value))
			end
		elseif action == "equip" then
			if RaceService.isRacing(player) then
				return
			end
			ok, err = PlayerData.equip(data, kind, value)
		elseif action == "text" and (kind == "plate" or kind == "name") then
			if os.clock() - (textCooldown[player] or 0) < 2 then
				return
			end
			textCooldown[player] = os.clock()
			local maxLength = if kind == "plate" then Cosmetics.PlateMaxLength else Cosmetics.NameMaxLength
			local clean = Cosmetics.cleanText(value, maxLength)
			data.equipped[kind] = DataService.filter(player, clean)
			ok = true
		elseif action == "setting" then
			ok = PlayerData.setSetting(data, kind, value == true)
		end
		if ok then
			DataService.markDirty(player)
			refreshDisplays()
		elseif err then
			Net.Notify:FireClient(player, err)
		end
		DataService.push(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		textCooldown[player] = nil
	end)

	-- Horns: anyone can honk; everyone nearby sees (and hears) it.
	local honkCooldown: { [Player]: number } = {}
	Net.HonkRequest.OnServerEvent:Connect(function(player)
		if os.clock() - (honkCooldown[player] or 0) < 1.5 then
			return
		end
		honkCooldown[player] = os.clock()
		local data = DataService.get(player)
		local horn = Cosmetics.find("horn", data and data.equipped.horn or "beep")
		Net.Honk:FireAllClients(player.DisplayName, horn and horn.id or "beep", player.UserId)
	end)
	Net.UseItem.OnServerEvent:Connect(function(player, aimBack)
		RaceService.useItem(player, aimBack == true)
	end)
	Net.Respawn.OnServerEvent:Connect(RaceService.requestRespawn)

	handles.garagePrompt.Triggered:Connect(function(player)
		Net.OpenGarage:FireClient(player)
	end)
	handles.spectatePrompt.Triggered:Connect(function(player)
		if RaceService.isRunning() and not RaceService.isRacing(player) then
			Net.Spectate:FireClient(player)
		else
			Net.Notify:FireClient(player, "No race to watch right now.")
		end
	end)
	handles.practicePrompt.Triggered:Connect(function(player)
		if RaceService.isRacing(player) then
			return
		end
		local kartId, look = kartOf(player)
		PracticeService.start(player, kartId, look)
	end)

	task.spawn(function()
		local lastSecond = -1
		while true do
			task.wait(TICK)
			local ok, err = pcall(step)
			if not ok then
				warn("[RoundService]", err)
			end
			-- Rebroadcast on changes, and once a second so countdowns tick on signs.
			local second = math.floor(now())
			if dirty or second ~= lastSecond then
				lastSecond = second
				local ok2, err2 = pcall(broadcast)
				if not ok2 then
					warn("[RoundService] broadcast failed:", err2)
				end
			end
		end
	end)
end

return RoundService
