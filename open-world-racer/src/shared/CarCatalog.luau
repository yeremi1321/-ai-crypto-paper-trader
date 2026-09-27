--!strict
-- Fictional car roster and performance parts. Names and designs are original on
-- purpose: real brands need licensing before publishing.

export type Drivetrain = "FWD" | "RWD" | "AWD"

export type CarStats = {
	power: number, -- horsepower
	weight: number, -- kg
	grip: number, -- 0..1 tire grip
	handling: number, -- 0..1 suspension / chassis response
	topSpeed: number, -- studs per second at stock gearing
	drivetrain: Drivetrain,
}

export type CarDef = {
	id: string,
	name: string,
	archetype: string,
	price: number,
	engineSound: string, -- key into EngineAudio profiles
	stats: CarStats,
}

export type PartDef = {
	id: string,
	slot: string,
	name: string,
	price: number,
	-- Multipliers / additions applied on top of stock stats.
	powerMul: number?,
	weightAdd: number?,
	gripAdd: number?,
	handlingAdd: number?,
	topSpeedMul: number?,
}

local CarCatalog = {}

CarCatalog.StarterCarId = "kestrel"

CarCatalog.Cars = {
	kestrel = {
		id = "kestrel",
		name = "Kestrel Hatch",
		archetype = "Lightweight hatchback",
		price = 0,
		engineSound = "inline4",
		stats = { power = 110, weight = 980, grip = 0.62, handling = 0.70, topSpeed = 150, drivetrain = "FWD" },
	},
	aurelia = {
		id = "aurelia",
		name = "Aurelia Sedan",
		archetype = "Luxury sedan",
		price = 9000,
		engineSound = "v6",
		stats = { power = 240, weight = 1650, grip = 0.66, handling = 0.55, topSpeed = 175, drivetrain = "RWD" },
	},
	dune = {
		id = "dune",
		name = "Dune Runner",
		archetype = "Off-road build",
		price = 11000,
		engineSound = "v6",
		stats = { power = 260, weight = 1900, grip = 0.58, handling = 0.45, topSpeed = 160, drivetrain = "AWD" },
	},
	ronin = {
		id = "ronin",
		name = "Ronin RS",
		archetype = "Japanese sports car",
		price = 18000,
		engineSound = "inline6turbo",
		stats = { power = 280, weight = 1350, grip = 0.74, handling = 0.78, topSpeed = 195, drivetrain = "RWD" },
	},
	bulldog = {
		id = "bulldog",
		name = "Bulldog V8",
		archetype = "Muscle car",
		price = 20000,
		engineSound = "v8",
		stats = { power = 420, weight = 1700, grip = 0.64, handling = 0.52, topSpeed = 205, drivetrain = "RWD" },
	},
	vanta = {
		id = "vanta",
		name = "Vanta GT",
		archetype = "Supercar",
		price = 95000,
		engineSound = "v10",
		stats = { power = 620, weight = 1450, grip = 0.86, handling = 0.85, topSpeed = 250, drivetrain = "AWD" },
	},
} :: { [string]: CarDef }

CarCatalog.Parts = {
	engine1 = { id = "engine1", slot = "engine", name = "Street Engine Tune", price = 2500, powerMul = 1.10 },
	engine2 = { id = "engine2", slot = "engine", name = "Sport Engine Build", price = 7000, powerMul = 1.22 },
	engine3 = { id = "engine3", slot = "engine", name = "Race Engine Build", price = 16000, powerMul = 1.38 },
	turbo = { id = "turbo", slot = "forced", name = "Turbo Kit", price = 9000, powerMul = 1.25, weightAdd = 25 },
	tiresSport = { id = "tiresSport", slot = "tires", name = "Sport Tires", price = 1800, gripAdd = 0.06 },
	tiresRace = { id = "tiresRace", slot = "tires", name = "Semi-Slick Tires", price = 5200, gripAdd = 0.12 },
	tiresDrift = { id = "tiresDrift", slot = "tires", name = "Drift Compound", price = 2000, gripAdd = -0.08 },
	suspension = { id = "suspension", slot = "suspension", name = "Coilovers", price = 3500, handlingAdd = 0.10 },
	weight1 = { id = "weight1", slot = "weight", name = "Stripped Interior", price = 2200, weightAdd = -90 },
	gearing = { id = "gearing", slot = "gearing", name = "Long Gearing", price = 3000, topSpeedMul = 1.08 },
} :: { [string]: PartDef }

function CarCatalog.getCar(id: string): CarDef?
	return CarCatalog.Cars[id]
end

function CarCatalog.getPart(id: string): PartDef?
	return CarCatalog.Parts[id]
end

-- Applies installed parts (one per slot) to a car's stock stats.
function CarCatalog.applyParts(stock: CarStats, partIds: { string }): CarStats
	local s: CarStats = {
		power = stock.power,
		weight = stock.weight,
		grip = stock.grip,
		handling = stock.handling,
		topSpeed = stock.topSpeed,
		drivetrain = stock.drivetrain,
	}
	local usedSlots: { [string]: boolean } = {}
	for _, partId in partIds do
		local part = CarCatalog.Parts[partId]
		if part and not usedSlots[part.slot] then
			usedSlots[part.slot] = true
			s.power *= part.powerMul or 1
			s.weight += part.weightAdd or 0
			s.grip = math.clamp(s.grip + (part.gripAdd or 0), 0.3, 1)
			s.handling = math.clamp(s.handling + (part.handlingAdd or 0), 0.2, 1)
			s.topSpeed *= part.topSpeedMul or 1
		end
	end
	-- More power raises the achievable top speed a little.
	s.topSpeed *= (s.power / stock.power) ^ 0.25
	return s
end

return CarCatalog
