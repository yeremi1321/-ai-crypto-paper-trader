-- Rising Escape Obby — server
-- Put this in ServerScriptService as a Script named EscapeObbyServer.
-- Everything (remotes, lobby spawn, courses) is created by this script.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

----------------------------------------------------------------------
-- Tuning
----------------------------------------------------------------------
local MIN_PARTY = 1
local MAX_PARTY = 6
local STAGE_COUNT = 12 -- stage 12 is the finish pad, so a run is 12 jumps
local CHECKPOINT_STAGES = { [4] = true, [8] = true }

local COUNTDOWN_SECONDS = 3
local ROUND_SECONDS = 100
local LAVA_GRACE_SECONDS = 4 -- lava waits this long after GO
local LAVA_REACHES_FINISH_AT = 96 -- seconds after GO when lava covers the finish
local RESPAWN_DELAY = 2
local RESULTS_SECONDS = 8
local TELEPORT_GRACE = 1.5 -- ignore lava checks right after a teleport

-- Default Roblox movement. Course gaps below are sized for these values.
local WALK_SPEED = 16
local JUMP_POWER = 50

-- Gaps are edge to edge. At speed 16 / power 50 a flat jump covers ~8 studs,
-- and ~7 studs when landing 2.5 studs higher, so these leave a safe margin.
local MIN_GAP, MAX_GAP = 3, 5.5
local MIN_RISE, MAX_RISE = 0.5, 2.5
local MAX_SIDE_STEP = 3.5
local MAX_SIDE_OFFSET = 10

local COURSE_ORIGIN = Vector3.new(-70, 80, 160)
local COURSE_SPACING = 90 -- distance between parallel party courses

-- Look. Set either to false for the plain look.
local VOLCANO_COURSE = true -- rock platforms, magma glow, canyon walls, embers
local VOLCANO_WORLD = true -- smoky orange sky, dark lobby floor, background volcano

local ROCK_COLORS = {
	Color3.fromRGB(58, 50, 48),
	Color3.fromRGB(74, 60, 54),
	Color3.fromRGB(48, 44, 46),
	Color3.fromRGB(88, 70, 60),
}
local MAGMA_COLOR = Color3.fromRGB(255, 110, 30)
local LAVA_COLOR = Color3.fromRGB(255, 80, 20)

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("RisingEscapeRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "RisingEscapeRemotes"
	remotes.Parent = ReplicatedStorage
end

local function getRemote(name)
	local remote = remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
	end
	return remote
end

local actionEvent = getRemote("Action") -- client -> server
local stateEvent = getRemote("State") -- server -> client

----------------------------------------------------------------------
-- World setup
----------------------------------------------------------------------
-- We load characters ourselves so a dead player respawns exactly once,
-- at the right place, instead of racing Roblox's automatic respawn.
Players.CharacterAutoLoads = false

local coursesFolder = Workspace:FindFirstChild("RisingEscapeCourses")
if not coursesFolder then
	coursesFolder = Instance.new("Folder")
	coursesFolder.Name = "RisingEscapeCourses"
	coursesFolder.Parent = Workspace
end

local function findLobbySpawn()
	for _, item in ipairs(Workspace:GetDescendants()) do
		if item:IsA("SpawnLocation") and not item:IsDescendantOf(coursesFolder) then
			return item
		end
	end
	if not Workspace:FindFirstChild("Baseplate") then
		local floor = Instance.new("Part")
		floor.Name = "LobbyFloor"
		floor.Anchored = true
		floor.Size = Vector3.new(120, 2, 120)
		floor.Position = Vector3.new(0, -1, 0)
		floor.Material = Enum.Material.Slate
		floor.Parent = Workspace
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, 0)
	spawn.Duration = 0
	spawn.Parent = Workspace
	return spawn
end

local lobbySpawn = findLobbySpawn()
local rng = Random.new()

local function lobbyCFrame()
	local base = lobbySpawn.Position + Vector3.new(0, lobbySpawn.Size.Y / 2 + 3.5, 0)
	return CFrame.new(base + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)))
end

-- Volcano world: only changes things while the game runs, never your saved place.
local function setupVolcanoWorld()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 17.8
	Lighting.Ambient = Color3.fromRGB(70, 40, 35)
	Lighting.OutdoorAmbient = Color3.fromRGB(130, 80, 65)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 140, 90)

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(200, 120, 90)
	atmosphere.Decay = Color3.fromRGB(95, 40, 30)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.8

	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Color = Color3.fromRGB(45, 36, 34)
		baseplate.Material = Enum.Material.Basalt
		for _, child in ipairs(baseplate:GetChildren()) do
			if child:IsA("Texture") then
				child.Transparency = 1
			end
		end
	end

	if Workspace:FindFirstChild("VolcanoBackdrop") then
		return
	end
	-- A big stepped volcano behind the start of the courses.
	local model = Instance.new("Model")
	model.Name = "VolcanoBackdrop"
	local base = Vector3.new(-290, 0, 230)
	local layers, layerHeight = 10, 14
	local bottomRadius, topRadius = 150, 45
	local peakY = layers * layerHeight
	for i = 0, layers - 1 do
		local radius = bottomRadius + (topRadius - bottomRadius) * (i / (layers - 1))
		local layer = Instance.new("Part")
		layer.Name = "Slope"
		layer.Shape = Enum.PartType.Cylinder
		layer.Anchored = true
		layer.Size = Vector3.new(layerHeight, radius * 2, radius * 2)
		layer.CFrame = CFrame.new(base.X, base.Y + i * layerHeight + layerHeight / 2, base.Z) * CFrame.Angles(0, 0, math.pi / 2)
		layer.Color = ROCK_COLORS[(i % #ROCK_COLORS) + 1]
		layer.Material = Enum.Material.Basalt
		layer.Parent = model
	end
	local crater = Instance.new("Part")
	crater.Name = "CraterLava"
	crater.Shape = Enum.PartType.Cylinder
	crater.Anchored = true
	crater.Size = Vector3.new(1, topRadius * 1.6, topRadius * 1.6)
	crater.CFrame = CFrame.new(base.X, peakY + 0.4, base.Z) * CFrame.Angles(0, 0, math.pi / 2)
	crater.Color = LAVA_COLOR
	crater.Material = Enum.Material.Neon
	crater.CanCollide = false
	crater.Parent = model

	local smoke = Instance.new("ParticleEmitter")
	smoke.EmissionDirection = Enum.NormalId.Right -- the cylinder's top face after rotating
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 80, 80), Color3.fromRGB(40, 35, 35))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 20),
		NumberSequenceKeypoint.new(1, 45),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(8, 12)
	smoke.Rate = 4
	smoke.Speed = NumberRange.new(8, 14)
	smoke.Parent = crater

	-- Lava streams running down the slopes.
	for i = 1, 5 do
		local angle = (i / 5) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local startPoint = base + dir * (topRadius + 2) + Vector3.new(0, peakY, 0)
		local endPoint = base + dir * (bottomRadius + 2) + Vector3.new(0, 1, 0)
		local stream = Instance.new("Part")
		stream.Name = "LavaStream"
		stream.Anchored = true
		stream.Size = Vector3.new(rng:NextNumber(5, 9), 1, (endPoint - startPoint).Magnitude)
		stream.CFrame = CFrame.lookAt((startPoint + endPoint) / 2, endPoint)
		stream.Color = MAGMA_COLOR
		stream.Material = Enum.Material.Neon
		stream.CanCollide = false
		stream.Parent = model
	end
	model.Parent = Workspace
end

if VOLCANO_WORLD then
	setupVolcanoWorld()
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local parties = {} -- [partyId] = party
local playerParty = {} -- [Player] = party
local usedSlots = {} -- [slotIndex] = true
local lastActionAt = {} -- [Player] = os.clock()
local respawnTokens = {} -- [Player] = number
local nextPartyId = 0
local dirty = true

local function now()
	return Workspace:GetServerTimeNow()
end

local function markDirty()
	dirty = true
end

local function notify(player, text)
	if player and player.Parent == Players then
		stateEvent:FireClient(player, "notice", text)
	end
end

local function notifyParty(party, text)
	for _, member in ipairs(party.members) do
		notify(member, text)
	end
end

local function getHumanoid(character)
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(character)
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function playerFromHit(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(model)
	if not player then
		return nil
	end
	local humanoid = getHumanoid(model)
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return player
end

-- Moves a character safely. Yields (streaming), so call from task.spawn.
local function teleportCharacter(player, cframe)
	local character = player.Character
	local root = getRoot(character)
	if not root then
		return false
	end
	pcall(function()
		player:RequestStreamAroundAsync(cframe.Position, 3)
	end)
	if player.Character ~= character or not character.Parent or not root.Parent then
		return false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(cframe)
	return true
end

----------------------------------------------------------------------
-- Course building
----------------------------------------------------------------------
local addGlowRim, addEmbers, buildCanyon -- defined below makePart

local function makePart(parent, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addLabel(part, text, color)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 36)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 120
	billboard.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard
end

local function noCollide(part)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

-- Thin glowing slab just under a platform, so its edges look red-hot.
-- It never collides, so it doesn't change the jumps.
addGlowRim = function(folder, pad)
	local rim = makePart(
		folder,
		pad.Name .. "Glow",
		Vector3.new(pad.Size.X + 0.6, 0.5, pad.Size.Z + 0.6),
		pad.CFrame * CFrame.new(0, -pad.Size.Y / 2 - 0.1, 0),
		MAGMA_COLOR,
		Enum.Material.Neon
	)
	noCollide(rim)
end

-- Sparks drifting up from the lava surface.
addEmbers = function(lava)
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 210, 90), Color3.fromRGB(255, 60, 20))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Lifetime = NumberRange.new(1.5, 3)
	embers.Rate = 25
	embers.Speed = NumberRange.new(4, 9)
	embers.SpreadAngle = Vector2.new(20, 20)
	embers.Parent = lava
end

-- Tall rock walls on both sides of the course with glowing lavafalls.
-- They sit well outside jumping range of every platform.
buildCanyon = function(folder, minX, maxX, centerZ, bottomY, topY)
	local length = maxX - minX
	local height = topY - bottomY
	local midX = (minX + maxX) / 2
	local midY = (bottomY + topY) / 2
	for _, side in ipairs({ -1, 1 }) do
		local z = centerZ + side * (MAX_SIDE_OFFSET + 18)
		makePart(folder, "CanyonWall", Vector3.new(length, height, 4), CFrame.new(midX, midY, z), ROCK_COLORS[1], Enum.Material.Basalt)
		for i = 1, 3 do
			local x = minX + length * i / 4 + rng:NextNumber(-8, 8)
			local fall = makePart(
				folder,
				"Lavafall",
				Vector3.new(rng:NextNumber(3, 6), height, 0.4),
				CFrame.new(x, midY, z - side * 2.2),
				MAGMA_COLOR,
				Enum.Material.Neon
			)
			noCollide(fall)
		end
	end
end

local function claimSlot()
	local slot = 0
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	return slot
end

local function facingForward(position)
	return CFrame.lookAt(position, position + Vector3.xAxis)
end

-- Builds a fresh random course. Returns the round table (without players).
local function buildCourse(party)
	local slot = claimSlot()
	local origin = COURSE_ORIGIN + Vector3.new(0, 0, slot * COURSE_SPACING)
	local folder = Instance.new("Folder")
	folder.Name = "Course_" .. party.id

	local round = {
		slot = slot,
		folder = folder,
		pads = {},
		checkpoints = {},
		connections = {},
		players = {},
		ended = false,
	}

	-- Start pad with six spawn spots and a gate that opens on GO.
	local startSize = Vector3.new(14, 1, 14)
	local startPad = makePart(folder, "Start", startSize, CFrame.new(origin), Color3.fromRGB(120, 120, 130))
	if VOLCANO_COURSE then
		startPad.Color = ROCK_COLORS[4]
		startPad.Material = Enum.Material.Basalt
		addGlowRim(folder, startPad)
	end
	local startTop = origin.Y + startSize.Y / 2
	round.startTop = startTop
	round.checkpoints[0] = { cframe = facingForward(Vector3.new(origin.X - 3, startTop + 4, origin.Z)), top = startTop }
	round.startSpots = {}
	for i = 0, 5 do
		local col = i % 3
		local row = math.floor(i / 3)
		local spot = Vector3.new(origin.X - 4 + row * 4, startTop + 4, origin.Z - 4 + col * 4)
		table.insert(round.startSpots, facingForward(spot))
	end
	addLabel(startPad, "RISING ESCAPE", Color3.fromRGB(255, 170, 60))

	local gate = makePart(
		folder,
		"Gate",
		Vector3.new(1, 14, startSize.Z),
		CFrame.new(origin.X + startSize.X / 2 + 0.5, startTop + 7, origin.Z),
		Color3.fromRGB(80, 170, 255),
		Enum.Material.ForceField
	)
	gate.Transparency = 0.4
	if VOLCANO_COURSE then
		gate.Color = MAGMA_COLOR
	end
	round.gate = gate

	-- Stages 1..12. The path wanders sideways and climbs; new every round.
	local frontX = origin.X + startSize.X / 2
	local sideOffset = 0
	local top = startTop
	for stage = 1, STAGE_COUNT do
		local isFinish = stage == STAGE_COUNT
		local isCheckpoint = CHECKPOINT_STAGES[stage] == true
		local size
		if isFinish then
			size = Vector3.new(12, 1, 12)
		elseif isCheckpoint then
			size = Vector3.new(10, 1, 10)
		else
			size = Vector3.new(rng:NextNumber(6, 8), 1, rng:NextNumber(6, 8))
		end

		local gap = rng:NextNumber(MIN_GAP, MAX_GAP)
		top += rng:NextNumber(MIN_RISE, MAX_RISE)
		sideOffset = math.clamp(sideOffset + rng:NextNumber(-MAX_SIDE_STEP, MAX_SIDE_STEP), -MAX_SIDE_OFFSET, MAX_SIDE_OFFSET)
		local centerX = frontX + gap + size.X / 2
		local center = Vector3.new(centerX, top - size.Y / 2, origin.Z + sideOffset)
		frontX = centerX + size.X / 2

		local color, material, name
		if isFinish then
			color, material, name = Color3.fromRGB(255, 200, 40), Enum.Material.Neon, "Finish"
		elseif isCheckpoint then
			color, material, name = Color3.fromRGB(60, 220, 90), Enum.Material.Neon, "Checkpoint" .. stage
		elseif VOLCANO_COURSE then
			color, material, name = ROCK_COLORS[rng:NextInteger(1, #ROCK_COLORS)], Enum.Material.Basalt, "Stage" .. stage
		else
			color = Color3.fromHSV((stage * 0.08) % 1, 0.45, 0.95)
			name = "Stage" .. stage
		end
		local pad = makePart(folder, name, size, CFrame.new(center), color, material)
		if VOLCANO_COURSE and not isFinish and not isCheckpoint then
			addGlowRim(folder, pad)
		end
		pad:SetAttribute("Stage", stage)
		round.pads[stage] = pad

		if isFinish then
			round.finishPad = pad
			round.finishTop = top
			addLabel(pad, "FINISH", Color3.fromRGB(255, 220, 80))
		elseif isCheckpoint then
			round.checkpoints[stage] = { cframe = facingForward(Vector3.new(centerX, top + 4, center.Z)), top = top }
			addLabel(pad, "CHECKPOINT", Color3.fromRGB(120, 255, 140))
		end
	end

	-- Lava: a tall block under the whole course. Its top surface rises.
	local minX = origin.X - startSize.X / 2 - 12
	local maxX = frontX + 12
	local lavaHeight = 60
	round.lavaHeight = lavaHeight
	round.lavaCenterX = (minX + maxX) / 2
	round.lavaCenterZ = origin.Z
	round.bounds = {
		minX = minX,
		maxX = maxX,
		minZ = origin.Z - MAX_SIDE_OFFSET - 20,
		maxZ = origin.Z + MAX_SIDE_OFFSET + 20,
	}
	round.lavaStartTop = startTop - 8
	round.lavaRate = (round.finishTop - round.lavaStartTop) / (LAVA_REACHES_FINISH_AT - LAVA_GRACE_SECONDS)

	local lava = makePart(
		folder,
		"Lava",
		Vector3.new(maxX - minX, lavaHeight, round.bounds.maxZ - round.bounds.minZ),
		CFrame.new(round.lavaCenterX, round.lavaStartTop - lavaHeight / 2, round.lavaCenterZ),
		Color3.fromRGB(255, 80, 20),
		Enum.Material.Neon
	)
	lava.CanCollide = false
	lava.CanTouch = false
	lava.CanQuery = false
	lava.Transparency = 0.15
	round.lava = lava

	if VOLCANO_COURSE then
		lava.Color = LAVA_COLOR
		addEmbers(lava)
		buildCanyon(folder, minX, maxX, origin.Z, startTop - 70, startTop + 60)
	end

	folder.Parent = coursesFolder
	return round
end

local function lavaTopAt(round, t)
	if not round.goAt then
		return round.lavaStartTop
	end
	local elapsed = t - round.goAt - LAVA_GRACE_SECONDS
	if elapsed <= 0 then
		return round.lavaStartTop
	end
	return round.lavaStartTop + elapsed * round.lavaRate
end

local function destroyCourse(round)
	for _, connection in ipairs(round.connections) do
		connection:Disconnect()
	end
	table.clear(round.connections)
	if round.folder then
		round.folder:Destroy()
		round.folder = nil
	end
	if round.slot ~= nil then
		usedSlots[round.slot] = nil
		round.slot = nil
	end
end

----------------------------------------------------------------------
-- Snapshots sent to clients
----------------------------------------------------------------------
local function buildRows(round)
	local rows = {}
	for _, rp in pairs(round.players) do
		table.insert(rows, {
			name = rp.name,
			status = rp.status,
			time = rp.finishTime,
			place = rp.place,
			stage = rp.stage,
		})
	end
	table.sort(rows, function(a, b)
		local aWon = a.status == "won"
		local bWon = b.status == "won"
		if aWon ~= bWon then
			return aWon
		end
		if aWon then
			return a.time < b.time
		end
		if a.stage ~= b.stage then
			return a.stage > b.stage
		end
		return a.name < b.name
	end)
	return rows
end

local function buildSnapshot(player)
	local list = {}
	for _, party in pairs(parties) do
		table.insert(list, {
			id = party.id,
			host = party.host.DisplayName,
			count = #party.members,
			capacity = party.capacity,
			phase = party.phase,
		})
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)

	local snapshot = {
		parties = list,
		minParty = MIN_PARTY,
		maxParty = MAX_PARTY,
		stageCount = STAGE_COUNT,
	}

	local party = playerParty[player]
	if party then
		local members = {}
		for _, member in ipairs(party.members) do
			table.insert(members, { name = member.DisplayName, isHost = member == party.host })
		end
		snapshot.myParty = {
			id = party.id,
			isHost = party.host == player,
			capacity = party.capacity,
			phase = party.phase,
			members = members,
		}

		local round = party.round
		if round then
			local rp = round.players[player]
			snapshot.round = {
				phase = party.phase,
				goAt = round.goAt,
				endsAt = round.endsAt,
				resultsEndAt = round.resultsEndAt,
				lavaStartTop = round.lavaStartTop,
				lavaRate = round.lavaRate,
				lavaStartsAt = round.goAt and (round.goAt + LAVA_GRACE_SECONDS) or nil,
				status = rp and rp.status or "spectating",
				stage = rp and rp.stage or 0,
				checkpoint = rp and rp.checkpoint or 0,
				rows = buildRows(round),
			}
		end
	end
	return snapshot
end

task.spawn(function()
	while true do
		task.wait(0.2)
		if dirty then
			dirty = false
			for _, player in ipairs(Players:GetPlayers()) do
				stateEvent:FireClient(player, "state", buildSnapshot(player))
			end
		end
	end
end)

----------------------------------------------------------------------
-- Round flow
----------------------------------------------------------------------
local endRound -- forward declaration

local function checkRoundEnd(party)
	local round = party.round
	if not round or round.ended then
		return
	end
	for _, rp in pairs(round.players) do
		if rp.status == "alive" then
			return
		end
	end
	endRound(party)
end

local function eliminate(party, player, reason)
	local round = party.round
	local rp = round and round.players[player]
	if not rp or rp.status ~= "alive" then
		return
	end
	rp.status = "eliminated"
	rp.onCourse = false
	notify(player, reason)
	markDirty()
	checkRoundEnd(party)
end

local function sendToLobby(player)
	task.spawn(function()
		teleportCharacter(player, lobbyCFrame())
	end)
end

local function finishCleanup(party, round)
	if party.round ~= round then
		return
	end
	for member, rp in pairs(round.players) do
		if rp.onCourse and member.Parent == Players and playerParty[member] == party then
			rp.onCourse = false
			sendToLobby(member)
		end
	end
	destroyCourse(round)
	party.round = nil
	party.phase = "lobby"
	markDirty()
end

endRound = function(party)
	local round = party.round
	if not round or round.ended then
		return
	end
	round.ended = true
	for _, rp in pairs(round.players) do
		if rp.status == "alive" then
			rp.status = "timeout"
		end
	end
	party.phase = "results"
	round.resultsEndAt = now() + RESULTS_SECONDS
	markDirty()
	task.delay(RESULTS_SECONDS, function()
		if parties[party.id] == party then
			finishCleanup(party, round)
		end
	end)
end

local function placeOnCourse(player, party, cframe)
	local round = party.round
	local rp = round and round.players[player]
	if not rp then
		return
	end
	rp.onCourse = false
	if teleportCharacter(player, cframe) and party.round == round and rp.status == "alive" then
		rp.onCourse = true
		rp.safeUntil = now() + TELEPORT_GRACE
	end
end

local function startRound(player)
	local party = playerParty[player]
	if not party then
		notify(player, "You are not in a party.")
		return
	end
	if party.host ~= player then
		notify(player, "Only the host can start.")
		return
	end
	if party.phase ~= "lobby" then
		notify(player, "A round is already running.")
		return
	end

	local round = buildCourse(party)
	party.round = round
	party.phase = "countdown"
	round.goAt = now() + COUNTDOWN_SECONDS
	round.endsAt = round.goAt + ROUND_SECONDS

	for index, member in ipairs(party.members) do
		round.players[member] = {
			name = member.DisplayName,
			status = "alive",
			checkpoint = 0,
			stage = 0,
			onCourse = false,
			safeUntil = 0,
		}
		local spot = round.startSpots[((index - 1) % #round.startSpots) + 1]
		local humanoid = getHumanoid(member.Character)
		if humanoid and humanoid.Health > 0 then
			task.spawn(placeOnCourse, member, party, spot)
		end
		-- Dead or missing characters are placed by onCharacterAdded.
	end

	-- Touch handlers: stage progress, checkpoints, finish.
	for stage, pad in pairs(round.pads) do
		table.insert(
			round.connections,
			pad.Touched:Connect(function(hit)
				local toucher = playerFromHit(hit)
				if not toucher or party.round ~= round or (party.phase :: string) ~= "running" then
					return
				end
				local rp = round.players[toucher]
				if not rp or rp.status ~= "alive" or not rp.onCourse then
					return
				end
				if stage > rp.stage then
					rp.stage = stage
					markDirty()
				end
				local checkpoint = round.checkpoints[stage]
				if checkpoint and stage > rp.checkpoint and lavaTopAt(round, now()) < checkpoint.top - 1 then
					rp.checkpoint = stage
					notify(toucher, "Checkpoint " .. stage .. " saved!")
					markDirty()
				end
				if pad == round.finishPad then
					rp.status = "won"
					rp.finishTime = now() - round.goAt
					round.finishers = (round.finishers or 0) + 1
					rp.place = round.finishers
					notifyParty(party, string.format("%s escaped in %.1fs!", rp.name, rp.finishTime))
					markDirty()
					checkRoundEnd(party)
				end
			end)
		)
	end

	notifyParty(party, "Get ready!")
	markDirty()
end

----------------------------------------------------------------------
-- Party actions
----------------------------------------------------------------------
local function toCapacity(value)
	if typeof(value) ~= "number" or value ~= value then
		return nil
	end
	value = math.floor(value)
	if value < MIN_PARTY or value > MAX_PARTY then
		return nil
	end
	return value
end

local function destroyParty(party)
	if party.round then
		destroyCourse(party.round)
		party.round = nil
	end
	parties[party.id] = nil
	markDirty()
end

local function createParty(player, capacityValue)
	if playerParty[player] then
		notify(player, "Leave your current party first.")
		return
	end
	local capacity = toCapacity(capacityValue)
	if not capacity then
		notify(player, "Party size must be 1 to 6.")
		return
	end
	nextPartyId += 1
	local party = {
		id = nextPartyId,
		host = player,
		capacity = capacity,
		members = { player },
		phase = "lobby" :: string, -- lobby | countdown | running | results
		round = nil,
	}
	parties[party.id] = party
	playerParty[player] = party
	markDirty()
end

local function joinParty(player, partyId)
	if playerParty[player] then
		notify(player, "Leave your current party first.")
		return
	end
	if typeof(partyId) ~= "number" then
		return
	end
	local party = parties[partyId]
	if not party then
		notify(player, "That party no longer exists.")
		return
	end
	if party.phase ~= "lobby" then
		notify(player, "That party is already playing.")
		return
	end
	if #party.members >= party.capacity then
		notify(player, "That party is full.")
		return
	end
	table.insert(party.members, player)
	playerParty[player] = party
	notifyParty(party, player.DisplayName .. " joined the party.")
	markDirty()
end

local function setCapacity(player, capacityValue)
	local party = playerParty[player]
	if not party or party.host ~= player or party.phase ~= "lobby" then
		return
	end
	local capacity = toCapacity(capacityValue)
	if not capacity then
		return
	end
	if capacity < #party.members then
		notify(player, "The party already has " .. #party.members .. " players.")
		return
	end
	party.capacity = capacity
	markDirty()
end

local function leaveParty(player, stillInGame)
	local party = playerParty[player]
	if not party then
		return
	end
	playerParty[player] = nil
	local index = table.find(party.members, player)
	if index then
		table.remove(party.members, index)
	end

	local round = party.round
	local rp = round and round.players[player]
	if rp then
		local wasOnCourse = rp.onCourse
		rp.onCourse = false
		if rp.status == "alive" then
			rp.status = "left"
		end
		if stillInGame and wasOnCourse then
			sendToLobby(player)
		end
	end

	if #party.members == 0 then
		destroyParty(party)
		return
	end
	if party.host == player then
		party.host = party.members[1]
		notifyParty(party, party.host.DisplayName .. " is now the host.")
	end
	if round then
		checkRoundEnd(party)
	end
	markDirty()
end

actionEvent.OnServerEvent:Connect(function(player, action, arg)
	if typeof(action) ~= "string" then
		return
	end
	local clock = os.clock()
	if clock - (lastActionAt[player] or 0) < 0.25 then
		return
	end
	lastActionAt[player] = clock

	if action == "create" then
		createParty(player, arg)
	elseif action == "join" then
		joinParty(player, arg)
	elseif action == "leave" then
		leaveParty(player, true)
	elseif action == "start" then
		startRound(player)
	elseif action == "capacity" then
		setCapacity(player, arg)
	elseif action == "refresh" then
		stateEvent:FireClient(player, "state", buildSnapshot(player))
	end
end)

----------------------------------------------------------------------
-- Characters, death and respawn
----------------------------------------------------------------------
local function loadCharacter(player)
	if player.Parent ~= Players then
		return
	end
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn("Rising Escape: LoadCharacter failed for " .. player.Name .. ": " .. tostring(err))
	end
end

local function scheduleRespawn(player)
	local token = (respawnTokens[player] or 0) + 1
	respawnTokens[player] = token
	task.delay(RESPAWN_DELAY, function()
		if respawnTokens[player] == token then
			loadCharacter(player)
		end
	end)
end

local function onDied(player, character)
	if player.Character ~= character then
		return
	end
	local party = playerParty[player]
	local round = party and party.round
	local rp = round and round.players[player]
	if rp then
		rp.onCourse = false
		if rp.status == "alive" and (party.phase == "running" or party.phase == "countdown") then
			local checkpoint = round.checkpoints[rp.checkpoint]
			if lavaTopAt(round, now()) >= checkpoint.top - 1 then
				eliminate(party, player, "The lava passed your checkpoint. You're out!")
			else
				notify(player, "Respawning at your checkpoint...")
			end
		end
	end
	scheduleRespawn(player)
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or player.Character ~= character then
		return
	end
	humanoid.WalkSpeed = WALK_SPEED
	humanoid.UseJumpPower = true
	humanoid.JumpPower = JUMP_POWER
	humanoid.Died:Connect(function()
		onDied(player, character)
	end)

	local party = playerParty[player]
	local round = party and party.round
	local rp = round and round.players[player]
	if not rp or rp.status ~= "alive" or not (party.phase == "running" or party.phase == "countdown") then
		return -- stays at the lobby spawn
	end

	local checkpoint = round.checkpoints[rp.checkpoint]
	if lavaTopAt(round, now()) >= checkpoint.top - 1 then
		eliminate(party, player, "The lava passed your checkpoint. You're out!")
		return
	end

	-- Wait until the character is actually in the world before moving it.
	if not character:WaitForChild("HumanoidRootPart", 10) then
		return
	end
	if not character:IsDescendantOf(Workspace) then
		character.AncestryChanged:Wait()
	end
	task.wait()
	if player.Character == character then
		local cframe = checkpoint.cframe
		if rp.checkpoint == 0 and party.phase == "countdown" then
			cframe = round.startSpots[rng:NextInteger(1, #round.startSpots)]
		end
		placeOnCourse(player, party, cframe)
	end
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	else
		loadCharacter(player)
	end
	markDirty()
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	leaveParty(player, false)
	lastActionAt[player] = nil
	respawnTokens[player] = nil
	markDirty()
end)

----------------------------------------------------------------------
-- Main loop: countdown, lava, lava deaths, timer
----------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
	local t = now()
	for _, party in pairs(parties) do
		local round = party.round
		if round and not round.ended then
			if party.phase == "countdown" and t >= round.goAt then
				party.phase = "running"
				if round.gate then
					round.gate:Destroy()
					round.gate = nil
				end
				notifyParty(party, "GO!")
				markDirty()
			end

			if party.phase == "running" then
				local lavaTop = lavaTopAt(round, t)
				round.lava.CFrame = CFrame.new(round.lavaCenterX, lavaTop - round.lavaHeight / 2, round.lavaCenterZ)

				local bounds = round.bounds
				for member, rp in pairs(round.players) do
					if rp.status == "alive" and rp.onCourse and t >= rp.safeUntil then
						local character = member.Character
						local humanoid = getHumanoid(character)
						local root = getRoot(character)
						if humanoid and root and humanoid.Health > 0 then
							local p = root.Position
							local inside = p.X >= bounds.minX and p.X <= bounds.maxX and p.Z >= bounds.minZ and p.Z <= bounds.maxZ
							local feetY = p.Y - 3
							if (inside and feetY <= lavaTop) or p.Y < round.startTop - 40 then
								humanoid.Health = 0
							end
						end
					end
				end

				if t >= round.endsAt then
					notifyParty(party, "Time's up!")
					endRound(party)
				end
			end
		end
	end
end)
