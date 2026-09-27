-- Builds the real map and every car inside Lune's Roblox DOM. Lune rejects
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

check("WorldBuilder builds the map", function()
	local world = load(server.WorldBuilder).build()
	local parts = 0
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	assert(parts > 100, `only {parts} parts`)
	assert(world:FindFirstChild("Places"):FindFirstChild("Place_garage"), "garage pad missing")
	print(`     {parts} parts`)
end)

check("VehicleFactory builds every car with every part", function()
	local CarCatalog = load(shared.CarCatalog)
	local PlayerProfile = load(shared.PlayerProfile)
	local VehicleFactory = load(server.VehicleFactory)
	local allParts = {}
	for id in CarCatalog.Parts do
		table.insert(allParts, id)
	end
	for id in CarCatalog.Cars do
		for _, parts in { {}, allParts } do
			local owned = { carId = id, parts = parts, paint = { 10, 20, 30 }, builds = {} }
			local car = VehicleFactory.build(owned, 1, roblox.CFrame.new(0, 0.5, 0), game:GetService("Workspace"))
			assert(car.PrimaryPart, "no primary part")
			assert(car:FindFirstChild("DriveSeat"), "no seat")
			local motors, steer = 0, 0
			for _, d in car:GetDescendants() do
				if d.ClassName == "HingeConstraint" then
					if d.Name == "Axle" then
						motors += 1
						assert(d.Attachment0 and d.Attachment1, "axle attachments")
					elseif d.Name == "Steer" then
						steer += 1
					end
				end
			end
			assert(motors == 4 and steer == 2, `{id}: {motors} axles, {steer} steering hinges`)
			assert(car:GetAttribute("Class"), "class attribute")
			car:Destroy()
		end
	end
	local _ = PlayerProfile
end)

print(if failures == 0 then "smoke ok" else `{failures} smoke failure(s)`)
if failures > 0 then
	process.exit(1)
end
