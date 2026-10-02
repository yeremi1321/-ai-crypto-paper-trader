--!strict
-- Kart bodies players choose before a race. Your Roblox avatar is the driver;
-- the kart sets the handling. Every kart totals the same number of stat
-- points, so the choice is about style, not power.

export type KartStats = {
	topSpeed: number, -- studs/s
	accel: number, -- studs/s^2
	handling: number, -- turn rate in rad/s at full lock
	weight: number, -- 1..5, heavier karts push lighter ones around
}

export type KartDef = {
	id: string,
	name: string,
	blurb: string,
	color: { number },
	stats: KartStats,
}

local Karts = {}

Karts.Default = "classic"

Karts.List = {
	{
		id = "zippy",
		name = "Zippy",
		blurb = "Light and quick off the line. Great for beginners.",
		color = { 80, 200, 255 },
		stats = { topSpeed = 92, accel = 70, handling = 2.3, weight = 1 },
	},
	{
		id = "classic",
		name = "Classic",
		blurb = "Balanced in every way.",
		color = { 230, 60, 60 },
		stats = { topSpeed = 100, accel = 58, handling = 2.2, weight = 3 },
	},
	{
		id = "brute",
		name = "Brute",
		blurb = "Top speed and weight. Slow to get going.",
		color = { 120, 220, 90 },
		stats = { topSpeed = 106, accel = 54, handling = 2.0, weight = 5 },
	},
} :: { KartDef }

function Karts.get(id: string?): KartDef
	for _, k in Karts.List do
		if k.id == id then
			return k
		end
	end
	return Karts.get(Karts.Default)
end

-- CPU drivers that fill empty grid slots. Original characters.
Karts.CpuDrivers = {
	{ name = "Pip", kart = "zippy" },
	{ name = "Nova", kart = "classic" },
	{ name = "Bolt", kart = "brute" },
	{ name = "Mochi", kart = "zippy" },
	{ name = "Rex", kart = "brute" },
	{ name = "Juno", kart = "classic" },
	{ name = "Taffy", kart = "zippy" },
	{ name = "Gizmo", kart = "classic" },
}

return Karts
