--!strict
-- Kart body designs and paint. Bodies are looks only: speed and handling come
-- from the kart class (Karts.luau), so any body can be paired with any class.
--
-- Adding a body: copy one below and change its parts. Each part is a box,
-- ball, cylinder or wedge with a size and an offset from the kart's center
-- (cylinders run along their x size; rotate them to point elsewhere)
-- (x = right, y = up, z = back; the nose points toward -z). `role` picks the
-- colour: main/accent paint, dark trim, glass, chrome or light (glowing).

export type BodyPart = {
	size: { number },
	offset: { number },
	role: "main" | "accent" | "dark" | "glass" | "chrome" | "light",
	-- Ellipsoid = a smooth stretched sphere (best for rounded, toy-like shapes).
	shape: ("Block" | "Ball" | "Cylinder" | "Wedge" | "Ellipsoid")?,
	rotation: { number }?, -- degrees x, y, z
	color: { number }?, -- fixed colour instead of the role's (eyes, toast, cardboard)
	material: string?, -- e.g. "Glass" or "Neon" instead of the role's
	transparency: number?,
	reflectance: number?,
	-- Animated parts (client/KartVisuals): "blink" eyelids, "toast" pops up
	-- when boosting, "flap" wings, "flutter" laces, "claw" snips, "wobble"
	-- jelly, "rattle" lid, "orbit" lights circling the kart, "engine" an
	-- exposed motor's rumble (harder on the throttle).
	anim: string?,
	text: string?, -- marker drawing on both sides of this part
	bubbles: boolean?, -- this part blows bubbles
}

export type Body = {
	id: string,
	name: string,
	icon: string?,
	price: number?, -- coins to unlock (0 or nil = free)
	wheelRadius: number,
	wheelWidth: number,
	-- Bigger rear wheels (dragsters, hot rods). Default: same as the front.
	rearWheelRadius: number?,
	rearWheelWidth: number?,
	-- Realistic finish: glossy paint, polished chrome, rubber tyres on
	-- metal rims (KartRig). Cartoon bodies leave it off.
	realistic: boolean?,
	wheels: { { number } }, -- x, z of each wheel; the two with the largest z are rear wheels
	seat: { number }, -- where the driver sits
	exhaust: { number },
	parts: { BodyPart },
}

local KartBodies = {}

KartBodies.Default = "classic"

KartBodies.Palette = {
	{ 230, 60, 60 }, -- red
	{ 255, 140, 40 }, -- orange
	{ 255, 210, 50 }, -- yellow
	{ 120, 220, 90 }, -- lime
	{ 40, 170, 110 }, -- green
	{ 80, 200, 255 }, -- sky
	{ 40, 90, 220 }, -- blue
	{ 140, 80, 230 }, -- purple
	{ 255, 110, 190 }, -- pink
	{ 245, 245, 250 }, -- white
	{ 120, 120, 130 }, -- grey
	{ 25, 25, 30 }, -- black
}

local WHEELS_STANDARD = { { -2.5, -2.4 }, { 2.5, -2.4 }, { -2.5, 2.4 }, { 2.5, 2.4 } }

KartBodies.List = {
	{
		id = "classic",
		name = "Classic",
		icon = "🚗",
		price = 0,
		wheelRadius = 0.85,
		wheelWidth = 1.1,
		wheels = WHEELS_STANDARD,
		seat = { 0, 0.6, 0.9 },
		exhaust = { 0, 0.6, 3.6 },
		parts = {
			{ size = { 4.6, 0.5, 7 }, offset = { 0, 0, 0 }, role = "dark" },
			{ size = { 4.2, 1.8, 5 }, offset = { 0, 0.9, -0.9 }, role = "main", shape = "Ellipsoid", reflectance = 0.08 },
			{ size = { 3.4, 1.1, 2.6 }, offset = { 0, 0.5, -3 }, role = "main", shape = "Ellipsoid" },
			{ size = { 1.1, 1.1, 3.8 }, offset = { -2.2, 0.5, 0.6 }, role = "accent", shape = "Ellipsoid" },
			{ size = { 1.1, 1.1, 3.8 }, offset = { 2.2, 0.5, 0.6 }, role = "accent", shape = "Ellipsoid" },
			{ size = { 4.4, 0.3, 1.1 }, offset = { 0, 2.2, 3.2 }, role = "accent", shape = "Ellipsoid" },
			{ size = { 0.3, 1.4, 0.3 }, offset = { -1.2, 1.4, 3.2 }, role = "dark" },
			{ size = { 0.3, 1.4, 0.3 }, offset = { 1.2, 1.4, 3.2 }, role = "dark" },
			{ size = { 3.8, 0.5, 0.5 }, offset = { 0, 0.4, -4.1 }, role = "chrome", shape = "Cylinder" },
			{ size = { 0.9, 0.55, 0.35 }, offset = { -1.2, 0.9, -3.35 }, role = "light", shape = "Ellipsoid" },
			{ size = { 0.9, 0.55, 0.35 }, offset = { 1.2, 0.9, -3.35 }, role = "light", shape = "Ellipsoid" },
		},
	},
	{
		id = "toaster",
		name = "Toaster Terror",
		icon = "🍞",
		price = 400,
		wheelRadius = 0.85,
		wheelWidth = 1.2,
		wheels = WHEELS_STANDARD,
		seat = { 0, 0.6, 1.7 },
		exhaust = { 0, 0.6, 3.7 },
		parts = {
			{ size = { 4.6, 0.6, 7.2 }, offset = { 0, 0, 0 }, role = "dark" },
			{ size = { 4.2, 3, 3.8 }, offset = { 0, 1.7, -1.4 }, role = "main", reflectance = 0.15 },
			{ size = { 4.3, 0.25, 3.9 }, offset = { 0, 3.25, -1.4 }, role = "chrome" },
			{ size = { 1.1, 0.24, 2.8 }, offset = { -0.95, 3.32, -1.4 }, role = "dark" },
			{ size = { 1.1, 0.24, 2.8 }, offset = { 0.95, 3.32, -1.4 }, role = "dark" },
			{ size = { 0.9, 1.8, 2.4 }, offset = { -0.95, 2.6, -1.4 }, role = "main", color = { 225, 170, 90 }, anim = "toast" },
			{ size = { 0.9, 1.8, 2.4 }, offset = { 0.95, 2.6, -1.4 }, role = "main", color = { 225, 170, 90 }, anim = "toast" },
			{ size = { 0.35, 1.2, 0.35 }, offset = { 2.25, 2.3, -0.4 }, role = "chrome" },
			{ size = { 0.8, 0.5, 0.8 }, offset = { 2.25, 3, -0.4 }, role = "dark", shape = "Ellipsoid" },
			{ size = { 1, 1.1, 0.4 }, offset = { -0.85, 2, -3.32 }, role = "main", color = { 255, 255, 255 }, shape = "Ellipsoid" },
			{ size = { 1, 1.1, 0.4 }, offset = { 0.85, 2, -3.32 }, role = "main", color = { 255, 255, 255 }, shape = "Ellipsoid" },
			{ size = { 0.5, 0.5, 0.5 }, offset = { -0.85, 1.95, -3.5 }, role = "dark", shape = "Ball" },
			{ size = { 0.5, 0.5, 0.5 }, offset = { 0.85, 1.95, -3.5 }, role = "dark", shape = "Ball" },
			{ size = { 1.1, 0.6, 0.45 }, offset = { -0.85, 2.7, -3.36 }, role = "main", shape = "Ellipsoid", anim = "blink" },
			{ size = { 1.1, 0.6, 0.45 }, offset = { 0.85, 2.7, -3.36 }, role = "main", shape = "Ellipsoid", anim = "blink" },
			{ size = { 4.6, 1.3, 2.6 }, offset = { 0, 0.6, 2.4 }, role = "accent", shape = "Ellipsoid" },
		},
	},
	{
		id = "bubbleBuggy",
		name = "Bubble Buggy",
		icon = "🧴",
		price = 0,
		wheelRadius = 0.75,
		wheelWidth = 1,
		wheels = { { -2.2, -2.2 }, { 2.2, -2.2 }, { -2.2, 2.2 }, { 2.2, 2.2 } },
		seat = { 0, 0.7, 1.4 },
		exhaust = { 0, 0.7, 3.3 },
		parts = {
			{ size = { 4.4, 0.5, 6 }, offset = { 0, -0.1, 0 }, role = "dark" },
			{ size = { 4.4, 2.4, 6.6 }, offset = { 0, 0.9, 0 }, role = "main", shape = "Ellipsoid", reflectance = 0.25, transparency = 0.1 },
			{ size = { 4.5, 1.2, 3.2 }, offset = { 0, 1, -0.6 }, role = "main", color = { 255, 255, 255 }, shape = "Ellipsoid", text = "SUDS" },
			{ size = { 1, 1.8, 1 }, offset = { 0, 2.4, -2.2 }, role = "accent", shape = "Cylinder", rotation = { 0, 0, 90 } },
			{ size = { 0.6, 0.4, 1.6 }, offset = { 0, 3.35, -2.6 }, role = "accent" },
			{ size = { 1, 1, 1 }, offset = { 0.9, 2.1, 0.6 }, role = "main", color = { 255, 255, 255 }, shape = "Ball" },
			{ size = { 0.8, 0.8, 0.8 }, offset = { -0.7, 2, 0.2 }, role = "main", color = { 255, 255, 255 }, shape = "Ball" },
			{ size = { 0.9, 1, 0.4 }, offset = { -0.7, 1.4, -3.15 }, role = "main", color = { 255, 255, 255 }, shape = "Ellipsoid" },
			{ size = { 0.9, 1, 0.4 }, offset = { 0.7, 1.4, -3.15 }, role = "main", color = { 255, 255, 255 }, shape = "Ellipsoid" },
			{ size = { 0.45, 0.45, 0.45 }, offset = { -0.7, 1.35, -3.32 }, role = "dark", shape = "Ball" },
			{ size = { 0.45, 0.45, 0.45 }, offset = { 0.7, 1.35, -3.32 }, role = "dark", shape = "Ball" },
			{ size = { 1, 0.55, 0.45 }, offset = { -0.7, 2, -3.18 }, role = "main", shape = "Ellipsoid", anim = "blink" },
			{ size = { 1, 0.55, 0.45 }, offset = { 0.7, 2, -3.18 }, role = "main", shape = "Ellipsoid", anim = "blink" },
			{ size = { 0.8, 0.8, 0.8 }, offset = { 0, 0.7, 3.3 }, role = "chrome", shape = "Ball", bubbles = true },
		},
	},
	{
		id = "frog",
		name = "Frog Hopper",
		icon = "🐸",
		price = 0,
		wheelRadius = 0.8,
		wheelWidth = 1.1,
		wheels = { { -2.4, -2.2 }, { 2.4, -2.2 }, { -2.4, 2.3 }, { 2.4, 2.3 } },
		seat = { 0, 0.8, 1.2 },
		exhaust = { 0, 0.6, 3.2 },
		parts = {
			{ size = { 4.8, 2.2, 6.2 }, offset = { 0, 0.9, 0 }, role = "main", shape = "Ellipsoid", reflectance = 0.06 },
			{ size = { 4, 1.4, 5 }, offset = { 0, 0.45, -0.2 }, role = "main", color = { 240, 235, 200 }, shape = "Ellipsoid" },
			{ size = { 1.7, 1.7, 1.7 }, offset = { -1.2, 2.2, -1.9 }, role = "main", shape = "Ellipsoid" },
			{ size = { 1.7, 1.7, 1.7 }, offset = { 1.2, 2.2, -1.9 }, role = "main", shape = "Ellipsoid" },
			{ size = { 1.15, 1.15, 1.15 }, offset = { -1.2, 2.35, -2.5 }, role = "light", shape = "Ball" },
			{ size = { 1.15, 1.15, 1.15 }, offset = { 1.2, 2.35, -2.5 }, role = "light", shape = "Ball" },
			{ size = { 0.55, 0.55, 0.55 }, offset = { -1.2, 2.35, -3 }, role = "dark", shape = "Ball" },
			{ size = { 0.55, 0.55, 0.55 }, offset = { 1.2, 2.35, -3 }, role = "dark", shape = "Ball" },
			{ size = { 1.8, 0.9, 1.8 }, offset = { -1.2, 2.95, -1.95 }, role = "main", shape = "Ellipsoid", anim = "blink" },
			{ size = { 1.8, 0.9, 1.8 }, offset = { 1.2, 2.95, -1.95 }, role = "main", shape = "Ellipsoid", anim = "blink" },
			{ size = { 2.6, 0.14, 0.12 }, offset = { 0, 1.25, -3.08 }, role = "dark" },
			{ size = { 1.4, 1.2, 2.6 }, offset = { -2.4, 0.7, 1.6 }, role = "main", shape = "Ellipsoid" },
			{ size = { 1.4, 1.2, 2.6 }, offset = { 2.4, 0.7, 1.6 }, role = "main", shape = "Ellipsoid" },
			{ size = { 1.3, 0.45, 1.6 }, offset = { -2.1, -0.25, -2.6 }, role = "accent", shape = "Ellipsoid" },
			{ size = { 1.3, 0.45, 1.6 }, offset = { 2.1, -0.25, -2.6 }, role = "accent", shape = "Ellipsoid" },
		},
	},
	{
		id = "ufo",
		name = "UFO Cruiser",
		icon = "🛸",
		price = 600,
		wheelRadius = 0.55,
		wheelWidth = 0.8,
		wheels = { { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } },
		seat = { 0, 0.9, 0.4 },
		exhaust = { 0, 0.5, 3.4 },
		parts = {
			{ size = { 6.6, 1.4, 6.6 }, offset = { 0, 1, 0 }, role = "main", shape = "Ellipsoid", reflectance = 0.3 },
			{ size = { 7, 0.5, 7 }, offset = { 0, 0.9, 0 }, role = "accent", shape = "Ellipsoid" },
			{ size = { 3.4, 2.8, 3.4 }, offset = { 0, 2, 0.4 }, role = "glass", shape = "Ellipsoid" },
			{ size = { 0.5, 0.5, 0.5 }, offset = { 0, 3.5, 0.4 }, role = "light", shape = "Ball" },
			{ size = { 2.2, 0.2, 2.2 }, offset = { 0, 0.15, 0 }, role = "light", shape = "Cylinder", rotation = { 0, 0, 90 }, color = { 140, 230, 255 }, transparency = 0.3 },
			{ size = { 0.6, 0.6, 0.6 }, offset = { 3.3, 1, 0 }, role = "light", shape = "Ball", color = { 255, 90, 160 }, anim = "orbit" },
			{ size = { 0.6, 0.6, 0.6 }, offset = { -3.3, 1, 0 }, role = "light", shape = "Ball", color = { 120, 220, 255 }, anim = "orbit" },
			{ size = { 0.6, 0.6, 0.6 }, offset = { 0, 1, 3.3 }, role = "light", shape = "Ball", color = { 255, 220, 80 }, anim = "orbit" },
			{ size = { 0.6, 0.6, 0.6 }, offset = { 0, 1, -3.3 }, role = "light", shape = "Ball", color = { 120, 255, 150 }, anim = "orbit" },
		},
	},
	{
		id = "dragon",
		name = "Dragon Hatchling",
		icon = "🐉",
		price = 800,
		wheelRadius = 0.8,
		wheelWidth = 1.1,
		wheels = { { -2.3, -2.2 }, { 2.3, -2.2 }, { -2.3, 2.3 }, { 2.3, 2.3 } },
		seat = { 0, 0.7, 1 },
		exhaust = { 0, 0.8, 3.8 },
		parts = {
			{ size = { 4.4, 2.6, 5.6 }, offset = { 0, 0.8, 0.4 }, role = "main", color = { 248, 242, 222 }, shape = "Ellipsoid" },
			{ size = { 0.9, 0.9, 0.9 }, offset = { -2.05, 1.1, 0.4 }, role = "accent", shape = "Ball" },
			{ size = { 0.7, 0.7, 0.7 }, offset = { 2.05, 0.8, 1.2 }, role = "accent", shape = "Ball" },
			{ size = { 0.8, 0.8, 0.8 }, offset = { 1.8, 1.4, -0.8 }, role = "accent", shape = "Ball" },
			{ size = { 2.6, 2.2, 2.8 }, offset = { 0, 2.4, -1.9 }, role = "main", shape = "Ellipsoid" },
			{ size = { 1.8, 1.2, 1.8 }, offset = { 0, 2.1, -3.2 }, role = "main", shape = "Ellipsoid" },
			{ size = { 0.3, 0.3, 0.3 }, offset = { -0.35, 2.3, -4.05 }, role = "dark", shape = "Ball" },
			{ size = { 0.3, 0.3, 0.3 }, offset = { 0.35, 2.3, -4.05 }, role = "dark", shape = "Ball" },
			{ size = { 0.9, 1, 0.5 }, offset = { -0.7, 2.9, -2.9 }, role = "main", color = { 255, 255, 255 }, shape = "Ellipsoid" },
			{ size = { 0.9, 1, 0.5 }, offset = { 0.7, 2.9, -2.9 }, role = "main", color = { 255, 255, 255 }, shape = "Ellipsoid" },
			{ size = { 0.45, 0.6, 0.3 }, offset = { -0.7, 2.85, -3.12 }, role = "dark", shape = "Ellipsoid" },
			{ size = { 0.45, 0.6, 0.3 }, offset = { 0.7, 2.85, -3.12 }, role = "dark", shape = "Ellipsoid" },
			{ size = { 1, 0.55, 0.55 }, offset = { -0.7, 3.45, -2.92 }, role = "main", shape = "Ellipsoid", anim = "blink" },
			{ size = { 1, 0.55, 0.55 }, offset = { 0.7, 3.45, -2.92 }, role = "main", shape = "Ellipsoid", anim = "blink" },
			{ size = { 0.5, 1.4, 0.5 }, offset = { -0.7, 3.6, -1.5 }, role = "accent", shape = "Ellipsoid", rotation = { -25, 0, -12 } },
			{ size = { 0.5, 1.4, 0.5 }, offset = { 0.7, 3.6, -1.5 }, role = "accent", shape = "Ellipsoid", rotation = { -25, 0, 12 } },
			{ size = { 3.2, 0.3, 1.9 }, offset = { -2.6, 2, 0.6 }, role = "main", shape = "Ellipsoid", anim = "flap" },
			{ size = { 3.2, 0.3, 1.9 }, offset = { 2.6, 2, 0.6 }, role = "main", shape = "Ellipsoid", anim = "flap" },
			{ size = { 1, 1, 2.8 }, offset = { 0, 0.9, 3.4 }, role = "main", shape = "Ellipsoid", rotation = { 20, 0, 0 } },
			{ size = { 0.8, 0.8, 0.8 }, offset = { 0, 0.4, 4.7 }, role = "accent", shape = "Ball" },
		},
	},
	{
		id = "sneaker",
		name = "Sneaker Speeder",
		icon = "👟",
		price = 500,
		wheelRadius = 0.8,
		wheelWidth = 1.1,
		wheels = { { -2.4, -2.6 }, { 2.4, -2.6 }, { -2.4, 2.5 }, { 2.4, 2.5 } },
		seat = { 0, 0.9, 1.9 },
		exhaust = { 0, 0.4, 3.9 },
		parts = {
			{ size = { 4.6, 0.9, 7.6 }, offset = { 0, 0.1, 0 }, role = "main", color = { 250, 250, 250 }, shape = "Ellipsoid" },
			{ size = { 4.2, 2.4, 6.4 }, offset = { 0, 1.1, 0.4 }, role = "main", shape = "Ellipsoid" },
			{ size = { 3.8, 1.6, 2.4 }, offset = { 0, 0.8, -2.6 }, role = "accent", shape = "Ellipsoid" },
			{ size = { 3.2, 0.4, 2.6 }, offset = { 0, 2.25, 1.8 }, role = "dark", shape = "Ellipsoid" },
			{ size = { 2, 1.4, 0.6 }, offset = { 0, 2.6, 0.9 }, role = "main", shape = "Ellipsoid", rotation = { -25, 0, 0 } },
			{ size = { 0.2, 0.8, 3.6 }, offset = { -2.12, 1.2, 0.6 }, role = "accent", shape = "Ellipsoid", rotation = { 0, 0, 10 } },
			{ size = { 0.2, 0.8, 3.6 }, offset = { 2.12, 1.2, 0.6 }, role = "accent", shape = "Ellipsoid", rotation = { 0, 0, -10 } },
			{ size = { 3, 0.25, 0.35 }, offset = { 0, 2.2, -1.2 }, role = "main", color = { 255, 255, 255 } },
			{ size = { 3, 0.25, 0.35 }, offset = { 0, 2.3, -0.4 }, role = "main", color = { 255, 255, 255 } },
			{ size = { 0.8, 0.3, 1.3 }, offset = { -0.9, 2.45, -1.6 }, role = "main", color = { 255, 255, 255 }, shape = "Ellipsoid", anim = "flutter" },
			{ size = { 0.8, 0.3, 1.3 }, offset = { 0.9, 2.45, -1.6 }, role = "main", color = { 255, 255, 255 }, shape = "Ellipsoid", anim = "flutter" },
		},
	},
	{
		id = "crab",
		name = "Crab Cab",
		icon = "🦀",
		price = 500,
		wheelRadius = 0.8,
		wheelWidth = 1.1,
		wheels = WHEELS_STANDARD,
		seat = { 0, 0.7, 1.4 },
		exhaust = { 0, 0.5, 3.4 },
		parts = {
			{ size = { 4.6, 0.5, 6.4 }, offset = { 0, 0, 0.2 }, role = "dark" },
			{ size = { 5.4, 2.2, 4.4 }, offset = { 0, 1.1, -0.8 }, role = "main", shape = "Ellipsoid", reflectance = 0.1 },
			{ size = { 1, 1, 1 }, offset = { -1.3, 2, -0.5 }, role = "accent", shape = "Ball" },
			{ size = { 0.8, 0.8, 0.8 }, offset = { 1.4, 1.9, -1.2 }, role = "accent", shape = "Ball" },
			{ size = { 0.35, 1.4, 0.35 }, offset = { -0.8, 2.4, -2.4 }, role = "main", shape = "Cylinder", rotation = { 0, 0, 90 } },
			{ size = { 0.35, 1.4, 0.35 }, offset = { 0.8, 2.4, -2.4 }, role = "main", shape = "Cylinder", rotation = { 0, 0, 90 } },
			{ size = { 0.85, 0.85, 0.85 }, offset = { -0.8, 3.2, -2.4 }, role = "main", color = { 255, 255, 255 }, shape = "Ball" },
			{ size = { 0.85, 0.85, 0.85 }, offset = { 0.8, 3.2, -2.4 }, role = "main", color = { 255, 255, 255 }, shape = "Ball" },
			{ size = { 0.4, 0.4, 0.4 }, offset = { -0.8, 3.2, -2.8 }, role = "dark", shape = "Ball" },
			{ size = { 0.4, 0.4, 0.4 }, offset = { 0.8, 3.2, -2.8 }, role = "dark", shape = "Ball" },
			{ size = { 0.95, 0.5, 0.95 }, offset = { -0.8, 3.55, -2.4 }, role = "main", shape = "Ellipsoid", anim = "blink" },
			{ size = { 0.95, 0.5, 0.95 }, offset = { 0.8, 3.55, -2.4 }, role = "main", shape = "Ellipsoid", anim = "blink" },
			{ size = { 1.4, 1.2, 2.2 }, offset = { -2.9, 1.1, -2.6 }, role = "accent", shape = "Ellipsoid", anim = "claw" },
			{ size = { 1.4, 1.2, 2.2 }, offset = { 2.9, 1.1, -2.6 }, role = "accent", shape = "Ellipsoid", anim = "claw" },
			{ size = { 1.6, 0.3, 0.3 }, offset = { -2.8, 0.3, 0.6 }, role = "dark", rotation = { 0, 0, 25 } },
			{ size = { 1.6, 0.3, 0.3 }, offset = { 2.8, 0.3, 0.6 }, role = "dark", rotation = { 0, 0, -25 } },
		},
	},
	{
		id = "jelly",
		name = "Jelly Racer",
		icon = "🍮",
		price = 400,
		wheelRadius = 0.8,
		wheelWidth = 1.1,
		wheels = WHEELS_STANDARD,
		seat = { 0, 0.6, 2 },
		exhaust = { 0, 0.5, 3.7 },
		parts = {
			{ size = { 4.6, 0.5, 7 }, offset = { 0, 0, 0 }, role = "dark" },
			{ size = { 4.6, 2.6, 5.4 }, offset = { 0, 1.4, -0.6 }, role = "main", shape = "Ellipsoid", material = "Glass", transparency = 0.3, anim = "wobble" },
			{ size = { 1, 1, 1 }, offset = { 0.6, 1.2, -1 }, role = "accent", shape = "Ball" },
			{ size = { 0.8, 0.8, 0.8 }, offset = { -0.8, 1.6, -0.2 }, role = "accent", shape = "Ball" },
			{ size = { 0.7, 0.7, 0.7 }, offset = { 0.2, 1, 0.4 }, role = "accent", shape = "Ball" },
			{ size = { 3, 0.8, 3 }, offset = { 0, 2.8, -0.8 }, role = "main", color = { 255, 252, 245 }, shape = "Ellipsoid", anim = "wobble" },
			{ size = { 0.9, 0.9, 0.9 }, offset = { 0, 3.4, -0.8 }, role = "main", color = { 220, 30, 50 }, shape = "Ball", anim = "wobble" },
			{ size = { 4.6, 0.6, 1.4 }, offset = { 0, 0.4, 2.8 }, role = "accent", shape = "Ellipsoid" },
		},
	},
	{
		id = "cardboard",
		name = "Cardboard Champion",
		icon = "📦",
		price = 200,
		wheelRadius = 0.85,
		wheelWidth = 1.1,
		wheels = WHEELS_STANDARD,
		seat = { 0, 0.8, 1.7 },
		exhaust = { 0, 0.5, 3.6 },
		parts = {
			{ size = { 4.4, 2.6, 5.2 }, offset = { 0, 1.4, -0.7 }, role = "main", color = { 205, 165, 115 }, text = "VROOM!" },
			{ size = { 4.45, 0.1, 0.8 }, offset = { 0, 2.73, -0.7 }, role = "main", color = { 230, 210, 160 }, transparency = 0.2 },
			{ size = { 4.4, 0.15, 1.8 }, offset = { 0, 3.2, -3.6 }, role = "main", color = { 195, 155, 105 }, rotation = { 40, 0, 0 } },
			{ size = { 1.8, 1.8, 0.1 }, offset = { 0, 1.5, -3.32 }, role = "main", color = { 255, 255, 255 }, shape = "Ellipsoid", text = "1" },
			{ size = { 4.6, 0.5, 7 }, offset = { 0, 0, 0 }, role = "dark" },
			{ size = { 4.4, 1.2, 1.6 }, offset = { 0, 0.6, 2.6 }, role = "accent" },
		},
	},
	{
		id = "dumpster",
		name = "Dumpster Rocket",
		icon = "🗑️",
		price = 600,
		wheelRadius = 0.8,
		wheelWidth = 1.2,
		wheels = WHEELS_STANDARD,
		seat = { 0, 1.1, 0.2 },
		exhaust = { 0, 1.2, 4.2 },
		parts = {
			{ size = { 4.4, 2.4, 5 }, offset = { 0, 1.3, -0.4 }, role = "main" },
			{ size = { 4.5, 0.3, 0.3 }, offset = { 0, 2.1, -2.95 }, role = "accent" },
			{ size = { 4.5, 0.3, 0.3 }, offset = { 0, 0.9, -2.95 }, role = "accent" },
			{ size = { 4.6, 0.3, 5.2 }, offset = { 0, 3.6, 2.2 }, role = "dark", rotation = { 70, 0, 0 }, anim = "rattle" },
			{ size = { 2.4, 1.5, 1.5 }, offset = { 0, 1.2, 2.8 }, role = "chrome", shape = "Cylinder", rotation = { 0, 90, 0 } },
			{ size = { 0.3, 1.2, 1.2 }, offset = { -1, 1.2, 3.6 }, role = "accent", shape = "Wedge" },
			{ size = { 0.3, 1.2, 1.2 }, offset = { 1, 1.2, 3.6 }, role = "accent", shape = "Wedge" },
			{ size = { 4.6, 0.5, 6.8 }, offset = { 0, 0, 0.2 }, role = "dark" },
		},
	},
	{
		id = "racer",
		name = "Wedge Racer",
		icon = "📐",
		price = 150,
		wheelRadius = 0.75,
		wheelWidth = 1,
		wheels = { { -2.6, -2.6 }, { 2.6, -2.6 }, { -2.6, 2.6 }, { 2.6, 2.6 } },
		seat = { 0, 0.5, 0.9 },
		exhaust = { 0, 0.5, 3.9 },
		parts = {
			{ size = { 4.8, 0.5, 7.6 }, offset = { 0, 0, 0 }, role = "dark" },
			{ size = { 3.8, 1, 3.4 }, offset = { 0, 0.6, -2.4 }, role = "main", shape = "Wedge" },
			{ size = { 4.2, 1, 3 }, offset = { 0, 0.6, 1.6 }, role = "main" },
			{ size = { 1, 0.7, 4 }, offset = { -2.1, 0.5, 0.2 }, role = "accent" },
			{ size = { 1, 0.7, 4 }, offset = { 2.1, 0.5, 0.2 }, role = "accent" },
			{ size = { 5, 0.2, 1.2 }, offset = { 0, 2.4, 3.6 }, role = "accent" },
			{ size = { 0.3, 1.6, 0.4 }, offset = { -1.6, 1.5, 3.6 }, role = "dark" },
			{ size = { 0.3, 1.6, 0.4 }, offset = { 1.6, 1.5, 3.6 }, role = "dark" },
			{ size = { 4.2, 0.2, 0.2 }, offset = { 0, 0.4, -4 }, role = "light" },
		},
	},
	{
		id = "buggy",
		name = "Dune Buggy",
		icon = "🏜️",
		price = 150,
		wheelRadius = 1.05,
		wheelWidth = 1.2,
		wheels = { { -2.7, -2.5 }, { 2.7, -2.5 }, { -2.7, 2.5 }, { 2.7, 2.5 } },
		seat = { 0, 0.8, 0.4 },
		exhaust = { 0, 1.2, 3.4 },
		parts = {
			{ size = { 3.6, 0.6, 6.4 }, offset = { 0, 0.2, 0 }, role = "main" },
			{ size = { 3.2, 0.6, 1.2 }, offset = { 0, 0.6, -3.1 }, role = "accent" },
			-- Roll cage
			{ size = { 0.25, 2.6, 0.25 }, offset = { -1.5, 1.8, -0.8 }, role = "chrome" },
			{ size = { 0.25, 2.6, 0.25 }, offset = { 1.5, 1.8, -0.8 }, role = "chrome" },
			{ size = { 0.25, 2.6, 0.25 }, offset = { -1.5, 1.8, 1.8 }, role = "chrome" },
			{ size = { 0.25, 2.6, 0.25 }, offset = { 1.5, 1.8, 1.8 }, role = "chrome" },
			{ size = { 3.25, 0.25, 0.25 }, offset = { 0, 3.1, -0.8 }, role = "chrome" },
			{ size = { 3.25, 0.25, 0.25 }, offset = { 0, 3.1, 1.8 }, role = "chrome" },
			{ size = { 0.25, 0.25, 2.85 }, offset = { -1.5, 3.1, 0.5 }, role = "chrome" },
			{ size = { 0.25, 0.25, 2.85 }, offset = { 1.5, 3.1, 0.5 }, role = "chrome" },
			{ size = { 2.4, 1.4, 1.2 }, offset = { 0, 1, 2.7 }, role = "dark" },
			{ size = { 0.6, 0.6, 0.3 }, offset = { -0.9, 1.1, -3.7 }, role = "light" },
			{ size = { 0.6, 0.6, 0.3 }, offset = { 0.9, 1.1, -3.7 }, role = "light" },
		},
	},
	{
		id = "muscle",
		name = "Muscle",
		icon = "💪",
		price = 200,
		wheelRadius = 0.9,
		wheelWidth = 1.3,
		wheels = { { -2.6, -2.6 }, { 2.6, -2.6 }, { -2.6, 2.5 }, { 2.6, 2.5 } },
		seat = { 0, 0.7, 1 },
		exhaust = { 0, 0.5, 3.9 },
		parts = {
			{ size = { 4.4, 1.3, 7.6 }, offset = { 0, 0.5, 0 }, role = "main" },
			{ size = { 1.6, 0.5, 2 }, offset = { 0, 1.35, -2 }, role = "dark" },
			{ size = { 0.8, 1.3, 7.7 }, offset = { 0, 0.52, 0 }, role = "accent" },
			{ size = { 4.5, 0.4, 0.4 }, offset = { 0, 0.1, -3.9 }, role = "chrome" },
			{ size = { 4.5, 0.4, 0.4 }, offset = { 0, 0.1, 3.9 }, role = "chrome" },
			{ size = { 1, 0.45, 0.45 }, offset = { -1.4, 0.2, 4.1 }, role = "chrome", shape = "Cylinder", rotation = { 0, 90, 0 } },
			{ size = { 1, 0.45, 0.45 }, offset = { 1.4, 0.2, 4.1 }, role = "chrome", shape = "Cylinder", rotation = { 0, 90, 0 } },
			{ size = { 1, 0.4, 0.2 }, offset = { -1.5, 0.8, -3.85 }, role = "light" },
			{ size = { 1, 0.4, 0.2 }, offset = { 1.5, 0.8, -3.85 }, role = "light" },
		},
	},
	{
		id = "formula",
		name = "Formula",
		icon = "🏎️",
		price = 300,
		wheelRadius = 0.85,
		wheelWidth = 1.2,
		wheels = { { -2.8, -2.8 }, { 2.8, -2.8 }, { -2.8, 2.6 }, { 2.8, 2.6 } },
		seat = { 0, 0.5, 0.8 },
		exhaust = { 0, 0.8, 4 },
		parts = {
			{ size = { 1.6, 0.9, 8.4 }, offset = { 0, 0.3, -0.2 }, role = "main" },
			{ size = { 1.2, 0.6, 2 }, offset = { 0, 0.2, -4.8 }, role = "main", shape = "Wedge" },
			{ size = { 5.6, 0.2, 1 }, offset = { 0, -0.1, -4.9 }, role = "accent" },
			{ size = { 1.2, 0.8, 3 }, offset = { -1.4, 0.3, 0.8 }, role = "accent" },
			{ size = { 1.2, 0.8, 3 }, offset = { 1.4, 0.3, 0.8 }, role = "accent" },
			{ size = { 1.2, 1.2, 1.6 }, offset = { 0, 1.1, 2 }, role = "main" },
			{ size = { 4.8, 0.25, 1.2 }, offset = { 0, 2.3, 3.8 }, role = "accent" },
			{ size = { 0.25, 1.4, 0.8 }, offset = { -2.2, 1.6, 3.8 }, role = "dark" },
			{ size = { 0.25, 1.4, 0.8 }, offset = { 2.2, 1.6, 3.8 }, role = "dark" },
			{ size = { 3, 0.2, 0.2 }, offset = { 0, 1.5, -0.6 }, role = "chrome" },
		},
	},
} :: { Body }

-- Original low racing bodies: open cockpits, broad slicks and twin exhausts.
local racingBodies = {
 { id = "embergt", name = "Ember GT", nose = "Ellipsoid", wing = 2.1 },
 { id = "arrowsprint", name = "Arrow Sprint", nose = "Wedge", wing = 2.8 },
 { id = "rallycomet", name = "Rally Comet", nose = "Ellipsoid", wing = 1.8 },
}
for index, design in racingBodies do
 local parts: { BodyPart } = {
  { size = { 5.4, 0.45, 7.8 }, offset = { 0, 0, 0 }, role = "dark", shape = "Ellipsoid" },
  { size = { 3.4, 1, 4.2 }, offset = { 0, 0.45, -2 }, role = "main", shape = design.nose },
  { size = { 5.5, 0.25, 0.8 }, offset = { 0, 0.05, -4.2 }, role = "accent", shape = "Ellipsoid" },
  { size = { 2, 0.15, 3 }, offset = { 0, 1, -2 }, role = "accent", shape = "Ellipsoid" },
  { size = { 4.8, 0.25, 1.1 }, offset = { 0, design.wing, 3.4 }, role = "accent", shape = "Ellipsoid" },
 }
 for _, side in { -1, 1 } do
  table.insert(parts, { size = { 1.1, 1.2, 4.8 }, offset = { side * 2.1, 0.65, 0.2 }, role = "main", shape = "Ellipsoid" })
  table.insert(parts, { size = { 0.25, design.wing, 0.5 }, offset = { side * 1.8, design.wing / 2, 3.4 }, role = "dark" })
  table.insert(parts, { size = { 2.4, 1.1, 1.1 }, offset = { side * 1.4, 1.2, 2.9 }, role = "chrome", shape = "Cylinder", rotation = { 0, 90, 0 } })
  table.insert(parts, { size = { 0.12, 0.75, 0.75 }, offset = { side * 1.4, 1.2, 4.12 }, role = "dark", shape = "Cylinder", rotation = { 0, 90, 0 } })
  table.insert(parts, { size = { 0.8, 0.45, 0.15 }, offset = { side * 1.7, 0.6, -3.8 }, role = "chrome", shape = "Ellipsoid" })
 end
 for k = -2, 2 do table.insert(parts, { size = { 0.1, 0.45, 0.18 }, offset = { k * 0.24, 0.52, -4.05 }, role = "chrome" }) end
 if design.id == "rallycomet" then
  for _, side in { -1, 1 } do
   table.insert(parts, { size = { 0.25, 2.8, 0.25 }, offset = { side * 1.4, 1.8, 1.8 }, role = "chrome" })
  end
  table.insert(parts, { size = { 3, 0.25, 0.25 }, offset = { 0, 3.2, 1.8 }, role = "chrome" })
 end
 table.insert(KartBodies.List, index, {
  id = design.id, name = design.name, icon = "🏎️", price = 0,
  wheelRadius = 0.95, wheelWidth = 1.4,
  wheels = { { -2.8, -2.6 }, { 2.8, -2.6 }, { -2.8, 2.6 }, { 2.8, 2.6 } },
  seat = { 0, 0.55, 0.6 }, exhaust = { 0, 1.1, 4.1 }, parts = parts,
 })
end

---------------------------------------------------------------------------
-- Big-motor cars: realistic paint, chrome and rubber, with exposed engines
-- that rumble. Original designs, built from small helpers so each stays short.
---------------------------------------------------------------------------
local function P(parts: { BodyPart }, size: { number }, offset: { number }, role: any, shape: any?, extra: { [string]: any }?)
	local part: any = { size = size, offset = offset, role = role, shape = shape }
	for k, v in extra or {} do
		part[k] = v
	end
	table.insert(parts, part)
end

local GLOSS = { reflectance = 0.12 }
local RED_LIGHT = { color = { 255, 40, 30 } }

-- An exposed V8: block, chrome valve covers, a supercharger with its belt
-- pulley, eight velocity stacks (or a scoop) and four-into-one headers.
-- The blower and stacks rumble.
type EngineOptions = { stacks: boolean?, headers: boolean?, length: number? }
local function v8(parts: { BodyPart }, x: number, y: number, z: number, options: EngineOptions?)
	local o: EngineOptions = options or {}
	local L = o.length or 2.4
	P(parts, { 1.8, 1, L }, { x, y, z }, "accent", nil, { material = "Metal", reflectance = 0.1 })
	for _, side in { -1, 1 } do
		P(parts, { 0.7, 0.45, L - 0.2 }, { x + side * 0.75, y + 0.6, z }, "chrome", nil, { rotation = { 0, 0, side * -25 } })
	end
	P(parts, { 1.3, 0.75, L * 0.65 }, { x, y + 1.05, z }, "chrome", nil, { anim = "engine" })
	P(parts, { 0.5, 0.9, 0.9 }, { x, y + 0.95, z - L / 2 - 0.1 }, "dark", "Cylinder", { rotation = { 0, 90, 0 } })
	if o.stacks ~= false then
		for k = 0, 3 do
			for _, side in { -1, 1 } do
				P(parts, { 0.75, 0.34, 0.34 }, { x + side * 0.32, y + 1.75, z - L * 0.25 + k * L * 0.17 }, "chrome", "Cylinder", { rotation = { 0, 0, 90 }, anim = "engine" })
			end
		end
	else
		P(parts, { 1.2, 0.6, 1.1 }, { x, y + 1.7, z }, "dark", nil, { anim = "engine" })
	end
	if o.headers ~= false then
		for _, side in { -1, 1 } do
			for k = 0, 3 do
				P(parts, { 1.3, 0.24, 0.24 }, { x + side * 1.35, y - 0.05, z - L * 0.35 + k * L * 0.23 }, "chrome", "Cylinder", { rotation = { 0, 0, side * -40 } })
			end
		end
	end
end

local bigMotor: { Body } = {}

do -- Blower Rod: an open hot rod, supercharged V8 out front, fat rear tyres.
	local parts: { BodyPart } = {}
	for _, side in { -1, 1 } do
		P(parts, { 0.35, 0.4, 8.6 }, { side * 1.05, -0.15, -0.3 }, "dark")
	end
	P(parts, { 4.4, 0.28, 0.28 }, { 0, -0.2, -3.7 }, "dark", "Cylinder")
	P(parts, { 3.2, 1.5, 3.4 }, { 0, 0.55, 1.5 }, "main", "Ellipsoid", GLOSS)
	P(parts, { 3.4, 0.35, 3.6 }, { 0, 1.2, 1.5 }, "accent", "Ellipsoid")
	for _, side in { -1, 1 } do
		P(parts, { 1.5, 1.1, 3.2 }, { side * 2.55, 1.3, 2.6 }, "main", "Ellipsoid", GLOSS)
	end
	P(parts, { 2.2, 2, 0.5 }, { 0, 0.75, -4.3 }, "chrome")
	P(parts, { 1.8, 1.6, 0.2 }, { 0, 0.75, -4.6 }, "dark")
	for k = -3, 3 do
		P(parts, { 0.1, 1.5, 0.25 }, { k * 0.22, 0.75, -4.62 }, "chrome")
	end
	v8(parts, 0, 0.35, -2.1)
	P(parts, { 2.6, 1, 0.12 }, { 0, 1.9, 0.1 }, "glass", nil, { rotation = { -15, 0, 0 } })
	P(parts, { 2.8, 0.15, 0.2 }, { 0, 2.45, 0.25 }, "chrome")
	for _, side in { -1, 1 } do
		P(parts, { 0.18, 0.9, 0.18 }, { side * 1.45, 0.6, -3.9 }, "chrome")
		P(parts, { 0.4, 0.8, 0.8 }, { side * 1.45, 1.2, -3.95 }, "chrome", "Cylinder", { rotation = { 0, 90, 0 } })
		P(parts, { 0.06, 0.65, 0.65 }, { side * 1.45, 1.2, -4.38 }, "light", "Cylinder", { rotation = { 0, 90, 0 } })
		P(parts, { 0.5, 0.35, 0.12 }, { side * 2.55, 1.2, 4.25 }, "light", nil, RED_LIGHT)
	end
	table.insert(bigMotor, {
		id = "blowerrod", name = "Blower Rod", icon = "🔥", price = 0, realistic = true,
		wheelRadius = 0.75, wheelWidth = 0.8, rearWheelRadius = 1.3, rearWheelWidth = 1.9,
		wheels = { { -2.3, -3.7 }, { 2.3, -3.7 }, { -2.55, 2.6 }, { 2.55, 2.6 } },
		seat = { 0, 0.35, 1.6 }, exhaust = { 0, 0, 4.3 }, parts = parts,
	})
end

do -- Thunder Muscle: a wide convertible muscle car, blower through the hood.
	local parts: { BodyPart } = {}
	P(parts, { 4.2, 1.1, 8.8 }, { 0, 0.25, 0 }, "main", nil, GLOSS)
	P(parts, { 4.2, 0.9, 1.6 }, { 0, 0.15, -4.3 }, "main", "Ellipsoid", GLOSS)
	P(parts, { 4.2, 0.9, 1.4 }, { 0, 0.2, 4.3 }, "main", "Ellipsoid", GLOSS)
	for _, side in { -1, 1 } do
		P(parts, { 0.55, 0.06, 8.8 }, { side * 0.45, 0.82, 0 }, "accent")
		for _, z in { -2.9, 2.8 } do
			P(parts, { 0.9, 0.9, 2.8 }, { side * 2.3, 0.6, z }, "main", "Ellipsoid", GLOSS)
		end
		P(parts, { 5.2, 0.42, 0.42 }, { side * 2.25, -0.4, 0 }, "chrome", "Cylinder", { rotation = { 0, 90, 0 } })
		P(parts, { 1.4, 0.3, 0.1 }, { side * 1.3, 0.45, 4.98 }, "light", nil, RED_LIGHT)
		for k = 0, 1 do
			P(parts, { 0.12, 0.45, 0.45 }, { side * (1.2 + k * 0.6), 0.35, -5.05 }, "light", "Cylinder", { rotation = { 0, 90, 0 } })
		end
		P(parts, { 0.2, 0.6, 0.2 }, { side * 1.8, 1.05, 4.2 }, "dark")
	end
	P(parts, { 3.4, 0.3, 2.6 }, { 0, 0.85, 1.2 }, "dark")
	P(parts, { 3.8, 1, 0.12 }, { 0, 1.35, -0.3 }, "glass", nil, { rotation = { -25, 0, 0 } })
	P(parts, { 3.9, 0.12, 0.2 }, { 0, 1.85, -0.1 }, "chrome")
	P(parts, { 2.2, 0.35, 3.4 }, { 0, 0.9, -2.4 }, "main", "Ellipsoid", GLOSS)
	v8(parts, 0, 0, -2.5, { headers = false })
	P(parts, { 4.2, 0.2, 0.9 }, { 0, 1.35, 4.2 }, "accent")
	P(parts, { 3.4, 0.6, 0.15 }, { 0, 0.25, -5.0 }, "dark")
	P(parts, { 4.4, 0.25, 0.3 }, { 0, -0.25, -5.05 }, "chrome")
	P(parts, { 4.4, 0.25, 0.3 }, { 0, -0.15, 5.0 }, "chrome")
	table.insert(bigMotor, {
		id = "thunder", name = "Thunder Muscle", icon = "⚡", price = 300, realistic = true,
		wheelRadius = 0.95, wheelWidth = 1.3, rearWheelRadius = 1.1, rearWheelWidth = 1.7,
		wheels = { { -2.45, -2.9 }, { 2.45, -2.9 }, { -2.45, 2.8 }, { 2.45, 2.8 } },
		seat = { 0, 0.3, 1.3 }, exhaust = { 0, -0.2, 5.1 }, parts = parts,
	})
end

do -- Twin-Turbo Dragster: long nose, tiny front wheels, huge slicks, a wing.
	local parts: { BodyPart } = {}
	for _, side in { -1, 1 } do
		P(parts, { 0.25, 0.25, 10.5 }, { side * 0.6, -0.1, -1.6 }, "dark")
	end
	P(parts, { 1.4, 0.9, 5 }, { 0, 0.15, -4.3 }, "main", "Ellipsoid", { reflectance = 0.15 })
	P(parts, { 1, 0.5, 1.6 }, { 0, 0.2, -6.9 }, "accent", "Ellipsoid")
	P(parts, { 2.6, 0.12, 0.6 }, { 0, -0.1, -6.9 }, "accent")
	P(parts, { 2, 1.2, 2.4 }, { 0, 0.5, -0.6 }, "main", "Ellipsoid", { reflectance = 0.15 })
	P(parts, { 1.8, 0.18, 0.18 }, { 0, 2.6, 0.2 }, "chrome")
	P(parts, { 2.2, 1, 2 }, { 0, 0.3, 3.3 }, "main", "Ellipsoid", GLOSS)
	v8(parts, 0, 0.4, 1.9, { headers = false })
	for _, side in { -1, 1 } do
		P(parts, { 0.18, 2, 0.18 }, { side * 0.8, 1.6, 0.2 }, "chrome")
		P(parts, { 0.9, 1.1, 1.1 }, { side * 1.45, 1.3, 1.6 }, "chrome", "Cylinder", { rotation = { 0, 90, 0 } })
		P(parts, { 0.1, 0.75, 0.75 }, { side * 1.45, 1.3, 1.03 }, "dark", "Cylinder", { rotation = { 0, 90, 0 } })
		for k = 0, 1 do
			P(parts, { 1.4, 0.3, 0.3 }, { side * 1.3, 1.1, 2.2 + k * 0.6 }, "chrome", "Cylinder", { rotation = { 0, 0, side * 35 } })
		end
		P(parts, { 0.15, 1.1, 1.7 }, { side * 2.7, 4.1, 3.9 }, "accent")
		P(parts, { 0.2, 3.2, 0.2 }, { side * 1, 2.7, 3.6 }, "dark")
	end
	P(parts, { 5.4, 0.25, 1.8 }, { 0, 4.3, 3.9 }, "accent", nil, { rotation = { -8, 0, 0 } })
	table.insert(bigMotor, {
		id = "dragster", name = "Twin-Turbo Dragster", icon = "🚀", price = 500, realistic = true,
		wheelRadius = 0.6, wheelWidth = 0.6, rearWheelRadius = 1.55, rearWheelWidth = 2.3,
		wheels = { { -1.5, -6.2 }, { 1.5, -6.2 }, { -2.65, 2.9 }, { 2.65, 2.9 } },
		seat = { 0, 0.15, -0.4 }, exhaust = { 0, 1.6, 3.4 }, parts = parts,
	})
end

do -- Dune Hauler: a long-travel trophy truck with a roll cage and light bar.
	local parts: { BodyPart } = {}
	P(parts, { 4.2, 1.1, 7.2 }, { 0, 0.9, -0.2 }, "main", nil, GLOSS)
	P(parts, { 4.2, 0.9, 1.4 }, { 0, 0.8, -3.9 }, "main", "Ellipsoid", GLOSS)
	P(parts, { 4.4, 0.3, 0.5 }, { 0, 0.2, -4.4 }, "chrome")
	v8(parts, 0, 1.1, -2.2, { headers = false })
	for _, side in { -1, 1 } do
		for _, z in { -0.4, 1.6 } do
			P(parts, { 0.2, 2.2, 0.2 }, { side * 1.6, 2.5, z }, "chrome")
		end
		P(parts, { 0.2, 0.2, 2.2 }, { side * 1.6, 3.6, 0.6 }, "chrome")
		for _, z in { -2.7, 2.8 } do
			P(parts, { 1.1, 0.45, 3 }, { side * 2.4, 1.65, z }, "accent", "Ellipsoid")
			P(parts, { 1.8, 0.3, 0.3 }, { side * 1.7, 1.3, z }, "chrome", "Cylinder", { rotation = { 0, 0, side * -50 } })
		end
		P(parts, { 0.4, 0.8, 0.1 }, { side * 1.6, 1.0, 3.45 }, "light", nil, RED_LIGHT)
	end
	for _, z in { -0.4, 1.6 } do
		P(parts, { 3.4, 0.2, 0.2 }, { 0, 3.6, z }, "chrome")
	end
	P(parts, { 3, 0.4, 0.4 }, { 0, 3.85, -0.45 }, "dark")
	for k = -3, 3, 2 do
		P(parts, { 0.12, 0.3, 0.3 }, { k * 0.4, 3.85, -0.7 }, "light", "Cylinder", { rotation = { 0, 90, 0 } })
	end
	P(parts, { 3.8, 0.5, 2.6 }, { 0, 1.6, 2.7 }, "dark")
	P(parts, { 0.9, 1.8, 1.8 }, { 0, 2.3, 2.7 }, "dark", "Cylinder", { rotation = { 0, 0, 90 }, material = "Rubber" })
	table.insert(bigMotor, {
		id = "dunehauler", name = "Dune Hauler", icon = "🛻", price = 300, realistic = true,
		wheelRadius = 1.2, wheelWidth = 1.5,
		wheels = { { -2.6, -2.7 }, { 2.6, -2.7 }, { -2.6, 2.8 }, { 2.6, 2.8 } },
		seat = { 0, 0.9, 0.6 }, exhaust = { 0, 0.8, 4 }, parts = parts,
	})
end

do -- Midnight V12: a low mid-engine speedster, the V12 under a glass cover.
	local parts: { BodyPart } = {}
	P(parts, { 4.4, 0.8, 8.4 }, { 0, 0.05, 0 }, "main", "Ellipsoid", { reflectance = 0.18 })
	P(parts, { 4.2, 0.7, 3.2 }, { 0, 0.35, -2.6 }, "main", "Wedge", { reflectance = 0.18 })
	P(parts, { 2.8, 0.4, 2.2 }, { 0, 0.5, 0 }, "dark")
	P(parts, { 3, 0.6, 0.1 }, { 0, 0.95, -1 }, "glass", nil, { rotation = { -35, 0, 0 } })
	P(parts, { 2.2, 0.7, 2.6 }, { 0, 0.6, 2.4 }, "accent", nil, { material = "Metal", reflectance = 0.1 })
	for k = 0, 5 do
		for _, side in { -1, 1 } do
			P(parts, { 0.5, 0.26, 0.26 }, { side * 0.5, 1.05, 1.4 + k * 0.4 }, "chrome", "Cylinder", { rotation = { 0, 0, 90 }, anim = "engine" })
		end
	end
	P(parts, { 3, 0.15, 3 }, { 0, 1.3, 2.4 }, "glass", nil, { transparency = 0.5 })
	for _, side in { -1, 1 } do
		P(parts, { 0.3, 0.6, 1.6 }, { side * 2.15, 0.4, 1.2 }, "dark")
		P(parts, { 1, 0.15, 0.1 }, { side * 1.4, 0.35, -4.15 }, "light")
		P(parts, { 0.2, 0.7, 0.2 }, { side * 1.6, 1.05, 3.9 }, "dark")
		for k = 0, 1 do
			P(parts, { 0.5, 0.35, 0.35 }, { side * (0.35 + k * 0.5), -0.1, 4.2 }, "chrome", "Cylinder", { rotation = { 0, 90, 0 } })
		end
	end
	P(parts, { 3.6, 0.12, 0.1 }, { 0, 0.55, 4.2 }, "light", nil, RED_LIGHT)
	P(parts, { 4.2, 0.15, 0.8 }, { 0, 1.4, 4 }, "accent")
	table.insert(bigMotor, {
		id = "v12", name = "Midnight V12", icon = "🌙", price = 600, realistic = true,
		wheelRadius = 0.9, wheelWidth = 1.2, rearWheelRadius = 1, rearWheelWidth = 1.6,
		wheels = { { -2.3, -2.7 }, { 2.3, -2.7 }, { -2.35, 2.6 }, { 2.35, 2.6 } },
		seat = { 0, -0.1, 0.2 }, exhaust = { 0, 0, 4.4 }, parts = parts,
	})
end

for _, body in bigMotor do
	table.insert(KartBodies.List, body)
end
-- The racing-style bodies get the realistic finish too.
for _, body in KartBodies.List do
	if table.find({ "embergt", "arrowsprint", "rallycomet", "racer", "buggy", "muscle", "formula" }, body.id) then
		body.realistic = true
	end
end

-- CPU drivers race the realistic cars so every grid shows them off.
KartBodies.CpuBodies = {}
for _, body in KartBodies.List do
	if body.realistic then
		table.insert(KartBodies.CpuBodies, body.id)
	end
end

-- Give the familiar starter body the same visible exhaust detail.
local starter = nil
for _, body in KartBodies.List do if body.id == "classic" then starter = body end end
if starter then
 for _, side in { -1, 1 } do
  table.insert(starter.parts, { size = { 2.4, 1, 1 }, offset = { side * 1.35, 1.1, 2.8 }, role = "chrome", shape = "Cylinder", rotation = { 0, 90, 0 } })
  table.insert(starter.parts, { size = { 0.12, 0.7, 0.7 }, offset = { side * 1.35, 1.1, 4.02 }, role = "dark", shape = "Cylinder", rotation = { 0, 90, 0 } })
 end
end

-- Adds a body at runtime (a car modelled in Blender and dropped into
-- KartAssets.Bodies; see common/Assets). Ignored if the id is taken.
function KartBodies.register(body: Body, cpu: boolean?)
	for _, b in KartBodies.List do
		if b.id == body.id then
			return
		end
	end
	table.insert(KartBodies.List, body)
	if cpu then
		table.insert(KartBodies.CpuBodies, body.id)
	end
end

export type Look = { body: string, main: number, accent: number }

function KartBodies.get(id: string?): Body
	for _, b in KartBodies.List do
		if b.id == id then
			return b
		end
	end
	return KartBodies.get(KartBodies.Default)
end

function KartBodies.color(index: number?): { number }
	local n = #KartBodies.Palette
	local i = math.clamp(math.floor(tonumber(index) or 1), 1, n)
	return KartBodies.Palette[i]
end

-- Cleans a look sent by a client.
function KartBodies.sanitize(look: any): Look
	local t = if type(look) == "table" then look else {}
	return {
		body = KartBodies.get(t.body).id,
		main = math.clamp(math.floor(tonumber(t.main) or 1), 1, #KartBodies.Palette),
		accent = math.clamp(math.floor(tonumber(t.accent) or 10), 1, #KartBodies.Palette),
	}
end

-- A varied look for CPU driver number n (the same every race).
function KartBodies.cpuLook(n: number): Look
	local pool = KartBodies.CpuBodies
	local body = pool[(n * 5 - 1) % #pool + 1]
	local main = (n * 5) % #KartBodies.Palette + 1
	local accent = (n * 7 + 4) % #KartBodies.Palette + 1
	if accent == main then
		accent = accent % #KartBodies.Palette + 1
	end
	return { body = body, main = main, accent = accent }
end

return KartBodies
