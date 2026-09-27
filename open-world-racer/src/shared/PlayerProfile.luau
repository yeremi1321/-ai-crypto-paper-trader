--!strict
-- A player's saved state and every rule for changing it. Pure data so the
-- server can validate purchases and garage changes in one tested place.

local CarCatalog = require("./CarCatalog")
local Progression = require("./Progression")

export type OwnedCar = {
	carId: string,
	parts: { string }, -- installed part ids, one per slot
	paint: { number }, -- r, g, b 0..255
	builds: { [string]: { string } }, -- saved part setups: street/drag/drift/track
}

export type Profile = {
	version: number,
	cash: number,
	cars: { OwnedCar },
	activeCar: number, -- index into cars
	partsInventory: { [string]: number }, -- owned but uninstalled parts
	rep: { [string]: number }, -- district id -> reputation
	discovered: { [string]: boolean },
	garageBays: number,
	stats: { races: number, wins: number },
}

local PlayerProfile = {}

PlayerProfile.Version = 1
PlayerProfile.BuildSlots = { "street", "drag", "drift", "track" }
PlayerProfile.MaxGarageBays = 6
PlayerProfile.BayPrices = { 0, 5000, 12000, 25000, 45000, 80000 } -- price to reach N bays

local function newCar(carId: string): OwnedCar
	return { carId = carId, parts = {}, paint = { 200, 200, 205 }, builds = {} }
end

function PlayerProfile.new(): Profile
	return {
		version = PlayerProfile.Version,
		cash = Progression.StartingCash,
		cars = { newCar(CarCatalog.StarterCarId) },
		activeCar = 1,
		partsInventory = {},
		rep = {},
		discovered = {},
		garageBays = 1,
		stats = { races = 0, wins = 0 },
	}
end

-- Fills in any fields missing from older saves.
function PlayerProfile.migrate(data: any): Profile
	local fresh = PlayerProfile.new()
	if type(data) ~= "table" then
		return fresh
	end
	for k, v in fresh :: any do
		if data[k] == nil then
			data[k] = v
		end
	end
	if #data.cars == 0 then
		data.cars = fresh.cars
	end
	data.activeCar = math.clamp(data.activeCar, 1, #data.cars)
	data.version = PlayerProfile.Version
	return data
end

local function fail(err: string): (boolean, string)
	return false, err
end

function PlayerProfile.buyCar(p: Profile, carId: string): (boolean, string?)
	local car = CarCatalog.getCar(carId)
	if not car then
		return fail("Unknown car")
	end
	if #p.cars >= p.garageBays then
		return fail("Garage is full - add a bay first")
	end
	if p.cash < car.price then
		return fail("Not enough cash")
	end
	p.cash -= car.price
	table.insert(p.cars, newCar(carId))
	return true
end

function PlayerProfile.buyBay(p: Profile): (boolean, string?)
	if p.garageBays >= PlayerProfile.MaxGarageBays then
		return fail("Garage is fully expanded")
	end
	local price = PlayerProfile.BayPrices[p.garageBays + 1]
	if p.cash < price then
		return fail("Not enough cash")
	end
	p.cash -= price
	p.garageBays += 1
	return true
end

function PlayerProfile.buyPart(p: Profile, partId: string): (boolean, string?)
	local part = CarCatalog.getPart(partId)
	if not part then
		return fail("Unknown part")
	end
	if p.cash < part.price then
		return fail("Not enough cash")
	end
	p.cash -= part.price
	p.partsInventory[partId] = (p.partsInventory[partId] or 0) + 1
	return true
end

function PlayerProfile.givePart(p: Profile, partId: string)
	p.partsInventory[partId] = (p.partsInventory[partId] or 0) + 1
end

-- Installs a part from inventory on a car, returning any part it replaces.
function PlayerProfile.installPart(p: Profile, carIndex: number, partId: string): (boolean, string?)
	local owned = p.cars[carIndex]
	local part = CarCatalog.getPart(partId)
	if not owned or not part then
		return fail("Unknown car or part")
	end
	if (p.partsInventory[partId] or 0) <= 0 then
		return fail("You don't own that part")
	end
	for i, installed in owned.parts do
		local other = CarCatalog.getPart(installed)
		if other and other.slot == part.slot then
			table.remove(owned.parts, i)
			PlayerProfile.givePart(p, installed)
			break
		end
	end
	p.partsInventory[partId] -= 1
	table.insert(owned.parts, partId)
	return true
end

function PlayerProfile.removePart(p: Profile, carIndex: number, partId: string): (boolean, string?)
	local owned = p.cars[carIndex]
	if not owned then
		return fail("Unknown car")
	end
	for i, installed in owned.parts do
		if installed == partId then
			table.remove(owned.parts, i)
			PlayerProfile.givePart(p, partId)
			return true
		end
	end
	return fail("Part not installed")
end

function PlayerProfile.saveBuild(p: Profile, carIndex: number, slot: string): (boolean, string?)
	local owned = p.cars[carIndex]
	if not owned or not table.find(PlayerProfile.BuildSlots, slot) then
		return fail("Unknown car or build slot")
	end
	owned.builds[slot] = table.clone(owned.parts)
	return true
end

-- Swaps to a saved build using only parts the player owns (installed or spare).
function PlayerProfile.loadBuild(p: Profile, carIndex: number, slot: string): (boolean, string?)
	local owned = p.cars[carIndex]
	local build = owned and owned.builds[slot]
	if not owned or not build then
		return fail("No saved build in that slot")
	end
	for _, partId in table.clone(owned.parts) do
		PlayerProfile.removePart(p, carIndex, partId)
	end
	for _, partId in build do
		if (p.partsInventory[partId] or 0) > 0 then
			PlayerProfile.installPart(p, carIndex, partId)
		end
	end
	return true
end

function PlayerProfile.setPaint(p: Profile, carIndex: number, r: number, g: number, b: number): (boolean, string?)
	local owned = p.cars[carIndex]
	if not owned then
		return fail("Unknown car")
	end
	local function c(v: number): number
		return math.clamp(math.floor(tonumber(v) or 0), 0, 255)
	end
	owned.paint = { c(r), c(g), c(b) }
	return true
end

function PlayerProfile.selectCar(p: Profile, carIndex: number): (boolean, string?)
	if not p.cars[carIndex] then
		return fail("Unknown car")
	end
	p.activeCar = carIndex
	return true
end

function PlayerProfile.recordResult(p: Profile, district: string, kind: string, place: number, fieldSize: number, dnf: boolean): (number, number)
	local cash = Progression.payout(kind, place, fieldSize, dnf)
	local rep = Progression.repGain(place, fieldSize, dnf)
	p.cash += cash
	p.rep[district] = (p.rep[district] or 0) + rep
	p.stats.races += 1
	if place == 1 and not dnf then
		p.stats.wins += 1
	end
	return cash, rep
end

-- Returns true the first time a discovery is found.
function PlayerProfile.discover(p: Profile, discoveryId: string): boolean
	if p.discovered[discoveryId] then
		return false
	end
	p.discovered[discoveryId] = true
	return true
end

return PlayerProfile
