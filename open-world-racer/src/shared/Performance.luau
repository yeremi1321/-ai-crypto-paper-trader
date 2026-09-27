--!strict
-- Performance rating (100..999) and class letters, used to keep races fair:
-- a new player in a D-class hatch only meets other D-class cars.

local CarCatalog = require("./CarCatalog")

local Performance = {}

export type ClassName = "D" | "C" | "B" | "A" | "S"

-- Upper bound (inclusive) of each class, lowest first.
Performance.Classes = {
	{ name = "D" :: ClassName, max = 449 },
	{ name = "C" :: ClassName, max = 549 },
	{ name = "B" :: ClassName, max = 649 },
	{ name = "A" :: ClassName, max = 799 },
	{ name = "S" :: ClassName, max = 999 },
}

local CLASS_ORDER: { [string]: number } = {}
for i, c in Performance.Classes do
	CLASS_ORDER[c.name] = i
end

function Performance.rating(stats: CarCatalog.CarStats): number
	local powerToWeight = stats.power / stats.weight -- ~0.1 (hatch) .. ~0.45 (supercar)
	local accel = math.clamp(powerToWeight / 0.45, 0, 1.3)
	local speed = math.clamp((stats.topSpeed - 120) / 150, 0, 1.3)
	local cornering = stats.grip * 0.6 + stats.handling * 0.4
	local awdBonus = if stats.drivetrain == "AWD" then 0.04 else 0

	local score = accel * 0.40 + speed * 0.25 + cornering * 0.35 + awdBonus
	return math.clamp(math.floor(100 + score * 830 + 0.5), 100, 999)
end

function Performance.classOf(rating: number): ClassName
	for _, c in Performance.Classes do
		if rating <= c.max then
			return c.name
		end
	end
	return "S"
end

function Performance.classRank(className: string): number
	return CLASS_ORDER[className] or 0
end

-- A car may enter an event capped at `cap` if its class is not above the cap.
function Performance.canEnter(rating: number, cap: ClassName?): boolean
	if cap == nil then
		return true
	end
	return Performance.classRank(Performance.classOf(rating)) <= Performance.classRank(cap)
end

function Performance.forBuild(carId: string, partIds: { string }): (number, ClassName)
	local car = CarCatalog.getCar(carId)
	assert(car, `unknown car {carId}`)
	local r = Performance.rating(CarCatalog.applyParts(car.stats, partIds))
	return r, Performance.classOf(r)
end

return Performance
