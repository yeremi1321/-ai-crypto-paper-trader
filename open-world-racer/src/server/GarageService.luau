-- Owns each player's current car and every garage / shop action.
-- Shops are physical: actions only work while you are parked at the matching
-- place, so buying a car means driving to the dealership.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CarCatalog = require(Shared.CarCatalog)
local Performance = require(Shared.Performance)
local PlayerProfile = require(Shared.PlayerProfile)
local Progression = require(Shared.Progression)
local WorldMap = require(Shared.WorldMap)

local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Net)
local VehicleFactory = require(script.Parent.VehicleFactory)

local GarageService = {}

local SHOP_RANGE = 70
local carsFolder = Instance.new("Folder")
carsFolder.Name = "Cars"
carsFolder.Parent = Workspace

local cars: { [Player]: Model } = {}
local busy: { [Player]: boolean } = {} -- set while a player is racing

-- Which place kinds allow which actions.
local ACTION_PLACES: { [string]: { string } } = {
	buyCar = { "dealership" },
	buyBay = { "garage" },
	select = { "garage" },
	buyPart = { "tuning" },
	install = { "tuning", "garage" },
	remove = { "tuning", "garage" },
	saveBuild = { "tuning", "garage" },
	loadBuild = { "tuning", "garage" },
	paint = { "tuning", "garage" },
}

local function districtNames(): { [string]: string }
	local names = {}
	for id, d in WorldMap.Districts do
		names[id] = d.name
	end
	return names
end

function GarageService.getCar(player: Player): Model?
	local car = cars[player]
	if car and car.Parent then
		return car
	end
	return nil
end

-- Position used for proximity checks: the car if driving, else the character.
function GarageService.position(player: Player): Vector3?
	local car = GarageService.getCar(player)
	local seat = car and car:FindFirstChild("DriveSeat") :: VehicleSeat?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if seat and seat.Occupant and seat.Occupant.Parent == character and car.PrimaryPart then
		return car.PrimaryPart.Position
	end
	return root and root.Position
end

function GarageService.isDriving(player: Player): boolean
	local car = GarageService.getCar(player)
	local seat = car and car:FindFirstChild("DriveSeat") :: VehicleSeat?
	return seat ~= nil and seat.Occupant ~= nil and seat.Occupant.Parent == player.Character
end

function GarageService.setBusy(player: Player, value: boolean)
	busy[player] = value or nil
end

function GarageService.nearPlaceKind(player: Player, kinds: { string }): boolean
	local pos = GarageService.position(player)
	if not pos then
		return false
	end
	for _, place in WorldMap.Places do
		if table.find(kinds, place.kind) then
			local d = Vector3.new(place.pos.x, pos.Y, place.pos.z) - pos
			if d.Magnitude <= SHOP_RANGE then
				return true
			end
		end
	end
	return false
end

function GarageService.pushProfile(player: Player)
	local p = DataService.get(player)
	if not p then
		return
	end
	local carList = {}
	for i, owned in p.cars do
		local def = CarCatalog.getCar(owned.carId)
		local rating, class = Performance.forBuild(owned.carId, owned.parts)
		local builds = {}
		for slot in owned.builds do
			table.insert(builds, slot)
		end
		carList[i] = {
			carId = owned.carId,
			name = def and def.name or owned.carId,
			parts = owned.parts,
			paint = owned.paint,
			rating = rating,
			class = class,
			builds = builds,
		}
	end
	local rep = {}
	for id, d in WorldMap.Districts do
		local value = p.rep[id] or 0
		rep[id] = { name = d.name, rep = value, tier = Progression.tierFor(value) }
	end
	Net.ProfileUpdated:FireClient(player, {
		cash = p.cash,
		title = Progression.title(p.rep, districtNames()),
		rep = rep,
		cars = carList,
		activeCar = p.activeCar,
		inventory = p.partsInventory,
		garageBays = p.garageBays,
		nextBayPrice = PlayerProfile.BayPrices[p.garageBays + 1],
		stats = p.stats,
	})
	player:SetAttribute("StreetTitle", Progression.title(p.rep, districtNames()))
end

-- Cars come out onto the street in front of the garage, one parking slot
-- per spawn so players joining together don't land on top of each other.
local GARAGE_SLOTS = 6
local nextSlot = 0
local function garageSpawnCFrame(): CFrame
	local g = WorldMap.Places.garage.pos
	nextSlot = nextSlot % GARAGE_SLOTS + 1
	local x = g.x - 40 + (nextSlot - 1) * 16
	local pos = Vector3.new(x, 0.5, g.z - 20)
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1))
end

function GarageService.despawn(player: Player)
	local car = cars[player]
	if car then
		car:Destroy()
		cars[player] = nil
	end
end

function GarageService.spawnCar(player: Player, at: CFrame?): Model?
	local p = DataService.get(player)
	if not p then
		return nil
	end
	GarageService.despawn(player)
	local owned = p.cars[p.activeCar]
	local car = VehicleFactory.build(owned, player.UserId, at or garageSpawnCFrame(), carsFolder)
	cars[player] = car

	local seat = car:FindFirstChild("DriveSeat") :: VehicleSeat
	local prompt = seat:FindFirstChild("DrivePrompt") :: ProximityPrompt
	prompt.Triggered:Connect(function(who)
		local humanoid = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
		if who == player and humanoid and not seat.Occupant then
			seat:Sit(humanoid)
		end
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		local driver = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
		if occupant and driver ~= player then
			-- Only the owner drives; passengers can come later with extra seats.
			occupant.Sit = false
			return
		end
		prompt.Enabled = occupant == nil
		if car.PrimaryPart and car.PrimaryPart:CanSetNetworkOwnership() then
			car.PrimaryPart:SetNetworkOwner(if driver then driver else nil)
		end
	end)
	return car
end

-- Rebuilds the car in place (after tuning or paint) keeping the driver seated.
local function refreshCar(player: Player)
	local car = GarageService.getCar(player)
	local wasDriving = GarageService.isDriving(player)
	local at = if car and car.PrimaryPart then car.PrimaryPart.CFrame - Vector3.new(0, 1.8, 0) else nil
	local newCar = GarageService.spawnCar(player, at)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if wasDriving and newCar and humanoid then
		(newCar:FindFirstChild("DriveSeat") :: VehicleSeat):Sit(humanoid)
	end
end

-- Puts a stuck or flipped car back on its wheels where it is; with no car
-- (or when parked at the garage), brings the active car out of the garage.
function GarageService.resetCar(player: Player)
	local car = GarageService.getCar(player)
	if not car or not car.PrimaryPart or (not busy[player] and GarageService.nearPlaceKind(player, { "garage" })) then
		GarageService.spawnCar(player)
		return
	end
	local cf = car.PrimaryPart.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.zAxis
	end
	local pos = cf.Position + Vector3.new(0, 4, 0)
	car:PivotTo(CFrame.lookAt(pos, pos + look))
	car.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
	car.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
end

local function handleShop(player: Player, action: string, a: any, b: any, c: any, d: any)
	local p = DataService.get(player)
	local places = ACTION_PLACES[action]
	if not p or not places then
		return
	end
	if not GarageService.nearPlaceKind(player, places) then
		Net.Notify:FireClient(player, "Drive to the right shop for that.", "error")
		return
	end
	if busy[player] and action ~= "buyPart" then
		Net.Notify:FireClient(player, "Finish your race first.", "error")
		return
	end

	local ok, err
	local changesCar = false
	if action == "buyCar" then
		ok, err = PlayerProfile.buyCar(p, tostring(a))
	elseif action == "buyBay" then
		ok, err = PlayerProfile.buyBay(p)
	elseif action == "select" then
		ok, err = PlayerProfile.selectCar(p, tonumber(a) or 0)
		changesCar = true
	elseif action == "buyPart" then
		ok, err = PlayerProfile.buyPart(p, tostring(a))
	elseif action == "install" then
		ok, err = PlayerProfile.installPart(p, p.activeCar, tostring(a))
		changesCar = true
	elseif action == "remove" then
		ok, err = PlayerProfile.removePart(p, p.activeCar, tostring(a))
		changesCar = true
	elseif action == "saveBuild" then
		ok, err = PlayerProfile.saveBuild(p, p.activeCar, tostring(a))
	elseif action == "loadBuild" then
		ok, err = PlayerProfile.loadBuild(p, p.activeCar, tostring(a))
		changesCar = true
	elseif action == "paint" then
		ok, err = PlayerProfile.setPaint(p, p.activeCar, tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0)
		changesCar = true
	end

	if ok then
		if changesCar then
			refreshCar(player)
		end
		GarageService.pushProfile(player)
	else
		Net.Notify:FireClient(player, err or "Can't do that", "error")
	end
end

function GarageService.start()
	Net.ShopAction.OnServerEvent:Connect(handleShop)
	Net.RespawnCar.OnServerEvent:Connect(GarageService.resetCar)

	-- Walking or driving up to a shop pad opens its menu.
	local places = Workspace:WaitForChild("World"):WaitForChild("Places")
	for _, pad in places:GetChildren() do
		local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				Net.OpenShop:FireClient(player, pad:GetAttribute("PlaceKind"))
			end)
		end
	end

	local function onPlayer(player: Player)
		task.spawn(function()
			if not DataService.waitFor(player) then
				return
			end
			GarageService.spawnCar(player)
			GarageService.pushProfile(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		GarageService.despawn(player)
		busy[player] = nil
	end)
end

return GarageService
