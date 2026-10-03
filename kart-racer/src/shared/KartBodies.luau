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
	-- jelly, "rattle" lid, "orbit" lights circling the kart.
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
	local body = KartBodies.List[(n - 1) % #KartBodies.List + 1].id
	local main = (n * 5) % #KartBodies.Palette + 1
	local accent = (n * 7 + 4) % #KartBodies.Palette + 1
	if accent == main then
		accent = accent % #KartBodies.Palette + 1
	end
	return { body = body, main = main, accent = accent }
end

return KartBodies
