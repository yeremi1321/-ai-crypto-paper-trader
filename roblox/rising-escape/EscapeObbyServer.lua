-- Rising Escape — server (v2: escape from inside the volcano)
-- Put this in ServerScriptService as a Script named EscapeObbyServer.
-- Everything (remotes, lobby spawn, volcano courses) is created by this script.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")

----------------------------------------------------------------------
-- Tuning
----------------------------------------------------------------------
local MIN_PARTY = 1
local MAX_PARTY = 6
local SECTION_COUNT = 6 -- obstacle sections per round, shuffled every round
local CHECKPOINT_SECTIONS = { [3] = true, [5] = true } -- checkpoint at the start of these sections

local COUNTDOWN_SECONDS = 3
local ROUND_SECONDS = 180
local LAVA_GRACE_SECONDS = 8 -- lava waits this long after GO
local LAVA_REACHES_FINISH_AT = 175 -- seconds after GO when lava covers the helipad
local RESPAWN_DELAY = 2
local RESULTS_SECONDS = 8
local TELEPORT_GRACE = 1.5 -- ignore lava checks right after a teleport

-- Default Roblox movement. Every jump below is sized for these values:
-- a flat jump covers ~8 studs, ~7 studs when landing 2.5 studs higher.
local WALK_SPEED = 16
local JUMP_POWER = 50
local MAX_GAP = 5.5

local ROPE_LENGTH = 14 -- rope between neighbouring teammates

local CRUMBLE_DELAY = 0.7 -- cracked ledge falls this long after it is touched
local CRUMBLE_RESPAWN = 4
local BRIDGE_BASE_SECONDS = 5 -- bridge lasts this long after the first step...
local BRIDGE_PER_PLAYER = 1.5 -- ...plus this per extra player
local BRIDGE_REBUILD_SECONDS = 6
local SWING_AUTO_OPEN = 35 -- safety: swing bridge lowers by itself after this long
local GEYSER_PERIOD = 7
local GEYSER_WARNING = 2.5 -- vent glows and rumbles this long before erupting
local GEYSER_ACTIVE = 1.5
local GEYSER_HEIGHT = 12

local COURSE_ORIGIN = Vector3.new(-70, 45, 200)
local COURSE_SPACING = 320 -- distance between volcanoes of different parties

-- Set to false for the plain look: smoky orange sky, dark floor, background volcano.
local VOLCANO_WORLD = true

-- Layout inside each volcano (studs, relative to the course origin).
local SHAFT_MIN_X, SHAFT_MAX_X = -6, 78
local SHAFT_HALF_Z = 34
local WALL_THICKNESS = 6
local LANE_Z = { -16, 16 } -- sections alternate between two lanes as they climb
local INNER_X = { 11, 61 } -- where a section begins (after its start landing)
local SECTION_SPAN = 50 -- length of a section between its two landings

----------------------------------------------------------------------
-- Look
----------------------------------------------------------------------
local LAVA_COLOR = Color3.fromRGB(255, 80, 20)
local MAGMA_COLOR = Color3.fromRGB(255, 110, 30)
local CHECKPOINT_COLOR = Color3.fromRGB(60, 220, 90)

local ZONES = {
	cave = {
		name = "Smoky Cave",
		rock = { Color3.fromRGB(58, 56, 60), Color3.fromRGB(72, 68, 70), Color3.fromRGB(50, 48, 52) },
		wall = Color3.fromRGB(44, 42, 46),
		wallMaterial = Enum.Material.Slate,
		glow = Color3.fromRGB(255, 120, 50),
	},
	magma = {
		name = "Magma Tunnels",
		rock = { Color3.fromRGB(78, 40, 32), Color3.fromRGB(92, 48, 36), Color3.fromRGB(66, 34, 30) },
		wall = Color3.fromRGB(60, 30, 26),
		wallMaterial = Enum.Material.Basalt,
		glow = Color3.fromRGB(255, 90, 20),
	},
	rim = {
		name = "Crater Rim",
		rock = { Color3.fromRGB(104, 82, 64), Color3.fromRGB(120, 96, 74), Color3.fromRGB(92, 72, 58) },
		wall = Color3.fromRGB(86, 66, 52),
		wallMaterial = Enum.Material.Rock,
		glow = Color3.fromRGB(255, 150, 60),
	},
}

local SECTION_KINDS = { "stones", "rescue", "split", "geysers", "bridge", "swing" }
local SECTION_INFO = {
	stones = { name = "Basalt Pillars", hint = "Hop across the pillars." },
	rescue = {
		name = "Rescue Ledges",
		hint = "Cracked ledges crumble! If a teammate falls, tap PULL to save them.",
	},
	split = {
		name = "Split Path",
		hint = "Split up! Stand on BOTH switches at the same time to open the gate.",
		soloHint = "Step on a switch to open the gate.",
	},
	geysers = { name = "Geyser Field", hint = "Vents glow and rumble before they erupt. Dodge the geysers!" },
	bridge = { name = "Collapsing Bridge", hint = "The bridge breaks soon after the first step. Cross together!" },
	swing = {
		name = "Rope Swing",
		hint = "Jump at the glowing hook to swing across, then hit the lever to lower the bridge.",
	},
}

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

local function newPart(parent, name, size, cframe, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function noCollide(part)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

-- Volcano world: only changes things while the game runs, never your saved place.
local function setupVolcanoWorld()
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
	-- A big smoking volcano on the horizon, seen from the lobby.
	local model = Instance.new("Model")
	model.Name = "VolcanoBackdrop"
	local base = Vector3.new(-380, 0, -220)
	local layers, layerHeight = 10, 14
	local bottomRadius, topRadius = 150, 45
	local peakY = layers * layerHeight
	local rock = ZONES.cave.rock
	for i = 0, layers - 1 do
		local radius = bottomRadius + (topRadius - bottomRadius) * (i / (layers - 1))
		newPart(
			model,
			"Slope",
			Vector3.new(layerHeight, radius * 2, radius * 2),
			CFrame.new(base.X, base.Y + i * layerHeight + layerHeight / 2, base.Z) * CFrame.Angles(0, 0, math.pi / 2),
			rock[(i % #rock) + 1],
			Enum.Material.Basalt,
			Enum.PartType.Cylinder
		)
	end
	local crater = newPart(
		model,
		"CraterLava",
		Vector3.new(1, topRadius * 1.6, topRadius * 1.6),
		CFrame.new(base.X, peakY + 0.4, base.Z) * CFrame.Angles(0, 0, math.pi / 2),
		LAVA_COLOR,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	crater.CanCollide = false

	local smoke = Instance.new("ParticleEmitter")
	smoke.EmissionDirection = Enum.NormalId.Right -- the cylinder's top face after rotating
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 80, 80), Color3.fromRGB(40, 35, 35))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 20), NumberSequenceKeypoint.new(1, 45) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(8, 12)
	smoke.Rate = 4
	smoke.Speed = NumberRange.new(8, 14)
	smoke.Parent = crater

	for i = 1, 5 do
		local angle = (i / 5) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local startPoint = base + dir * (topRadius + 2) + Vector3.new(0, peakY, 0)
		local endPoint = base + dir * (bottomRadius + 2) + Vector3.new(0, 1, 0)
		local stream = newPart(
			model,
			"LavaStream",
			Vector3.new(rng:NextNumber(5, 9), 1, (endPoint - startPoint).Magnitude),
			CFrame.lookAt((startPoint + endPoint) / 2, endPoint),
			MAGMA_COLOR,
			Enum.Material.Neon
		)
		stream.CanCollide = false
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
local lastActionAt = {} -- [Player] = { [action] = os.clock() }
local respawnTokens = {} -- [Player] = number
local nextPartyId = 0
local dirty = true

local ACTION_COOLDOWN = { hang = 0.05, pull = 0.2 }

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

-- Calls back for every living, on-course player of a round.
local function forEachClimber(round, callback)
	for member, rp in pairs(round.players) do
		if rp.status == "alive" and rp.onCourse then
			local character = member.Character
			local humanoid = getHumanoid(character)
			local root = getRoot(character)
			if humanoid and root and humanoid.Health > 0 then
				callback(member, rp, root, humanoid)
			end
		end
	end
end

local function aliveCount(round)
	local count = 0
	for _, rp in pairs(round.players) do
		if rp.status == "alive" then
			count += 1
		end
	end
	return count
end

----------------------------------------------------------------------
-- Course building helpers
----------------------------------------------------------------------
local function addLabel(part, text, color, offsetY)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(200, 40)
	billboard.StudsOffset = Vector3.new(0, offsetY or 4, 0)
	billboard.MaxDistance = 90
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

local function addLight(part, color, range, brightness)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
	return light
end

-- Thin glowing slab under a platform so its edges look red-hot. No collision.
local function addGlowRim(folder, pad, color)
	local rim = newPart(
		folder,
		pad.Name .. "Glow",
		Vector3.new(pad.Size.X + 0.6, 0.5, pad.Size.Z + 0.6),
		pad.CFrame * CFrame.new(0, -pad.Size.Y / 2 - 0.1, 0),
		color,
		Enum.Material.Neon
	)
	noCollide(rim)
end

-- A falling copy of a part, for crumble and collapse effects.
local function spawnDebris(part, folder)
	local piece = part:Clone()
	for _, child in ipairs(piece:GetChildren()) do
		child:Destroy()
	end
	piece.Anchored = false
	piece.CanCollide = false
	piece.CanTouch = false
	piece.CanQuery = false
	piece.Transparency = 0
	piece.Parent = folder
	piece.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-3, 3), rng:NextNumber(-3, 3))
	Debris:AddItem(piece, 3)
end

local function claimSlot()
	local slot = 0
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	return slot
end

local function facing(position, dir)
	return CFrame.lookAt(position, position + Vector3.new(dir, 0, 0))
end

local function zoneFor(index)
	if index <= 2 then
		return ZONES.cave
	elseif index <= 4 then
		return ZONES.magma
	end
	return ZONES.rim
end

local function rockColor(zone)
	return zone.rock[rng:NextInteger(1, #zone.rock)]
end

local function isRunning(round)
	return round.party.round == round and round.party.phase == "running"
end

-- Section context. Positions inside a section are given as (along, side, top):
-- "along" runs from the section's start landing (0) to its end landing (SECTION_SPAN).
local function newSection(round, index, kind, startTop)
	local lane = (index % 2 == 1) and 1 or 2
	local dir = (index % 2 == 1) and 1 or -1
	return {
		round = round,
		folder = round.folder,
		index = index,
		kind = kind,
		dir = dir,
		laneZ = round.origin.Z + LANE_Z[lane],
		innerX = round.origin.X + (dir == 1 and INNER_X[1] or INNER_X[2]),
		startTop = startTop,
		zone = zoneFor(index),
	}
end

local function sectionPoint(ctx, along, side, y)
	return Vector3.new(ctx.innerX + ctx.dir * along, y, ctx.laneZ + side)
end

-- A 1-stud-thick pad whose top surface is at `top`.
local function sectionPad(ctx, name, alongStart, length, side, width, top, color, material)
	local center = sectionPoint(ctx, alongStart + length / 2, side, top - 0.5)
	return newPart(ctx.folder, name, Vector3.new(length, 1, width), CFrame.new(center), color, material)
end

-- Lays pads in a line with equal gaps from `alongFrom` to `alongTo`.
-- Each spec: { len, width, rise, side, name, color, material }.
-- Returns the pads and the top height for whatever comes after.
local function buildChain(ctx, specs, alongFrom, alongTo, fromTop, endRise, fromSide, fromWidth)
	local total = 0
	for _, spec in ipairs(specs) do
		total += spec.len
	end
	local gap = (alongTo - alongFrom - total) / (#specs + 1)
	if gap > MAX_GAP or gap < 0.5 then
		warn(string.format("Rising Escape: %s section gap %.1f is out of range", ctx.kind, gap))
	end
	local along = alongFrom
	local top = fromTop
	local prevSide, prevWidth = fromSide or 0, fromWidth or 10
	local pads = {}
	for i, spec in ipairs(specs) do
		along += gap
		top += spec.rise
		-- Keep neighbouring pads overlapping sideways so every jump is straight ahead.
		local limit = (prevWidth + spec.width) / 2 - 1.5
		local side = math.clamp(spec.side or 0, prevSide - limit, prevSide + limit)
		local part = sectionPad(
			ctx,
			spec.name or ("Step" .. i),
			along,
			spec.len,
			side,
			spec.width,
			top,
			spec.color or rockColor(ctx.zone),
			spec.material or Enum.Material.Basalt
		)
		pads[i] = { part = part, top = top, side = side, along = along }
		along += spec.len
		prevSide, prevWidth = side, spec.width
	end
	return pads, top + endRise
end

----------------------------------------------------------------------
-- Obstacle sections. Each returns the top height of its end landing.
----------------------------------------------------------------------
local builders = {}

-- Basalt Pillars: plain hops, a warm-up that changes every round.
function builders.stones(ctx)
	local specs = {}
	local side = 0
	for i = 1, 5 do
		side = math.clamp(side + rng:NextNumber(-4, 4), -7, 7)
		if i == 5 then
			side = math.clamp(side, -3, 3)
		end
		specs[i] = { len = 5, width = 5, rise = rng:NextNumber(1, 2), side = side, name = "Pillar" .. i }
	end
	local pads, endTop = buildChain(ctx, specs, 0, SECTION_SPAN, ctx.startTop, 1.5, 0, 10)
	for _, pad in ipairs(pads) do
		addGlowRim(ctx.folder, pad.part, ctx.zone.glow)
		local column = newPart(
			ctx.folder,
			"PillarColumn",
			Vector3.new(pad.part.Size.X - 0.8, 10, pad.part.Size.Z - 0.8),
			pad.part.CFrame * CFrame.new(0, -5.5, 0),
			pad.part.Color,
			Enum.Material.Basalt
		)
		noCollide(column)
	end
	return endTop
end

-- Rescue Ledges: narrow cracked ledges crumble; wide safe ledges catch you.
function builders.rescue(ctx)
	local pattern = { "safe", "crumble", "crumble", "safe", "crumble", "crumble", "safe" }
	local specs = {}
	for i, kind in ipairs(pattern) do
		if kind == "safe" then
			specs[i] = { len = 5, width = 6, rise = 1, side = 0, name = "RescueLedge" }
		else
			specs[i] = {
				len = 4,
				width = 3,
				rise = 0.6,
				side = (i % 2 == 0) and -1.5 or 1.5,
				name = "CrackedLedge",
				color = Color3.fromRGB(110, 70, 50),
				material = Enum.Material.CrackedLava,
			}
		end
	end
	local pads, endTop = buildChain(ctx, specs, 0, SECTION_SPAN, ctx.startTop, 1, 0, 10)
	for i, pad in ipairs(pads) do
		local part = pad.part
		if pattern[i] == "safe" then
			addGlowRim(ctx.folder, part, CHECKPOINT_COLOR)
			if i == 1 then
				addLabel(part, "RESCUE LEDGE", Color3.fromRGB(140, 255, 160), 3)
			end
		else
			local originalColor = part.Color
			local state = "solid"
			table.insert(
				ctx.round.connections,
				part.Touched:Connect(function(hit)
					if state ~= "solid" or not isRunning(ctx.round) then
						return
					end
					local who = playerFromHit(hit)
					if not who or not ctx.round.players[who] then
						return
					end
					state = "cracking"
					part.Color = Color3.fromRGB(255, 120, 40)
					task.delay(CRUMBLE_DELAY, function()
						if not part.Parent then
							return
						end
						state = "fallen"
						spawnDebris(part, ctx.folder)
						part.Transparency = 1
						part.CanCollide = false
						task.delay(CRUMBLE_RESPAWN, function()
							if not part.Parent then
								return
							end
							part.Transparency = 0
							part.CanCollide = true
							part.Color = originalColor
							state = "solid"
						end)
					end)
				end)
			)
		end
	end
	return endTop
end

-- Split Path: two paths over a lava channel, a switch on each, a gate at the end.
function builders.split(ctx)
	local round = ctx.round
	local switches = {}
	local reunionAlong, reunionLen = 36, 10
	local pathTop = ctx.startTop
	for _, sign in ipairs({ -1, 1 }) do
		local specs = {
			{ len = 5, width = 5, rise = 1, side = sign * 6 },
			{ len = 5, width = 5, rise = 1, side = sign * 8 },
			{ len = 5, width = 5, rise = 1, side = sign * 8 },
			{ len = 6, width = 6, rise = 1, side = sign * 8, name = "SwitchPad" },
		}
		local pads, top = buildChain(ctx, specs, 0, reunionAlong, ctx.startTop, 1, 0, 10)
		pathTop = top
		local switchPad = pads[4]
		local button = newPart(
			ctx.folder,
			"Switch",
			Vector3.new(0.4, 4, 4),
			CFrame.new(sectionPoint(ctx, switchPad.along + 3, switchPad.side, switchPad.top + 0.2))
				* CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(220, 50, 40),
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
		noCollide(button)
		addLabel(button, "SWITCH", Color3.fromRGB(255, 220, 120), 3)
		table.insert(switches, { part = button, center = button.Position })
	end

	local reunion = sectionPad(ctx, "Reunion", reunionAlong, reunionLen, 0, 22, pathTop, rockColor(ctx.zone), Enum.Material.Basalt)
	addGlowRim(ctx.folder, reunion, ctx.zone.glow)
	local gate = newPart(
		ctx.folder,
		"SplitGate",
		Vector3.new(1, 14, 22),
		CFrame.new(sectionPoint(ctx, reunionAlong + reunionLen + 0.5, 0, pathTop + 7)),
		MAGMA_COLOR,
		Enum.Material.ForceField
	)
	gate.Transparency = 0.3
	addLabel(gate, "GATE LOCKED", Color3.fromRGB(255, 200, 120), 8)

	local opened = false
	table.insert(round.updaters, function()
		if opened then
			return
		end
		local needed = math.min(2, aliveCount(round))
		local pressed = 0
		for _, switch in ipairs(switches) do
			local on = false
			forEachClimber(round, function(_, _, root)
				local offset = root.Position - switch.center
				if Vector3.new(offset.X, 0, offset.Z).Magnitude < 3.2 and offset.Y > 0 and offset.Y < 7 then
					on = true
				end
			end)
			switch.part.Color = on and Color3.fromRGB(70, 230, 90) or Color3.fromRGB(220, 50, 40)
			if on then
				pressed += 1
			end
		end
		if needed > 0 and pressed >= needed then
			opened = true
			gate:Destroy()
			for _, switch in ipairs(switches) do
				switch.part.Color = Color3.fromRGB(70, 230, 90)
			end
			for member in pairs(round.players) do
				notify(member, "The gate is open!")
			end
		end
	end)
	-- The reunion ends at along 46; a 4 gap and a 0.5 rise reach the end landing.
	return pathTop + 0.5
end

-- Geyser Field: vents glow and rumble, then erupt. Safe lanes always exist.
function builders.geysers(ctx)
	local round = ctx.round
	local specs = {}
	for i = 1, 3 do
		specs[i] = { len = 13, width = 18, rise = 2, side = 0, name = "VentFloor" .. i }
	end
	local pads, endTop = buildChain(ctx, specs, 0, SECTION_SPAN, ctx.startTop, 2, 0, 10)
	local vents = {}
	for slabIndex, pad in ipairs(pads) do
		for _, sign in ipairs({ -1, 1 }) do
			local alongPos = pad.along + (sign < 0 and 4 or 9)
			local center = sectionPoint(ctx, alongPos, sign * 4.5, pad.top)
			local vent = newPart(
				ctx.folder,
				"Vent",
				Vector3.new(0.4, 5, 5),
				CFrame.new(center + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				Color3.fromRGB(70, 30, 20),
				Enum.Material.CrackedLava,
				Enum.PartType.Cylinder
			)
			noCollide(vent)
			vent:SetAttribute("State", "idle")
			CollectionService:AddTag(vent, "RisingEscapeVent")
			local light = addLight(vent, MAGMA_COLOR, 14, 0)

			local smoke = Instance.new("ParticleEmitter")
			smoke.EmissionDirection = Enum.NormalId.Right
			smoke.Color = ColorSequence.new(Color3.fromRGB(120, 100, 90))
			smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
			smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
			smoke.Lifetime = NumberRange.new(1, 2)
			smoke.Speed = NumberRange.new(4, 8)
			smoke.Rate = 18
			smoke.Enabled = false
			smoke.Parent = vent

			local column = newPart(
				ctx.folder,
				"Geyser",
				Vector3.new(GEYSER_HEIGHT, 5, 5),
				CFrame.new(center + Vector3.new(0, GEYSER_HEIGHT / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				MAGMA_COLOR,
				Enum.Material.Neon,
				Enum.PartType.Cylinder
			)
			noCollide(column)
			column.Transparency = 1

			table.insert(vents, {
				vent = vent,
				light = light,
				smoke = smoke,
				column = column,
				center = center,
				offset = (sign < 0 and 0 or GEYSER_PERIOD / 2) + slabIndex * 1.2,
				state = "idle",
			})
		end
	end

	table.insert(round.updaters, function(t)
		local elapsed = t - round.goAt
		for _, v in ipairs(vents) do
			local phase = (elapsed + v.offset) % GEYSER_PERIOD
			local state = "idle"
			if phase < GEYSER_WARNING then
				state = "warning"
			elseif phase < GEYSER_WARNING + GEYSER_ACTIVE then
				state = "active"
			end
			if state ~= v.state then
				v.state = state
				v.vent:SetAttribute("State", state)
				v.smoke.Enabled = state == "warning"
				v.column.Transparency = state == "active" and 0.15 or 1
				v.vent.Color = state == "idle" and Color3.fromRGB(70, 30, 20) or Color3.fromRGB(255, 150, 60)
				v.vent.Material = state == "idle" and Enum.Material.CrackedLava or Enum.Material.Neon
				v.light.Brightness = state == "idle" and 0 or (state == "warning" and 2 or 5)
			end
			if state == "active" then
				forEachClimber(round, function(member, _, root, humanoid)
					local offset = root.Position - v.center
					if Vector3.new(offset.X, 0, offset.Z).Magnitude < 3 and offset.Y > -1 and offset.Y < GEYSER_HEIGHT then
						humanoid.Health = 0
						notify(member, "Scorched by a geyser!")
					end
				end)
			end
		end
	end)
	return endTop
end

-- Collapsing Bridge: breaks a few seconds after the first step, then rebuilds.
function builders.bridge(ctx)
	local round = ctx.round
	local padLen, plankLen, plankCount = 8, 4, 7
	local padA = sectionPad(ctx, "BridgeStart", 3.5, padLen, 0, 8, ctx.startTop + 1.5, rockColor(ctx.zone), Enum.Material.Basalt)
	addGlowRim(ctx.folder, padA, ctx.zone.glow)
	local top = ctx.startTop + 1.5
	local planks = {}
	local plankStart = 3.5 + padLen
	for i = 1, plankCount do
		top += 0.4
		local plank = sectionPad(
			ctx,
			"BridgePlank",
			plankStart + (i - 1) * plankLen,
			plankLen - 0.15,
			0,
			5,
			top,
			Color3.fromRGB(110, 78, 52),
			Enum.Material.WoodPlanks
		)
		table.insert(planks, { part = plank, color = plank.Color })
	end
	local padBStart = plankStart + plankCount * plankLen
	local padB = sectionPad(ctx, "BridgeEnd", padBStart, 7, 0, 8, top, rockColor(ctx.zone), Enum.Material.Basalt)
	addGlowRim(ctx.folder, padB, ctx.zone.glow)
	addLabel(planks[1].part, "CROSS TOGETHER!", Color3.fromRGB(255, 200, 120), 5)

	local state, stateAt, breakAt = "intact", 0, 0
	local function onTouch(hit)
		if state ~= "intact" or not isRunning(round) then
			return
		end
		local who = playerFromHit(hit)
		if not who or not round.players[who] then
			return
		end
		state = "cracking"
		stateAt = now()
		breakAt = stateAt + BRIDGE_BASE_SECONDS + BRIDGE_PER_PLAYER * math.max(0, aliveCount(round) - 1)
		for member in pairs(round.players) do
			notify(member, "The bridge is cracking! Everyone across!")
		end
	end
	for _, plank in ipairs(planks) do
		table.insert(round.connections, plank.part.Touched:Connect(onTouch))
	end

	table.insert(round.updaters, function(t)
		if state == "cracking" then
			local alpha = math.clamp((t - stateAt) / (breakAt - stateAt), 0, 1)
			local flicker = (math.floor(t * 6) % 2 == 0) and 1 or 0.7
			for _, plank in ipairs(planks) do
				plank.part.Color = plank.color:Lerp(Color3.fromRGB(255, 90, 30), alpha * flicker)
			end
			if t >= breakAt then
				state = "broken"
				stateAt = t
				for _, plank in ipairs(planks) do
					spawnDebris(plank.part, ctx.folder)
					plank.part.Transparency = 1
					plank.part.CanCollide = false
				end
			end
		elseif state == "broken" and t - stateAt >= BRIDGE_REBUILD_SECONDS then
			state = "intact"
			for _, plank in ipairs(planks) do
				plank.part.Transparency = 0
				plank.part.CanCollide = true
				plank.part.Color = plank.color
			end
		end
	end)
	-- padB ends at along 46.5; a 3.5 gap and a 1.5 rise reach the end landing.
	return top + 1.5
end

-- Rope Swing: too wide to jump. Swing from the hook, hit the lever, a bridge lowers.
function builders.swing(ctx)
	local round = ctx.round
	local approachTop = ctx.startTop + 2
	local approach = sectionPad(ctx, "SwingLedge", 3.5, 7.5, 0, 8, approachTop, rockColor(ctx.zone), Enum.Material.Basalt)
	addGlowRim(ctx.folder, approach, ctx.zone.glow)

	local farTop = approachTop - 1.5
	local far = sectionPad(ctx, "LeverLedge", 29, 8, 0, 8, farTop, rockColor(ctx.zone), Enum.Material.Basalt)
	addGlowRim(ctx.folder, far, ctx.zone.glow)
	local stepTop = farTop + 2
	local step = sectionPad(ctx, "SwingExit", 41, 5, 0, 6, stepTop, rockColor(ctx.zone), Enum.Material.Basalt)
	addGlowRim(ctx.folder, step, ctx.zone.glow)

	-- The hook. Each player's own client does the swinging, using these attributes.
	local hookPos = sectionPoint(ctx, 20, 0, approachTop + 11)
	local hook = newPart(ctx.folder, "SwingHook", Vector3.new(2, 2, 2), CFrame.new(hookPos), MAGMA_COLOR, Enum.Material.Neon, Enum.PartType.Ball)
	noCollide(hook)
	hook:SetAttribute("Dir", ctx.dir)
	hook:SetAttribute("StartX", sectionPoint(ctx, 9, 0, 0).X)
	hook:SetAttribute("ReleaseX", sectionPoint(ctx, 27.5, 0, 0).X)
	hook:SetAttribute("MaxLength", 16)
	CollectionService:AddTag(hook, "RisingEscapeHook")
	addLight(hook, MAGMA_COLOR, 16, 2)
	addLabel(hook, "JUMP TO SWING", Color3.fromRGB(255, 220, 120), 3)
	local chain = newPart(ctx.folder, "HookChain", Vector3.new(0.4, 14, 0.4), CFrame.new(hookPos + Vector3.new(0, 8, 0)), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
	noCollide(chain)

	-- Hidden bridge across the gap, lowered by the lever.
	local bridge = sectionPad(ctx, "SwingBridge", 11, 18, 0, 5, farTop, Color3.fromRGB(110, 78, 52), Enum.Material.WoodPlanks)
	bridge.Transparency = 1
	bridge.CanCollide = false

	local leverBase = newPart(
		ctx.folder,
		"LeverButton",
		Vector3.new(3, 0.4, 3),
		CFrame.new(sectionPoint(ctx, 35, 0, farTop + 0.2)),
		Color3.fromRGB(220, 50, 40),
		Enum.Material.Neon
	)
	leverBase.CanCollide = false
	local handle = newPart(
		ctx.folder,
		"LeverHandle",
		Vector3.new(0.4, 3, 0.4),
		CFrame.new(leverBase.Position + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(25)),
		Color3.fromRGB(230, 230, 230),
		Enum.Material.Metal
	)
	noCollide(handle)
	addLabel(leverBase, "LEVER", Color3.fromRGB(255, 220, 120), 4)

	local opened = false
	local firstArrival = nil
	local function open(byName)
		if opened then
			return
		end
		opened = true
		bridge.Transparency = 0
		bridge.CanCollide = true
		leverBase.Color = Color3.fromRGB(70, 230, 90)
		handle.CFrame = CFrame.new(leverBase.Position + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(-25))
		for member in pairs(round.players) do
			notify(member, byName and (byName .. " lowered the bridge!") or "The bridge lowered by itself.")
		end
	end
	table.insert(
		round.connections,
		leverBase.Touched:Connect(function(hit)
			local who = playerFromHit(hit)
			if who and round.players[who] and isRunning(round) then
				open(who.DisplayName)
			end
		end)
	)
	table.insert(
		round.connections,
		approach.Touched:Connect(function(hit)
			local who = playerFromHit(hit)
			if who and round.players[who] and isRunning(round) and not firstArrival then
				firstArrival = now()
			end
		end)
	)
	table.insert(round.updaters, function(t)
		if not opened and firstArrival and t - firstArrival >= SWING_AUTO_OPEN then
			open(nil)
		end
	end)
	-- The exit step ends at along 46; a 4 gap and a 2.5 rise reach the end landing.
	return stepTop + 2.5
end

----------------------------------------------------------------------
-- Volcano shell, zones, helicopter
----------------------------------------------------------------------
local function buildShell(round, bottomY, zoneTops)
	local origin = round.origin
	local folder = round.folder
	local minX, maxX = origin.X + SHAFT_MIN_X, origin.X + SHAFT_MAX_X
	local minZ, maxZ = origin.Z - SHAFT_HALF_Z, origin.Z + SHAFT_HALF_Z
	local midX, midZ = (minX + maxX) / 2, (minZ + maxZ) / 2
	local lengthX, lengthZ = maxX - minX, maxZ - minZ
	local w = WALL_THICKNESS

	local bands = {
		{ zone = ZONES.cave, from = bottomY, to = zoneTops[1] },
		{ zone = ZONES.magma, from = zoneTops[1], to = zoneTops[2] },
		{ zone = ZONES.rim, from = zoneTops[2], to = zoneTops[3] },
	}
	for _, band in ipairs(bands) do
		local h = band.to - band.from
		local y = (band.from + band.to) / 2
		local zone = band.zone
		local walls = {
			newPart(folder, "Wall", Vector3.new(lengthX + 2 * w, h, w), CFrame.new(midX, y, minZ - w / 2), zone.wall, zone.wallMaterial),
			newPart(folder, "Wall", Vector3.new(lengthX + 2 * w, h, w), CFrame.new(midX, y, maxZ + w / 2), zone.wall, zone.wallMaterial),
			newPart(folder, "Wall", Vector3.new(w, h, lengthZ), CFrame.new(minX - w / 2, y, midZ), zone.wall, zone.wallMaterial),
			newPart(folder, "Wall", Vector3.new(w, h, lengthZ), CFrame.new(maxX + w / 2, y, midZ), zone.wall, zone.wallMaterial),
		}
		if zone == ZONES.magma then
			-- Glowing magma veins on the tunnel walls.
			local inwards = { Vector3.new(0, 0, 1), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) }
			for i, wall in ipairs(walls) do
				local alongX = i <= 2
				local span = alongX and lengthX or lengthZ
				for k = 1, 4 do
					local t = (k - 0.5) / 4 - 0.5 + rng:NextNumber(-0.06, 0.06)
					local offset = alongX and Vector3.new(t * span, 0, 0) or Vector3.new(0, 0, t * span)
					local pos = wall.Position + offset + inwards[i] * (w / 2 + 0.2)
					local vein = newPart(
						folder,
						"MagmaVein",
						alongX and Vector3.new(rng:NextNumber(1.5, 3), h, 0.4) or Vector3.new(0.4, h, rng:NextNumber(1.5, 3)),
						CFrame.new(pos),
						MAGMA_COLOR,
						Enum.Material.Neon
					)
					noCollide(vein)
					if k % 2 == 0 then
						addLight(vein, MAGMA_COLOR, 30, 1.5)
					end
				end
			end
		elseif zone == ZONES.cave then
			-- Smoke drifting up through the cave.
			for _, corner in ipairs({
				Vector3.new(minX + 6, 0, minZ + 6),
				Vector3.new(maxX - 6, 0, maxZ - 6),
				Vector3.new(minX + 6, 0, maxZ - 6),
				Vector3.new(maxX - 6, 0, minZ + 6),
			}) do
				local source = newPart(folder, "SmokeSource", Vector3.new(10, 1, 10), CFrame.new(corner.X, band.from + h * 0.4, corner.Z), Color3.new(), Enum.Material.SmoothPlastic)
				noCollide(source)
				source.Transparency = 1
				local smoke = Instance.new("ParticleEmitter")
				smoke.EmissionDirection = Enum.NormalId.Top
				smoke.Color = ColorSequence.new(Color3.fromRGB(80, 74, 72))
				smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 16) })
				smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
				smoke.Lifetime = NumberRange.new(5, 8)
				smoke.Rate = 3
				smoke.Speed = NumberRange.new(2, 4)
				smoke.Parent = source
			end
		end
	end

	-- Jagged crater rim on top of the walls.
	local rimTop = zoneTops[3]
	local rimRocks = {}
	for _, edge in ipairs({
		{ from = Vector3.new(minX - w, 0, minZ - w / 2), to = Vector3.new(maxX + w, 0, minZ - w / 2) },
		{ from = Vector3.new(minX - w, 0, maxZ + w / 2), to = Vector3.new(maxX + w, 0, maxZ + w / 2) },
		{ from = Vector3.new(minX - w / 2, 0, minZ), to = Vector3.new(minX - w / 2, 0, maxZ) },
		{ from = Vector3.new(maxX + w / 2, 0, minZ), to = Vector3.new(maxX + w / 2, 0, maxZ) },
	}) do
		local length = (edge.to - edge.from).Magnitude
		local count = math.max(1, math.floor(length / 10))
		for k = 0, count - 1 do
			local p = edge.from:Lerp(edge.to, (k + 0.5) / count)
			local height = rng:NextNumber(3, 14)
			local rock = newPart(
				folder,
				"RimRock",
				Vector3.new(rng:NextNumber(7, 12), height, rng:NextNumber(7, 12)),
				CFrame.new(p.X, rimTop + height / 2, p.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				rockColor(ZONES.rim),
				Enum.Material.Rock
			)
			table.insert(rimRocks, rock)
		end
	end

	-- Outer slopes so each course looks like a volcano from the lobby. They stop
	-- well below the rim, so nobody can climb in from outside.
	local slopeTop = rimTop - 25
	local slopeHeight = slopeTop - bottomY
	local depth = 100
	for _, side in ipairs({
		{ center = Vector3.new(midX, 0, minZ - w), out = Vector3.new(0, 0, -1), width = lengthX + 2 * w },
		{ center = Vector3.new(midX, 0, maxZ + w), out = Vector3.new(0, 0, 1), width = lengthX + 2 * w },
		{ center = Vector3.new(minX - w, 0, midZ), out = Vector3.new(-1, 0, 0), width = lengthZ + 2 * w },
		{ center = Vector3.new(maxX + w, 0, midZ), out = Vector3.new(1, 0, 0), width = lengthZ + 2 * w },
	}) do
		local center = side.center + side.out * (depth / 2) + Vector3.new(0, bottomY + slopeHeight / 2, 0)
		local wedge = Instance.new("WedgePart")
		wedge.Name = "VolcanoSlope"
		wedge.Anchored = true
		wedge.Size = Vector3.new(side.width, slopeHeight, depth)
		wedge.CFrame = CFrame.lookAt(center, center + side.out)
		wedge.Color = ZONES.cave.wall
		wedge.Material = Enum.Material.Basalt
		wedge.Parent = folder
	end
	return rimRocks
end

local function buildHelicopter(round, pad)
	local folder = round.folder
	local c = pad.Position + Vector3.new(0, 11, 0)
	local yellow = Color3.fromRGB(245, 190, 40)
	local dark = Color3.fromRGB(50, 50, 55)
	local function piece(name, size, cf, color, material, shape)
		local p = newPart(folder, name, size, cf, color, material, shape)
		noCollide(p)
		return p
	end
	local body = piece("HeliBody", Vector3.new(9, 5, 5), CFrame.new(c), yellow, Enum.Material.SmoothPlastic)
	local nose = piece("HeliNose", Vector3.new(5, 5, 5), CFrame.new(c + Vector3.new(4.5, -0.2, 0)), Color3.fromRGB(150, 210, 255), Enum.Material.Glass, Enum.PartType.Ball)
	nose.Transparency = 0.3
	piece("HeliTail", Vector3.new(10, 1.2, 1.2), CFrame.new(c + Vector3.new(-9, 0.8, 0)), yellow, Enum.Material.SmoothPlastic)
	piece("HeliFin", Vector3.new(1.5, 3, 0.4), CFrame.new(c + Vector3.new(-13.5, 2, 0)), Color3.fromRGB(200, 60, 40), Enum.Material.SmoothPlastic)
	piece("HeliSkid", Vector3.new(10, 0.4, 0.4), CFrame.new(c + Vector3.new(0, -3.6, 2.2)), dark, Enum.Material.Metal)
	piece("HeliSkid", Vector3.new(10, 0.4, 0.4), CFrame.new(c + Vector3.new(0, -3.6, -2.2)), dark, Enum.Material.Metal)
	piece("HeliMast", Vector3.new(0.6, 1.5, 0.6), CFrame.new(c + Vector3.new(0, 3.2, 0)), dark, Enum.Material.Metal)
	local hub = c + Vector3.new(0, 4, 0)
	local bladeA = piece("Rotor", Vector3.new(24, 0.3, 1.2), CFrame.new(hub), dark, Enum.Material.Metal)
	local bladeB = piece("Rotor", Vector3.new(1.2, 0.3, 24), CFrame.new(hub), dark, Enum.Material.Metal)
	piece("Ladder", Vector3.new(0.3, 8, 2), CFrame.new(c + Vector3.new(0, -7, 0)), Color3.fromRGB(150, 110, 70), Enum.Material.Fabric)
	addLabel(body, "ESCAPE!", Color3.fromRGB(255, 230, 120), 7)
	addLight(body, Color3.fromRGB(255, 240, 200), 24, 2)

	table.insert(round.updaters, function(t)
		local spin = CFrame.new(hub) * CFrame.Angles(0, (t * 12) % (math.pi * 2), 0)
		bladeA.CFrame = spin
		bladeB.CFrame = spin
	end)
end

----------------------------------------------------------------------
-- Building one full course
----------------------------------------------------------------------
-- Builds a fresh volcano course. Returns the round table (without players).
local function buildCourse(party)
	local slot = claimSlot()
	local origin = COURSE_ORIGIN + Vector3.new(0, 0, slot * COURSE_SPACING)
	local folder = Instance.new("Folder")
	folder.Name = "Course_" .. party.id

	local round = {
		party = party,
		slot = slot,
		origin = origin,
		folder = folder,
		sectionStarts = {},
		checkpoints = {},
		connections = {},
		updaters = {},
		players = {},
		sections = {},
		ended = false,
	}

	-- Shuffle the obstacle order: a new route every round.
	local kinds = table.clone(SECTION_KINDS)
	for i = #kinds, 2, -1 do
		local j = rng:NextInteger(1, i)
		kinds[i], kinds[j] = kinds[j], kinds[i]
	end
	while #kinds > SECTION_COUNT do
		table.remove(kinds)
	end
	while #kinds < SECTION_COUNT do
		table.insert(kinds, "stones")
	end

	-- Start pad (section 1's start landing) with spawn spots and a GO barrier.
	local startTop = origin.Y + 0.5
	round.startTop = startTop
	local startCenter = Vector3.new(origin.X + 6, origin.Y, origin.Z + LANE_Z[1])
	local startPad = newPart(folder, "Start", Vector3.new(10, 1, 16), CFrame.new(startCenter), ZONES.cave.rock[2], Enum.Material.Basalt)
	addGlowRim(folder, startPad, ZONES.cave.glow)
	addLabel(startPad, "ESCAPE THE VOLCANO!", Color3.fromRGB(255, 170, 60), 6)
	round.sectionStarts[1] = { part = startPad, top = startTop }
	round.checkpoints[0] = { cframe = facing(Vector3.new(startCenter.X - 2, startTop + 4, startCenter.Z), 1), top = startTop }
	round.startSpots = {}
	for i = 0, 5 do
		local col = i % 3
		local row = math.floor(i / 3)
		local spot = Vector3.new(startCenter.X - 2 + row * 3.5, startTop + 4, startCenter.Z - 4 + col * 4)
		table.insert(round.startSpots, facing(spot, 1))
	end
	local barrier = newPart(
		folder,
		"StartBarrier",
		Vector3.new(1, 14, 16),
		CFrame.new(startCenter.X + 5.5, startTop + 7, startCenter.Z),
		MAGMA_COLOR,
		Enum.Material.ForceField
	)
	barrier.Transparency = 0.4
	round.gate = barrier

	local top = startTop
	local zoneTops = {}
	for index = 1, SECTION_COUNT do
		local kind = kinds[index]
		local ctx = newSection(round, index, kind, top)
		local info = SECTION_INFO[kind]
		local hint = info.hint
		if info.soloHint and #party.members < 2 then
			hint = info.soloHint
		end
		table.insert(round.sections, { name = info.name, hint = hint, zone = ctx.zone.name })

		local endTop = builders[kind](ctx)
		local endCenterX = ctx.innerX + ctx.dir * (SECTION_SPAN + 5)

		if index == SECTION_COUNT then
			-- Final landing is the helipad (its near edge sits where a landing's would).
			local helipad = newPart(
				folder,
				"Helipad",
				Vector3.new(12, 1, 16),
				CFrame.new(endCenterX + ctx.dir, endTop - 0.5, ctx.laneZ),
				Color3.fromRGB(70, 70, 76),
				Enum.Material.Concrete
			)
			for _, mark in ipairs({
				{ size = Vector3.new(6, 0.2, 1), offset = Vector3.new(0, 0.6, 0) },
				{ size = Vector3.new(1, 0.2, 6), offset = Vector3.new(-2.5, 0.6, 0) },
				{ size = Vector3.new(1, 0.2, 6), offset = Vector3.new(2.5, 0.6, 0) },
			}) do
				noCollide(newPart(folder, "HelipadMark", mark.size, CFrame.new(helipad.Position + mark.offset), Color3.fromRGB(255, 220, 80), Enum.Material.Neon))
			end
			round.finishPad = helipad
			round.finishTop = endTop
			buildHelicopter(round, helipad)
			zoneTops[3] = endTop + 12
		else
			local landing = newPart(
				folder,
				"Landing" .. index,
				Vector3.new(10, 1, 10),
				CFrame.new(endCenterX, endTop - 0.5, ctx.laneZ),
				rockColor(ctx.zone),
				Enum.Material.Basalt
			)
			addGlowRim(folder, landing, ctx.zone.glow)

			-- Cross to the other lane: two hops up to the next start landing.
			local nextLaneZ = origin.Z + LANE_Z[(index % 2 == 1) and 2 or 1]
			local towards = (nextLaneZ > ctx.laneZ) and 1 or -1
			local hopTop = endTop
			for hop = 1, 2 do
				hopTop += 1
				local z = ctx.laneZ + towards * (11.5 + (hop - 1) * 9)
				local hopPad = newPart(folder, "Hop", Vector3.new(6, 1, 5), CFrame.new(endCenterX, hopTop - 0.5, z), rockColor(ctx.zone), Enum.Material.Basalt)
				addGlowRim(folder, hopPad, ctx.zone.glow)
			end
			local nextTop = hopTop + 1
			local nextIndex = index + 1
			local isCheckpoint = CHECKPOINT_SECTIONS[nextIndex] == true
			local nextStart = newPart(
				folder,
				isCheckpoint and ("Checkpoint" .. nextIndex) or ("Start" .. nextIndex),
				Vector3.new(10, 1, 10),
				CFrame.new(endCenterX, nextTop - 0.5, nextLaneZ),
				isCheckpoint and CHECKPOINT_COLOR or rockColor(zoneFor(nextIndex)),
				isCheckpoint and Enum.Material.Neon or Enum.Material.Basalt
			)
			round.sectionStarts[nextIndex] = { part = nextStart, top = nextTop }
			if isCheckpoint then
				round.checkpoints[nextIndex] = {
					cframe = facing(Vector3.new(endCenterX, nextTop + 4, nextLaneZ), -ctx.dir),
					top = nextTop,
				}
				addLabel(nextStart, "CHECKPOINT", Color3.fromRGB(120, 255, 140))
			end
			if index == 2 then
				zoneTops[1] = nextTop - 3
			elseif index == 4 then
				zoneTops[2] = nextTop - 3
			end
			top = nextTop
		end
	end

	-- Fallbacks in case SECTION_COUNT was changed to something small.
	local bottomY = origin.Y - 45
	zoneTops[3] = zoneTops[3] or (top + 12)
	zoneTops[1] = zoneTops[1] or (bottomY + (zoneTops[3] - bottomY) / 3)
	zoneTops[2] = zoneTops[2] or (bottomY + (zoneTops[3] - bottomY) * 2 / 3)
	round.rimRocks = buildShell(round, bottomY, zoneTops)

	-- Lava fills the shaft floor and rises.
	local minX, maxX = origin.X + SHAFT_MIN_X, origin.X + SHAFT_MAX_X
	local lavaHeight = 80
	round.lavaHeight = lavaHeight
	round.lavaCenterX = (minX + maxX) / 2
	round.lavaCenterZ = origin.Z
	round.bounds = {
		minX = minX,
		maxX = maxX,
		minZ = origin.Z - SHAFT_HALF_Z,
		maxZ = origin.Z + SHAFT_HALF_Z,
	}
	round.lavaStartTop = startTop - 10
	round.lavaRate = (round.finishTop - round.lavaStartTop) / (LAVA_REACHES_FINISH_AT - LAVA_GRACE_SECONDS)

	local lava = newPart(
		folder,
		"Lava",
		Vector3.new(maxX - minX, lavaHeight, round.bounds.maxZ - round.bounds.minZ),
		CFrame.new(round.lavaCenterX, round.lavaStartTop - lavaHeight / 2, round.lavaCenterZ),
		LAVA_COLOR,
		Enum.Material.Neon
	)
	noCollide(lava)
	lava.Transparency = 0.1
	addLight(lava, MAGMA_COLOR, 60, 3)
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 210, 90), Color3.fromRGB(255, 60, 20))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(2, 4)
	embers.Rate = 40
	embers.Speed = NumberRange.new(5, 10)
	embers.SpreadAngle = Vector2.new(20, 20)
	embers.Parent = lava
	round.lava = lava

	-- Collapsing crater rim: rocks keep breaking off and tumbling into the lava.
	local nextRockfall = 0
	table.insert(round.updaters, function(t)
		if t < nextRockfall or #round.rimRocks == 0 then
			return
		end
		nextRockfall = t + rng:NextNumber(2, 4)
		local rock = round.rimRocks[rng:NextInteger(1, #round.rimRocks)]
		if rock.Parent then
			spawnDebris(rock, folder)
		end
	end)

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
	table.clear(round.updaters)
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
			section = rp.section,
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
		if a.section ~= b.section then
			return a.section > b.section
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
		sectionCount = SECTION_COUNT,
		ropeLength = ROPE_LENGTH,
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
			-- The rope links living teammates in party order.
			local chain, hanging = {}, {}
			for _, member in ipairs(party.members) do
				local mrp = round.players[member]
				if mrp and mrp.status == "alive" then
					table.insert(chain, member.UserId)
					if mrp.hanging then
						table.insert(hanging, member.UserId)
					end
				end
			end
			snapshot.round = {
				phase = party.phase,
				goAt = round.goAt,
				endsAt = round.endsAt,
				resultsEndAt = round.resultsEndAt,
				lavaStartTop = round.lavaStartTop,
				lavaRate = round.lavaRate,
				lavaStartsAt = round.goAt and (round.goAt + LAVA_GRACE_SECONDS) or nil,
				status = rp and rp.status or "spectating",
				section = rp and rp.section or 0,
				checkpoint = rp and rp.checkpoint or 0,
				sections = round.sections,
				chain = chain,
				hanging = hanging,
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
	rp.hanging = false
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
		rp.hanging = false
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
		markDirty()
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
			section = 1,
			onCourse = false,
			safeUntil = 0,
			hanging = false,
		}
		local spot = round.startSpots[((index - 1) % #round.startSpots) + 1]
		local humanoid = getHumanoid(member.Character)
		if humanoid and humanoid.Health > 0 then
			task.spawn(placeOnCourse, member, party, spot)
		end
		-- Dead or missing characters are placed by onCharacterAdded.
	end

	-- Section progress and checkpoints.
	for index, start in pairs(round.sectionStarts) do
		table.insert(
			round.connections,
			start.part.Touched:Connect(function(hit)
				local toucher = playerFromHit(hit)
				if not toucher or not isRunning(round) then
					return
				end
				local rp = round.players[toucher]
				if not rp or rp.status ~= "alive" or not rp.onCourse then
					return
				end
				if index > rp.section then
					rp.section = index
					markDirty()
				end
				local checkpoint = round.checkpoints[index]
				if checkpoint and index > rp.checkpoint and lavaTopAt(round, now()) < checkpoint.top - 1 then
					rp.checkpoint = index
					notify(toucher, "Checkpoint saved!")
					markDirty()
				end
			end)
		)
	end

	-- Helipad: escape!
	table.insert(
		round.connections,
		round.finishPad.Touched:Connect(function(hit)
			local toucher = playerFromHit(hit)
			if not toucher or not isRunning(round) then
				return
			end
			local rp = round.players[toucher]
			if not rp or rp.status ~= "alive" or not rp.onCourse then
				return
			end
			rp.status = "won"
			rp.hanging = false
			rp.section = SECTION_COUNT
			rp.finishTime = now() - round.goAt
			round.finishers = (round.finishers or 0) + 1
			rp.place = round.finishers
			notifyParty(party, string.format("%s reached the helicopter in %.1fs!", rp.name, rp.finishTime))
			markDirty()
			checkRoundEnd(party)
		end)
	)

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
		rp.hanging = false
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

-- The client reports that it started or stopped dangling from the rope.
local function setHanging(player, value)
	if typeof(value) ~= "boolean" then
		return
	end
	local party = playerParty[player]
	local round = party and party.round
	local rp = round and round.players[player]
	if not rp or rp.status ~= "alive" then
		return
	end
	if rp.hanging ~= value then
		rp.hanging = value
		markDirty()
	end
end

-- A teammate taps PULL to haul up someone dangling from the rope.
local function pullTeammate(player, targetUserId)
	if typeof(targetUserId) ~= "number" then
		return
	end
	local party = playerParty[player]
	local round = party and party.round
	if not round or not isRunning(round) then
		return
	end
	local puller = round.players[player]
	local target = Players:GetPlayerByUserId(targetUserId)
	local trp = target and round.players[target]
	if not puller or puller.status ~= "alive" or not trp or trp.status ~= "alive" or not trp.hanging then
		return
	end
	local pullerRoot = getRoot(player.Character)
	local targetRoot = getRoot(target.Character)
	if not pullerRoot or not targetRoot then
		return
	end
	if (pullerRoot.Position - targetRoot.Position).Magnitude > ROPE_LENGTH * 2.5 + 2 then
		return
	end
	stateEvent:FireClient(target, "pulled", player.DisplayName)
end

actionEvent.OnServerEvent:Connect(function(player, action, arg)
	if typeof(action) ~= "string" then
		return
	end
	local clock = os.clock()
	local times = lastActionAt[player]
	if not times then
		times = {}
		lastActionAt[player] = times
	end
	if clock - (times[action] or 0) < (ACTION_COOLDOWN[action] or 0.25) then
		return
	end
	times[action] = clock

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
	elseif action == "hang" then
		setHanging(player, arg)
	elseif action == "pull" then
		pullTeammate(player, arg)
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
		if rp.hanging then
			rp.hanging = false
			markDirty()
		end
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
-- Main loop: countdown, obstacles, lava, timer
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
				notifyParty(party, "GO! Climb out before the lava gets you!")
				markDirty()
			end

			if party.phase == "running" then
				for _, update in ipairs(round.updaters) do
					local ok, err = pcall(update, t)
					if not ok then
						warn("Rising Escape obstacle error: " .. tostring(err))
					end
				end

				local lavaTop = lavaTopAt(round, t)
				round.lava.CFrame = CFrame.new(round.lavaCenterX, lavaTop - round.lavaHeight / 2, round.lavaCenterZ)

				local bounds = round.bounds
				forEachClimber(round, function(_, rp, root, humanoid)
					if t < rp.safeUntil then
						return
					end
					local p = root.Position
					local inside = p.X >= bounds.minX and p.X <= bounds.maxX and p.Z >= bounds.minZ and p.Z <= bounds.maxZ
					if (inside and p.Y - 3 <= lavaTop) or p.Y < round.startTop - 50 then
						humanoid.Health = 0
					end
				end)

				if not round.ended and t >= round.endsAt then
					notifyParty(party, "Time's up!")
					endRound(party)
				end
			end
		end
	end
end)
