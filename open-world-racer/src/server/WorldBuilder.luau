-- Builds the first playable map from WorldMap data: ground, roads, a downtown
-- skyline, street lights, and pads for every place you can drive to.
-- Swap this out for a hand-built map later; keep WorldMap coordinates in sync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local WorldMap = require(Shared.WorldMap)
local WorldClock = require(Shared.WorldClock)

local WorldBuilder = {}

local ROAD_LAYER = { street = 0.2, ramp = 0.22, highway = 0.24, strip = 0.26, track = 0.28 }
local ROAD_COLOR = {
	street = Color3.fromRGB(52, 52, 56),
	ramp = Color3.fromRGB(48, 48, 52),
	highway = Color3.fromRGB(40, 40, 44),
	strip = Color3.fromRGB(34, 34, 36),
	track = Color3.fromRGB(44, 44, 48),
}
local PLACE_COLOR = {
	garage = Color3.fromRGB(255, 170, 40),
	dealership = Color3.fromRGB(80, 170, 255),
	tuning = Color3.fromRGB(255, 70, 90),
	meet = Color3.fromRGB(170, 90, 255),
	photo = Color3.fromRGB(90, 230, 160),
}

local function v3(pt: WorldMap.Point, y: number): Vector3
	return Vector3.new(pt.x, y, pt.z)
end

local function newPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(part :: any)[k] = v
	end
	return part
end

local function buildGround(parent: Instance)
	local tile = 1000
	for x = -2000, 2000, tile do
		for z = -1500, 1000, tile do
			newPart({
				Name = "Ground",
				Size = Vector3.new(tile, 2, tile),
				Position = Vector3.new(x + tile / 2, -1, z + tile / 2),
				Material = Enum.Material.Grass,
				Color = Color3.fromRGB(70, 96, 62),
				Parent = parent,
			})
		end
	end
end

local function buildRoad(road: WorldMap.Road, parent: Instance)
	local a, b = v3(road.a, 0), v3(road.b, 0)
	local length = (b - a).Magnitude + road.width -- overlap corners
	local top = ROAD_LAYER[road.kind] or 0.2
	newPart({
		Name = `Road_{road.kind}`,
		Size = Vector3.new(road.width, 0.4, length),
		CFrame = CFrame.lookAt((a + b) / 2, b) + Vector3.new(0, top - 0.2, 0),
		Material = Enum.Material.Asphalt,
		Color = ROAD_COLOR[road.kind] or ROAD_COLOR.street,
		Parent = parent,
	})
end

local function buildLights(parent: Instance)
	local pts = WorldMap.HighwayPoints
	for i = 1, #pts do
		local a, b = v3(pts[i], 0), v3(pts[i % #pts + 1], 0)
		local dir = (b - a).Unit
		local side = dir:Cross(Vector3.yAxis) * 28
		local steps = math.floor((b - a).Magnitude / 160)
		for s = 1, steps do
			local base = a + dir * (s * 160) + side
			local pole = newPart({
				Name = "StreetLight",
				Size = Vector3.new(0.8, 18, 0.8),
				Position = base + Vector3.new(0, 9, 0),
				Color = Color3.fromRGB(90, 90, 95),
				Parent = parent,
			})
			local lamp = newPart({
				Name = "Lamp",
				Size = Vector3.new(2, 0.6, 2),
				Position = base + Vector3.new(0, 18.2, 0),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 214, 150),
				Parent = pole,
			})
			local light = Instance.new("PointLight")
			light.Range = 50
			light.Brightness = 1.5
			light.Color = lamp.Color
			light.Parent = lamp
		end
	end
end

-- Returns true if something important sits inside this downtown block.
local function blockHasLandmark(minX: number, minZ: number, size: number): boolean
	local function inside(pt: WorldMap.Point): boolean
		return pt.x >= minX and pt.x <= minX + size and pt.z >= minZ and pt.z <= minZ + size
	end
	for _, place in WorldMap.Places do
		if inside(place.pos) then
			return true
		end
	end
	for _, d in WorldMap.Discoveries do
		if inside(d.pos) then
			return true
		end
	end
	return false
end

local function buildSkyline(parent: Instance)
	local grid = WorldMap.Grid
	local margin = 20
	for x = grid.min, grid.max - grid.step, grid.step do
		for z = grid.min, grid.max - grid.step, grid.step do
			local minX, minZ = x + margin, z + margin
			local size = grid.step - margin * 2
			if not blockHasLandmark(x, z, grid.step) then
				local seed = WorldClock.hash(x * 7919 + z)
				local height = 40 + seed % 160
				local tint = 60 + seed % 50
				newPart({
					Name = "Building",
					Size = Vector3.new(size, height, size),
					Position = Vector3.new(minX + size / 2, height / 2, minZ + size / 2),
					Material = Enum.Material.Concrete,
					Color = Color3.fromRGB(tint, tint, tint + 12),
					Parent = parent,
				})
				-- Lit windows band so the city reads at night.
				newPart({
					Name = "Windows",
					Size = Vector3.new(size + 0.4, 3, size + 0.4),
					Position = Vector3.new(minX + size / 2, height * 0.6, minZ + size / 2),
					Material = Enum.Material.Neon,
					Color = Color3.fromRGB(255, 230, 170),
					Transparency = 0.35,
					CanCollide = false,
					Parent = parent,
				})
			end
		end
	end
end

local function buildPlace(place: WorldMap.Place, parent: Instance)
	local color = PLACE_COLOR[place.kind] or Color3.new(1, 1, 1)
	local pad = newPart({
		Name = `Place_{place.id}`,
		Size = Vector3.new(50, 0.3, 50),
		Position = v3(place.pos, 0.3),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(62, 62, 66),
		Parent = parent,
	})
	pad:SetAttribute("PlaceId", place.id)
	pad:SetAttribute("PlaceKind", place.kind)

	local edge = newPart({
		Name = "Edge",
		Size = Vector3.new(52, 0.2, 52),
		Position = v3(place.pos, 0.2),
		Material = Enum.Material.Neon,
		Color = color,
		Parent = pad,
	})
	edge.CanCollide = false

	if place.kind ~= "photo" and place.kind ~= "meet" then
		-- A simple storefront behind the pad.
		newPart({
			Name = "Building",
			Size = Vector3.new(50, 22, 14),
			Position = v3(place.pos, 11) + Vector3.new(0, 0, 32),
			Material = Enum.Material.Brick,
			Color = color:Lerp(Color3.new(0.2, 0.2, 0.22), 0.6),
			Parent = pad,
		})
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = if place.kind == "garage"
			then "Open Garage"
			elseif place.kind == "dealership" then "Browse Cars"
			else "Tune Car"
		prompt.ObjectText = place.name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 45
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0.2
		prompt.Parent = pad
	end

	if place.kind == "garage" then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "GarageSpawn"
		spawn.Anchored = true
		spawn.Size = Vector3.new(8, 0.4, 8)
		spawn.Position = v3(place.pos, 0.6) + Vector3.new(0, 0, 18)
		spawn.Transparency = 1
		spawn.Duration = 0
		spawn.Neutral = true
		spawn.Parent = pad
	end
end

local function buildDragStrip(parent: Instance)
	local ev = WorldMap.Events.westsideDrag
	for _, pt in { ev.start, ev.checkpoints[#ev.checkpoints] } do
		newPart({
			Name = "StripLine",
			Size = Vector3.new(40, 0.1, 2),
			Position = v3(pt, 0.33),
			Material = Enum.Material.Neon,
			Color = Color3.new(1, 1, 1),
			CanCollide = false,
			Parent = parent,
		})
	end
end

local function buildGrandstand(parent: Instance)
	-- Crowd seating beside the Harbor Ring start/finish.
	newPart({
		Name = "Grandstand",
		Size = Vector3.new(20, 14, 120),
		CFrame = CFrame.new(1250, 7, -40) * CFrame.Angles(0, 0, math.rad(-12)),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(120, 120, 130),
		Parent = parent,
	})
end

function WorldBuilder.build(): Folder
	local world = Instance.new("Folder")
	world.Name = "World"

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = world
	buildGround(ground)

	local roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = world
	for _, road in WorldMap.Roads do
		buildRoad(road, roads)
	end

	local city = Instance.new("Folder")
	city.Name = "City"
	city.Parent = world
	buildSkyline(city)
	buildLights(city)
	buildDragStrip(city)
	buildGrandstand(city)

	local places = Instance.new("Folder")
	places.Name = "Places"
	places.Parent = world
	for _, place in WorldMap.Places do
		buildPlace(place, places)
	end

	-- Remove the template baseplate if the place file still has one.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	world.Parent = Workspace
	return world
end

return WorldBuilder
