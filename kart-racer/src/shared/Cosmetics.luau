--!strict
-- Kart cosmetics you unlock with coins. They change looks only, never speed
-- or handling, so every choice stays equally competitive.

local KartBodies = require("./KartBodies")

export type Item = { id: string, name: string, price: number, icon: string? }

local Cosmetics = {}

-- Wheel styles: radius and width multipliers on the body's own wheels.
Cosmetics.Wheels = {
	{ id = "standard", name = "Standard", price = 0, icon = "⚫", radius = 1, width = 1, color = { 26, 26, 30 } },
	{ id = "chunky", name = "Chunky", price = 150, icon = "🛞", radius = 1.15, width = 1.5, color = { 30, 30, 34 } },
	{ id = "slick", name = "Slick", price = 150, icon = "🏁", radius = 0.95, width = 1.25, color = { 20, 20, 24 } },
	{ id = "monster", name = "Monster", price = 400, icon = "🦖", radius = 1.35, width = 1.4, color = { 34, 30, 28 } },
	{ id = "whitewall", name = "Whitewall", price = 250, icon = "⚪", radius = 1, width = 1.1, color = { 240, 240, 245 } },
	{ id = "neon", name = "Neon Rims", price = 500, icon = "💡", radius = 1.05, width = 1.1, color = { 20, 20, 26 }, glow = true },
}

-- Stickers go on both sides of the body.
Cosmetics.Stickers = {
	{ id = "none", name = "None", price = 0, icon = "🚫" },
	{ id = "star", name = "Star", price = 50, icon = "⭐" },
	{ id = "flame", name = "Flames", price = 100, icon = "🔥" },
	{ id = "bolt", name = "Lightning", price = 100, icon = "⚡" },
	{ id = "rainbow", name = "Rainbow", price = 150, icon = "🌈" },
	{ id = "cool", name = "Cool", price = 150, icon = "😎" },
	{ id = "frog", name = "Frog", price = 200, icon = "🐸" },
	{ id = "pizza", name = "Pizza", price = 200, icon = "🍕" },
	{ id = "hundred", name = "Hundred", price = 300, icon = "💯" },
}

-- Horns: a sound id when you have one uploaded; otherwise a "HONK!" bubble.
Cosmetics.Horns = {
	{ id = "beep", name = "Beep Beep", price = 0, icon = "📯", text = "BEEP BEEP!", soundId = "" },
	{ id = "duck", name = "Rubber Duck", price = 100, icon = "🦆", text = "QUACK!", soundId = "" },
	{ id = "trumpet", name = "Fanfare", price = 200, icon = "🎺", text = "TA-DAAA!", soundId = "" },
	{ id = "moo", name = "Moo", price = 200, icon = "🐄", text = "MOOO!", soundId = "" },
	{ id = "boing", name = "Boing", price = 250, icon = "🪀", text = "BOING!", soundId = "" },
}

-- Trails streaming from the back of the kart.
Cosmetics.Trails = {
	{ id = "none", name = "None", price = 0, icon = "🚫", colors = {} },
	{ id = "smoke", name = "Puffy Smoke", price = 0, icon = "☁️", colors = { { 240, 240, 245 }, { 200, 200, 210 } } },
	{ id = "rainbow", name = "Rainbow", price = 300, icon = "🌈", colors = { { 255, 80, 80 }, { 255, 210, 60 }, { 80, 220, 120 }, { 80, 150, 255 }, { 190, 110, 255 } } },
	{ id = "fire", name = "Fire", price = 300, icon = "🔥", colors = { { 255, 220, 80 }, { 255, 110, 40 }, { 200, 40, 40 } } },
	{ id = "ice", name = "Ice", price = 300, icon = "❄️", colors = { { 230, 250, 255 }, { 120, 200, 255 } } },
	{ id = "bubbles", name = "Bubbles", price = 250, icon = "🫧", colors = { { 200, 235, 255 }, { 255, 200, 240 } } },
}

Cosmetics.PlateMaxLength = 8
Cosmetics.NameMaxLength = 16

local LISTS: { [string]: { any } } = {
	wheels = Cosmetics.Wheels,
	sticker = Cosmetics.Stickers,
	horn = Cosmetics.Horns,
	trail = Cosmetics.Trails,
}
Cosmetics.Lists = LISTS

function Cosmetics.find(kind: string, id: string?): any?
	if kind == "body" then
		for _, b in KartBodies.List do
			if b.id == id then
				return b
			end
		end
		return nil
	end
	for _, item in LISTS[kind] or {} do
		if item.id == id then
			return item
		end
	end
	return nil
end

function Cosmetics.price(kind: string, id: string): number?
	local item = Cosmetics.find(kind, id)
	if not item then
		return nil
	end
	return item.price or 0
end

-- Defaults every new player owns.
function Cosmetics.starterOwned(): { [string]: { [string]: boolean } }
	local owned: { [string]: { [string]: boolean } } = { body = {} }
	for _, b in KartBodies.List do
		if (b :: any).price == nil or (b :: any).price == 0 then
			owned.body[b.id] = true
		end
	end
	for kind, list in LISTS do
		owned[kind] = {}
		for _, item in list do
			if item.price == 0 then
				owned[kind][item.id] = true
			end
		end
	end
	return owned
end

-- Plate and name text: letters, numbers and spaces only, trimmed to length.
-- (The server also runs Roblox text filtering before anyone else sees it.)
function Cosmetics.cleanText(text: any, maxLength: number): string
	local s = if type(text) == "string" then text else ""
	s = string.gsub(s, "[^%w ]", "")
	s = string.gsub(s, "%s+", " ")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return string.sub(s, 1, maxLength)
end

return Cosmetics
