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
		print(`     {def.name}: {#folder:GetChildren()} parts, {math.floor(track.length)} studs a lap`)
	end
end)

check("KartRig builds every kart", function()
	local Karts = load(shared.Karts)
	local KartRig = load(common.KartRig)
	for _, def in Karts.List do
		local kart = KartRig.build(def.id, "Tester", roblox.CFrame.new(0, 0, 0), game:GetService("Workspace"))
		assert(kart.PrimaryPart and kart.PrimaryPart.Name == "Root", "root")
		assert(kart.PrimaryPart:FindFirstChild("Drive"), "LinearVelocity")
		assert(kart.PrimaryPart:FindFirstChild("Align"), "AlignOrientation")
		assert(kart:FindFirstChild("DriverSeat"), "seat")
		KartRig.setEffects(kart, 2, true)
		kart:Destroy()
	end
end)

check("ItemService places item boxes", function()
	local Track = load(shared.Track)
	local Tracks = load(shared.Tracks)
	local ItemService = load(server.ItemService)
	local track = Track.build(Tracks.List[1])
	ItemService.setup(track)
	local items = game:GetService("Workspace"):FindFirstChild("Items")
	assert(items and #items:GetChildren() == #Track.itemBoxes(track), "item boxes")
	ItemService.clear()
end)

print(if failures == 0 then "smoke ok" else `{failures} smoke failure(s)`)
if failures > 0 then
	process.exit(1)
end
