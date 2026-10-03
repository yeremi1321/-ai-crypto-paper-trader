--!strict
-- A player's saved data and every rule for changing it: coins, unlocked and
-- equipped cosmetics, kart name and plate, settings, best laps, mastery,
-- lifetime stats and challenges. Pure data so the server validates
-- purchases and rewards in one tested place.

local Cosmetics = require("./Cosmetics")
local KartBodies = require("./KartBodies")
local Karts = require("./Karts")
local Rewards = require("./Rewards")

export type Equipped = {
	kart: string, -- stats class
	body: string,
	main: number,
	accent: number,
	wheels: string,
	sticker: string,
	horn: string,
	trail: string,
	plate: string,
	name: string,
}

export type Mastery = { races: number, finishes: number, podiums: number, wins: number, bestLap: number?, bestRace: number? }

export type Data = {
	version: number,
	coins: number,
	owned: { [string]: { [string]: boolean } },
	equipped: Equipped,
	settings: { autoAccelerate: boolean, reducedEffects: boolean, cameraFar: boolean },
	mastery: { [string]: Mastery },
	stats: { races: number, wins: number, podiums: number, shortcuts: number, cleanRaces: number, jumps: number, improvedLaps: number },
	challenges: { [string]: boolean },
	tokens: { [string]: boolean },
}

local PlayerData = {}

PlayerData.Version = 1
PlayerData.StartingCoins = 200

function PlayerData.new(): Data
	return {
		version = PlayerData.Version,
		coins = PlayerData.StartingCoins,
		owned = Cosmetics.starterOwned(),
		equipped = {
			kart = Karts.Default,
			body = KartBodies.Default,
			main = 1,
			accent = 10,
			wheels = "standard",
			sticker = "none",
			horn = "beep",
			trail = "smoke",
			plate = "",
			name = "",
		},
		settings = { autoAccelerate = false, reducedEffects = false, cameraFar = false },
		mastery = {},
		stats = { races = 0, wins = 0, podiums = 0, shortcuts = 0, cleanRaces = 0, jumps = 0, improvedLaps = 0 },
		challenges = {},
		tokens = {},
	}
end

-- Fills in anything missing from older or damaged saves.
function PlayerData.migrate(saved: any): Data
	local fresh = PlayerData.new()
	if type(saved) ~= "table" then
		return fresh
	end
	local function merge(into: any, defaults: any)
		for k, v in defaults do
			if into[k] == nil or type(into[k]) ~= type(v) then
				into[k] = v
			elseif type(v) == "table" and next(v) ~= nil and type(next(v)) == "string" then
				merge(into[k], v)
			end
		end
	end
	merge(saved, fresh)
	-- Make sure starter items stay owned even if the catalog grew.
	for kind, ids in Cosmetics.starterOwned() do
		saved.owned[kind] = saved.owned[kind] or {}
		for id in ids do
			saved.owned[kind][id] = true
		end
	end
	saved.version = PlayerData.Version
	PlayerData.validateEquipped(saved)
	return saved
end

-- Puts back defaults for anything equipped that isn't owned or no longer exists.
function PlayerData.validateEquipped(d: Data)
	local e = d.equipped
	if not Cosmetics.find("body", e.body) or not d.owned.body[e.body] then
		e.body = KartBodies.Default
	end
	for kind, default in { wheels = "standard", sticker = "none", horn = "beep", trail = "smoke" } do
		local id = (e :: any)[kind]
		if not Cosmetics.find(kind, id) or not (d.owned[kind] or {})[id] then
			(e :: any)[kind] = default
		end
	end
	e.kart = Karts.get(e.kart).id
	e.main = math.clamp(math.floor(tonumber(e.main) or 1), 1, #KartBodies.Palette)
	e.accent = math.clamp(math.floor(tonumber(e.accent) or 10), 1, #KartBodies.Palette)
	e.plate = Cosmetics.cleanText(e.plate, Cosmetics.PlateMaxLength)
	e.name = Cosmetics.cleanText(e.name, Cosmetics.NameMaxLength)
end

function PlayerData.owns(d: Data, kind: string, id: string): boolean
	return (d.owned[kind] or {})[id] == true
end

function PlayerData.buy(d: Data, kind: string, id: string): (boolean, string?)
	local price = Cosmetics.price(kind, id)
	if price == nil then
		return false, "That item doesn't exist"
	end
	if PlayerData.owns(d, kind, id) then
		return false, "You already own it"
	end
	if d.coins < price then
		return false, "Not enough coins"
	end
	d.coins -= price
	d.owned[kind] = d.owned[kind] or {}
	d.owned[kind][id] = true
	return true
end

-- Equip a cosmetic you own, a kart class, or paint.
function PlayerData.equip(d: Data, kind: string, value: any): (boolean, string?)
	local e = d.equipped
	if kind == "kart" then
		e.kart = Karts.get(tostring(value)).id
		return true
	elseif kind == "main" or kind == "accent" then
		local n = math.floor(tonumber(value) or 0)
		if n < 1 or n > #KartBodies.Palette then
			return false, "Unknown colour"
		end
		(e :: any)[kind] = n
		return true
	elseif kind == "body" or Cosmetics.Lists[kind] then
		local id = tostring(value)
		if not Cosmetics.find(kind, id) then
			return false, "That item doesn't exist"
		end
		if not PlayerData.owns(d, kind, id) then
			return false, "Unlock it first"
		end
		(e :: any)[kind] = id
		return true
	end
	return false, "Unknown setting"
end

-- What the kart builder needs (KartRig look).
function PlayerData.look(d: Data)
	local e = d.equipped
	return {
		body = e.body,
		main = e.main,
		accent = e.accent,
		wheels = e.wheels,
		sticker = e.sticker,
		trail = e.trail,
		plate = e.plate,
	}
end

export type RaceSummary = {
	coins: number,
	lines: { string },
	newBestLap: boolean,
	badge: number?,
	challenges: { string },
}

-- Applies one race to the save data and returns what was earned.
-- `stats` comes from the server's own tracking of that race.
function PlayerData.applyRace(d: Data, trackId: string, trackLength: number, trackCount: number, stats: Rewards.RaceStats, awardIds: { string }): RaceSummary
	local summary: RaceSummary = { coins = 0, lines = {}, newBestLap = false, badge = nil, challenges = {} }
	local function earn(amount: number, line: string)
		summary.coins += amount
		d.coins += amount
		table.insert(summary.lines, `+{amount} 🪙  {line}`)
	end

	earn(Rewards.placeCoins(stats.place, stats.finished), if stats.finished then `Finished {stats.place}` else "Took part")
	for _, id in awardIds do
		local info = Rewards.AwardInfo[id]
		earn(Rewards.AwardCoins, `{info.icon} {info.name}`)
	end

	-- Lifetime stats.
	local s = d.stats
	s.races += 1
	s.shortcuts += stats.shortcutsTaken
	s.jumps += stats.jumps
	if stats.finished then
		if stats.place == 1 then
			s.wins += 1
		end
		if stats.place <= 3 then
			s.podiums += 1
		end
		if stats.hitsTaken == 0 then
			s.cleanRaces += 1
		end
	end

	-- Track mastery and personal bests.
	local m = d.mastery[trackId]
	if not m then
		m = { races = 0, finishes = 0, podiums = 0, wins = 0 }
		d.mastery[trackId] = m
	end
	local before = Rewards.badge(m, trackLength)
	m.races += 1
	if stats.finished then
		m.finishes += 1
		if stats.place <= 3 then
			m.podiums += 1
		end
		if stats.place == 1 then
			m.wins += 1
		end
		if stats.time and (not m.bestRace or stats.time < m.bestRace) then
			m.bestRace = stats.time
		end
	end
	if stats.bestLap then
		if m.bestLap and stats.bestLap < m.bestLap then
			s.improvedLaps += 1
			summary.newBestLap = true
			table.insert(summary.lines, "⏱ New best lap!")
		elseif not m.bestLap then
			summary.newBestLap = true
		end
		if not m.bestLap or stats.bestLap < m.bestLap then
			m.bestLap = stats.bestLap
		end
	end
	local after = Rewards.badge(m, trackLength)
	if after > before then
		summary.badge = after
		table.insert(summary.lines, `{Rewards.BadgeIcons[after]} {Rewards.BadgeNames[after]} mastery badge!`)
	end

	-- Challenges.
	local tracksRaced = 0
	for _ in d.mastery do
		tracksRaced += 1
	end
	local tokenCount = 0
	for _ in d.tokens do
		tokenCount += 1
	end
	local view = {
		wins = s.wins,
		podiums = s.podiums,
		shortcuts = s.shortcuts,
		cleanRaces = s.cleanRaces,
		jumps = s.jumps,
		improvedLaps = s.improvedLaps,
		tracksRaced = tracksRaced,
		trackCount = trackCount,
		tokens = tokenCount,
		tokenCount = math.huge, -- tokens are checked when found, not after races
	}
	for _, c in Rewards.Challenges do
		if not d.challenges[c.id] and c.check(view) then
			d.challenges[c.id] = true
			table.insert(summary.challenges, c.name)
			earn(c.reward, `✅ Challenge: {c.name}`)
		end
	end
	return summary
end

-- A golden token found in the lobby. Returns coins earned (0 if already found).
function PlayerData.foundToken(d: Data, tokenId: string, totalTokens: number): (number, boolean)
	if d.tokens[tokenId] then
		return 0, false
	end
	d.tokens[tokenId] = true
	local coins = Rewards.TokenCoins
	local count = 0
	for _ in d.tokens do
		count += 1
	end
	local completedAll = false
	if count >= totalTokens and not d.challenges.tokens then
		d.challenges.tokens = true
		for _, c in Rewards.Challenges do
			if c.id == "tokens" then
				coins += c.reward
			end
		end
		completedAll = true
	end
	d.coins += coins
	return coins, completedAll
end

function PlayerData.setSetting(d: Data, key: string, value: any): boolean
	if d.settings[key] == nil or type(value) ~= "boolean" then
		return false
	end
	(d.settings :: any)[key] = value
	return true
end

return PlayerData
