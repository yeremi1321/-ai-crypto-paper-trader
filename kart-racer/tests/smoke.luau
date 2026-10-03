-- Builds every track, kart and item box inside Lune's Roblox DOM. Lune rejects
-- unknown properties, classes and enums, so this catches API typos outside
-- Studio. It cannot simulate physics, signals or services.
--   lune run tests/smoke
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Instance = roblox.Instance
local game = Instance.new("DataModel")

local sources: { [any]: string } = {} -- ModuleScript -> file path
local cache: { [any]: any } = {}

local function mount(dir: string, parent: any)
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		local moduleName = string.match(name, "^(.-)%.luau$")
		if moduleName and not string.find(moduleName, "%.") then
			local m = Instance.new("ModuleScript")
			m.Name = moduleName
			m.Parent = parent
			sources[m] = path
		end
	end
end

local shared = Instance.new("Folder")
shared.Name = "Shared"
shared.Parent = game:GetService("ReplicatedStorage")
mount("src/shared", shared)

local common = Instance.new("Folder")
common.Name = "Common"
common.Parent = game:GetService("ReplicatedStorage")
mount("src/common", common)

local server = Instance.new("Folder")
server.Name = "Server"
server.Parent = game:GetService("ServerScriptService")
mount("src/server", server)

local load
local function makeRequire(script: any)
	return function(target: any)
		if type(target) == "string" then
			-- String requires ("./X") resolve to siblings.
			local name = assert(string.match(target, "^%./(.+)$"), `unsupported require {target}`)
			target = script.Parent:FindFirstChild(name)
			assert(target, `missing module {name}`)
		end
		return load(target)
	end
end

load = function(module: any)
	if cache[module] ~= nil then
		return cache[module]
	end
	local path = assert(sources[module], `no source for {module:GetFullName()}`)
	local env = setmetatable({
		game = game,
		workspace = game:GetService("Workspace"),
		script = module,
		require = nil :: any,
		Instance = Instance,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberRange = roblox.NumberRange,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		PhysicalProperties = roblox.PhysicalProperties,
		task = task,
	}, { __index = _G })
	env.require = makeRequire(module)
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = env })
	local result = chunk()
	cache[module] = result
	return result
end

local failures = 0
local function check(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		print(`ok   {name}`)
	else
		failures += 1
		print(`FAIL {name}\n  {err}`)
	end
end

check("TrackBuilder builds every track", function()
	local Tracks = load(shared.Tracks)
	local TrackBuilder = load(server.TrackBuilder)
	for _, def in Tracks.List do
		local folder, track = TrackBuilder.build(def.id)
		local TerrainBuilder = load(server.TerrainBuilder)
		local theme = Tracks.Themes[def.theme]
		if theme.terrain then
			-- Lune has no Terrain, but the plan's fills are still counted.
			local counts = TerrainBuilder.lastCounts
			assert(counts.slab == 1, `{def.id}: terrain ground`)
			assert(counts.mountain + counts.hill + counts.lake + counts.mesa > 0, `{def.id}: no landscape`)
			assert(not folder:FindFirstChild("Ground"), `{def.id}: part floor under terrain`)
		else
			assert(folder:FindFirstChild("Ground"), `{def.id}: floor`)
		end
		if def.id == "emberfort" then
			assert(folder:FindFirstChild("Citadel"), "fortress scenery")
			local towers, canals = 0, 0
			for _, part in folder.Citadel:GetDescendants() do
				if part.Name == "GateTower" then towers += 1 end
				if part.Name == "LavaCanal" then canals += 1 end
			end
			assert(towers == 8 and canals == 80, "fortress gates and lava channels")
		end
		-- Road: two triangles (four wedges) per segment, solid and collidable.
		local surface = folder:FindFirstChild("RoadSurface")
		local wedges = #surface:GetChildren()
		assert(wedges >= #track.points * 4 - 4 and wedges <= #track.points * 4, `{def.id}: {wedges} road wedges for {#track.points} points`)
		for _, wedge in surface:GetChildren() do
			assert(wedge:IsA("WedgePart") and wedge.CanCollide and wedge:GetAttribute("Surface") == "road", "road collision")
			assert(math.abs(wedge.Size.X - 4) < 1e-6, "road slab thickness")
		end
		local walls = folder:FindFirstChild("Barriers")
		local wallCount = if walls then #walls:GetChildren() else 0
		if def.walls ~= false then
			assert(wallCount >= #track.points, `{def.id}: barriers missing ({wallCount})`)
		end
		local curbs, lines = 0, 0
		for _, m in folder.Markings:GetChildren() do
			if m.Name == "Curb" then curbs += 1 end
			if m.Name == "EdgeLine" then lines += 1 end
		end
		assert(curbs > 0 and lines > 0, `{def.id}: curbs {curbs}, lines {lines}`)
		-- Verges on both sides of every segment cover the terrain near the road.
		local verges = folder:FindFirstChild("Shoulders")
		if def.walls ~= false then
			assert(verges and #verges:GetChildren() >= #track.points * 8 - 8, `{def.id}: verges missing`)
		end
		local total = #folder:GetDescendants()
		local scenery = folder:FindFirstChild("Scenery")
		assert(scenery and #scenery:GetChildren() > 300, `{def.id}: not enough scenery`)
		print(`     {def.name}: {total} objects, {math.floor(track.length)} studs a lap`)
	end
end)

check("KartRig builds every kart class and body design", function()
	local Karts = load(shared.Karts)
	local KartBodies = load(shared.KartBodies)
	local KartRig = load(common.KartRig)
	for i, body in KartBodies.List do
		local def = Karts.List[(i - 1) % #Karts.List + 1]
		local Cosmetics = load(shared.Cosmetics)
		local look = {
			body = body.id,
			main = i,
			accent = 13 - i,
			wheels = Cosmetics.Wheels[(i - 1) % #Cosmetics.Wheels + 1].id,
			sticker = Cosmetics.Stickers[(i - 1) % #Cosmetics.Stickers + 1].id,
			trail = Cosmetics.Trails[(i - 1) % #Cosmetics.Trails + 1].id,
			plate = "ZOOM",
		}
		local kart = KartRig.build(def.id, "Tester", roblox.CFrame.new(0, 0, 0), game:GetService("Workspace"), look)
		assert(kart:GetAttribute("Body") == body.id, "body attribute")
		assert(kart:FindFirstChild("WheelRL") and kart:FindFirstChild("WheelRR"), `{body.id}: rear wheels`)
		assert(kart.PrimaryPart and kart.PrimaryPart.Name == "Root", "root")
		assert(kart.PrimaryPart:FindFirstChild("Drive"), "LinearVelocity")
		assert(kart.PrimaryPart:FindFirstChild("Align"), "AlignOrientation")
		assert(kart:FindFirstChild("DriverSeat"), "seat")
		KartRig.setEffects(kart, 2, true)
		kart:Destroy()
	end
end)

check("ItemService: boxes, and every item used in a fake race", function()
	local Track = load(shared.Track)
	local Tracks = load(shared.Tracks)
	local Items = load(shared.Items)
	local KartPhysics = load(shared.KartPhysics)
	local KartRig = load(common.KartRig)
	local ItemService = load(server.ItemService)
	local fakeTime = 0
	ItemService.clock = function()
		return fakeTime
	end
	local track = Track.build(Tracks.get("toyroom"))
	ItemService.setup(track)
	local items = game:GetService("Workspace"):FindFirstChild("Items")
	local boxes = 0
	for _, child in items:GetChildren() do
		if child:GetAttribute("ItemBox") then
			boxes += 1
		end
	end
	assert(boxes == #Track.itemBoxes(track), `item boxes: {boxes}`)

	-- Two karts driving the lap, one behind the other.
	local racers = {}
	for i = 1, 2 do
		local d = 200 + i * 20
		local p = Track.spot(track, d, 0)
		local _, tan = Track.at(track, d)
		local yaw = math.atan2(-tan.x, -tan.z)
		local model = KartRig.build("classic", `R{i}`, roblox.CFrame.new(p.x, p.y, p.z) * roblox.CFrame.Angles(0, yaw, 0), game:GetService("Workspace"))
		local progress = Track.newProgress(track, d)
		table.insert(racers, {
			model = model, state = KartPhysics.newState(yaw), progress = progress,
			score = d, place = 3 - i, item = nil, uses = 0, itemReadyAt = 0, cpuUseAt = math.huge,
		})
	end
	local log = { hit = 0, warn = 0, boost = 0, shield = 0 }
	local effects = {
		hit = function() log.hit += 1 return true end,
		warn = function() log.warn += 1 end,
		boost = function() log.boost += 1 end,
		shield = function() log.shield += 1 end,
		itemChanged = function() end,
	}
	-- racers[1] is behind racers[2]; fire everything from the back.
	for _, id in Items.Order do
		local r = racers[1]
		r.item, r.uses, r.itemReadyAt = id, 1, 0
		ItemService.use(track, racers, r, effects, false)
		assert(r.item == nil, `{id} not consumed`)
		for _ = 1, 50 do
			fakeTime += 0.05
			ItemService.tick(track, racers, 0.05, effects)
		end
	end
	assert(log.boost >= 1 and log.shield >= 1, "soda/shield effects")
	assert(log.hit >= 1, "the rocket should hit the kart ahead")
	assert(log.warn >= 1, "the kart ahead should be warned about the rocket")
	print(`     items: {log.hit} hits, {log.warn} warnings`)
	ItemService.clear()
	for _, r in racers do
		r.model:Destroy()
	end
end)

check("LobbyBuilder builds Kart HQ", function()
	local LobbyBuilder = load(server.LobbyBuilder)
	local handles = LobbyBuilder.build()
	local lobby = game:GetService("Workspace"):FindFirstChild("Lobby")
	assert(lobby, "no lobby")
	assert(not game:GetService("Workspace"):FindFirstChild("PracticeTrack"), "practice removed")
	assert(#handles.collectibles == 6, "tokens")
	handles.setPodium({ { name = "A", kartId = "classic", look = { body = "classic", main = 1, accent = 2 } }, { name = "B" } })
	handles.setKartDisplay(1, "Tester", "zippy", { body = "racer", main = 3, accent = 4 })
	handles.setKartDisplay(1, nil)
	assert(lobby.Chamber:FindFirstChild("VoteScreen"), "vote screen")
	assert(lobby.Chamber:FindFirstChild("StatusBoard"), "status board")
	for i = 1, 4 do assert(lobby.Chamber:FindFirstChild(`PadSign{i}`), "pad sign") end
	-- Realistic finish and the window view.
	local materials = {}
	for _, p in lobby:GetDescendants() do
		if p:IsA("BasePart") then
			materials[p.Material.Name] = (materials[p.Material.Name] or 0) + 1
		end
	end
	assert((materials.Concrete or 0) > 20 and (materials.Marble or 0) > 0 and (materials.Metal or 0) > 10, "lobby materials")
	assert(lobby.Chamber:FindFirstChild("WindowGlass"), "panoramic window")
	local vista = game:GetService("Workspace"):FindFirstChild("LobbyVista")
	assert(vista and #vista:GetChildren() > 100, "pines outside the window")
	assert(not lobby.Rooms:FindFirstChild("lounge") and not lobby.Rooms:FindFirstChild("practice"), "removed rooms")
	for _, key in { "garagePrompt" } do
		assert(handles[key]:IsA("ProximityPrompt"), key)
	end
	for _, lit in { true, false } do
		handles.setDeparture(lit)
		for _, door in lobby.Departure:GetChildren() do
			if door:GetAttribute("Departure") then
				assert(door:GetAttribute("Lit") == lit, "departure authorization")
				assert(door:GetAttribute("SlidingDoor") and door:GetAttribute("Width"), "door metadata")
			end
		end
	end
	-- A detached character exercises the safe early return (Lune has no signals/particles).
	handles.celebrate(1, Instance.new("Model"))
	print(`     {#lobby:GetDescendants()} lobby objects`)
end)

-- Client display logic with real DOM instances and explicit service/preview
-- doubles: Lune cannot run Roblox thumbnail services or render ViewportFrames.
check("LobbyScreens: phases, headshots, countdown and local doors", function()
	local ws = game:GetService("Workspace")
	local lobby = ws.Lobby
	local gui = Instance.new("Folder")
	local rootPosition = roblox.Vector3.new(0, 3, 5000)
	local fakeRoot = {}
	local character = { FindFirstChild = function(_, name)
		if name == "HumanoidRootPart" then
			fakeRoot.Position = rootPosition
			return fakeRoot
		end
		return nil
	end }
	local player = { Character = character, WaitForChild = function() return gui end }
	local clock = 120
	local workspaceProxy = {
		FindFirstChild = function(_, name) return ws:FindFirstChild(name) end,
		GetServerTimeNow = function() return clock end,
	}
	local thumbnails, previewSteps = 0, 0
	local fakeUI = { Colors = {
		panel = roblox.Color3.fromRGB(20, 25, 40), panelLight = roblox.Color3.fromRGB(45, 50, 70),
		text = roblox.Color3.new(1, 1, 1), purple = roblox.Color3.fromRGB(150, 100, 240),
	} }
	local function element(class, parent, props)
		local instance = Instance.new(class)
		for key, value in props do instance[key] = value end
		instance.Parent = parent
		return instance
	end
	fakeUI.label = function(parent, props) return element("TextLabel", parent, props) end
	fakeUI.panel = function(parent, props) return element("Frame", parent, props) end
	fakeUI.headshot = function(id, big)
		assert(big == true, "wall headshots must be sharp")
		thumbnails += 1
		return if thumbnails > 2 then `rbxassetid://{id}` else ""
	end
	local fakePreview = { new = function(parent, id)
		local frame = Instance.new("ViewportFrame")
		frame.Name = "TrackPreview"
		frame.Parent = parent
		return { frame = frame, trackId = id,
			step = function() previewSteps += 1 end,
			destroy = function() frame:Destroy() end,
		}
	end }
	local module = luau.load(fs.readFile("src/client/LobbyScreens.luau"), {
		environment = setmetatable({
			game = { GetService = function(_, service)
				if service == "Players" then return { LocalPlayer = player } end
				if service == "Workspace" then return workspaceProxy end
				if service == "ReplicatedStorage" then
					return { WaitForChild = function() return {
						WaitForChild = function(_, name) return shared:FindFirstChild(name) end,
					} end }
				end
				return game:GetService(service)
			end },
			script = { Parent = { UI = "UI", TrackPreview = "TrackPreview" } },
			require = function(target)
				if target == "UI" then return fakeUI end
				if target == "TrackPreview" then return fakePreview end
				return load(target)
			end,
			Instance = Instance, Vector2 = roblox.Vector2, Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame, Color3 = roblox.Color3, UDim2 = roblox.UDim2, Enum = roblox.Enum,
		}, { __index = _G }),
	})()
	local function texts(surface)
		local text = {}
		for _, child in gui:FindFirstChild(`LobbyScreen_{surface}`):GetDescendants() do
			if child:IsA("TextLabel") then table.insert(text, child.Text) end
		end
		return table.concat(text, " | ")
	end
	local s = { phase = "lobby", players = { { ready = true } }, options = {}, deadline = 125 }
	module.setState(s) -- before world discovery must not lose the snapshot
	module.step(0.1)
	assert(#gui:GetChildren() == 6, "six chamber screens")
	for _, screen in gui:GetChildren() do
		assert(screen:IsA("SurfaceGui") and screen.Adornee:IsA("BasePart"), "local adornee")
		assert(screen.ResetOnSpawn == false, "screens survive respawn")
	end
	assert(string.find(texts("vote"), "Step onto a pad to race", 1, true), "lobby instruction")
	assert(string.find(texts("status"), "5s", 1, true), "server deadline countdown")
	clock = 126
	module.step(0.1)
	assert(string.find(texts("status"), "0s", 1, true), "countdown clamps to zero")
	s.phase = "voting"
	s.options = {
		{ id = "toyroom", name = "Midnight Toy Room", votes = 1, voters = { 11 } },
		{ id = "kitchen", name = "Kitchen Chaos", votes = 0, voters = {} },
		{ id = "backyard", name = "Backyard Bug Rally", votes = 1, voters = { 22 } },
	}
	s.randomVoters = { 22 } -- counted in track tally too, but only once on status
	module.setState(s)
	clock += 1
	module.step(0.1)
	assert(string.find(texts("vote"), "RANDOM", 1, true), "random column")
	assert(string.find(texts("pad4"), "RANDOM", 1, true), "random pad")
	assert(string.find(texts("status"), "1 ready · 2 voted", 1, true), "distinct voters")
	assert(thumbnails > 2 and previewSteps > 0, "previews and cached thumbnail retry")
	for _, child in gui.LobbyScreen_vote:GetDescendants() do
		if child.Name == "Voter" then assert(child.Image ~= "", "thumbnail eventually loads") end
	end
	s.phase, s.winner = "announce", "kitchen"
	module.setState(s)
	assert(string.find(texts("vote"), "Kitchen Chaos", 1, true), "winner reveal")
	s.phase = "racing"
	s.spectate = { trackName = "Kitchen Chaos", rows = { { name = "Leader", finished = true }, { name = "CPU", isCpu = true } } }
	module.setState(s)
	assert(string.find(texts("vote"), "1. Leader", 1, true), "wall standings")
	assert(not gui:FindFirstChild("LobbyScreen_lounge"), "no viewing screen")
	s.phase, s.spectate = "results", nil
	s.lastResults = { { name = "First" }, { name = "Second" }, { name = "Third" }, { name = "Fourth" } }
	module.setState(s)
	assert(string.find(texts("vote"), "3. Third", 1, true), "podium top three")
	assert(not string.find(texts("vote"), "Fourth", 1, true), "results limited to three")
	local checked = 0
	for _, door in lobby:GetDescendants() do
		if not door:IsA("Model") or not door:GetAttribute("SlidingDoor") then continue end
		local panel = door.Panel1
		local closed = panel.CFrame
		rootPosition = (panel.CFrame.Position + door.Panel2.CFrame.Position) / 2 - roblox.Vector3.new(0, panel.Size.Y / 2 - 3, 0)
		local departure = door:GetAttribute("Departure")
		if departure then
			module.step(1)
			assert((panel.CFrame.Position - closed.Position).Magnitude < 0.001, "unlit departure stays shut")
			door:SetAttribute("Lit", true)
		end
		module.step(1)
		local target = closed * roblox.CFrame.new(panel:GetAttribute("Side") * (door:GetAttribute("Width") / 2 - 0.8), 0, 0)
		assert((panel.CFrame.Position - target.Position).Magnitude < 0.02, "door moves on local X")
		if departure then
			door:SetAttribute("Lit", false)
			module.step(1)
			assert((panel.CFrame.Position - closed.Position).Magnitude < 0.02, "authorization revoked closes door")
		end
		rootPosition = roblox.Vector3.new(0, 3, 5000)
		module.step(1)
		assert((panel.CFrame.Position - closed.Position).Magnitude < 0.02, "door returns to stored position")
		checked += 1
	end
	assert(checked == 5, "room and departure doors exercised")
	gui:Destroy()
end)

print(if failures == 0 then "smoke ok" else `{failures} smoke failure(s)`)
if failures > 0 then
	process.exit(1)
end
