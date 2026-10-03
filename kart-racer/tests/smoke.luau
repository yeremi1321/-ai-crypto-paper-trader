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
		local roads = 0
		for _, child in folder:GetChildren() do
			if child.Name == "Road" then
				roads += 1
			end
		end
		assert(roads == #track.points, `{def.id}: {roads} road parts for {#track.points} points`)
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

check("LobbyBuilder builds the Kart Carnival", function()
	local LobbyBuilder = load(server.LobbyBuilder)
	local handles = LobbyBuilder.build()
	local lobby = game:GetService("Workspace"):FindFirstChild("Lobby")
	assert(lobby, "no lobby")
	assert(game:GetService("Workspace"):FindFirstChild("PracticeTrack"), "no practice loop")
	assert(#handles.collectibles == 6, "tokens")
	handles.setStatus("TEST", "body")
	handles.setVoteOption(1, { id = "sunny", name = "Sunny Loop", icon = "x", difficulty = "Easy", feature = "f", votes = 2 })
	handles.setVoteOption(2, nil)
	handles.setPodium({ { name = "A", kartId = "classic", look = { body = "classic", main = 1, accent = 2 } }, { name = "B" } })
	handles.setKartDisplay(1, "Tester", "zippy", { body = "racer", main = 3, accent = 4 })
	handles.setKartDisplay(1, nil)
	handles.setSpectator("LIVE", "1. A")
	print(`     {#lobby:GetDescendants()} lobby objects`)
end)

print(if failures == 0 then "smoke ok" else `{failures} smoke failure(s)`)
if failures > 0 then
	process.exit(1)
end
