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
	shape: ("Block" | "Ball" | "Cylinder" | "Wedge")?,
	rotation: { number }?, -- degrees x, y, z
}

export type Body = {
	id: string,
	name: string,
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
		wheelRadius = 0.8,
		wheelWidth = 0.9,
		wheels = WHEELS_STANDARD,
		seat = { 0, 0.6, 0.6 },
		exhaust = { 0, 0.6, 3.6 },
		parts = {
			{ size = { 4.6, 0.6, 7 }, offset = { 0, 0, 0 }, role = "dark" },
			{ size = { 4.2, 1.2, 4.4 }, offset = { 0, 0.8, -0.6 }, role = "main" },
			{ size = { 3.4, 0.8, 1.6 }, offset = { 0, 0.5, -3.4 }, role = "main" },
			{ size = { 4.4, 0.25, 1 }, offset = { 0, 2.2, 3.2 }, role = "accent" },
			{ size = { 0.3, 1.4, 0.3 }, offset = { 0, 1.4, 3.2 }, role = "dark" },
			{ size = { 3.6, 0.3, 0.3 }, offset = { 0, 0.7, -4.2 }, role = "chrome" },
		},
	},
	{
		id = "racer",
		name = "Wedge Racer",
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
		id = "bubble",
		name = "Bubble",
		wheelRadius = 0.7,
		wheelWidth = 0.9,
		wheels = { { -2.2, -2 }, { 2.2, -2 }, { -2.2, 2 }, { 2.2, 2 } },
		seat = { 0, 0.5, 0.3 },
		exhaust = { 0, 0.5, 3 },
		parts = {
			{ size = { 4.6, 4.6, 4.6 }, offset = { 0, 0.9, 0.2 }, role = "main", shape = "Ball" },
			{ size = { 3.4, 3.4, 3.4 }, offset = { 0, 1.9, -0.4 }, role = "glass", shape = "Ball" },
			{ size = { 4.2, 0.5, 6 }, offset = { 0, -0.1, 0 }, role = "dark" },
			{ size = { 1.2, 1.2, 1.2 }, offset = { -1.4, 0.8, -2.2 }, role = "light", shape = "Ball" },
			{ size = { 1.2, 1.2, 1.2 }, offset = { 1.4, 0.8, -2.2 }, role = "light", shape = "Ball" },
			{ size = { 0.25, 1.8, 0.25 }, offset = { 1.2, 3.6, 1.6 }, role = "dark" },
			{ size = { 0.9, 0.9, 0.9 }, offset = { 1.2, 4.6, 1.6 }, role = "accent", shape = "Ball" },
		},
	},
	{
		id = "formula",
		name = "Formula",
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
