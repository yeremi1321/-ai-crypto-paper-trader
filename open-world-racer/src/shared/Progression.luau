--!strict
-- Cash payouts and per-district street reputation.
-- Winning on the Harbor Ring makes you known there; the drag strip keeps its
-- own scene, so reputation is tracked per district.

local Progression = {}

Progression.StartingCash = 3000

Progression.RepTiers = {
	{ name = "Unknown", min = 0 },
	{ name = "Regular", min = 100 },
	{ name = "Known", min = 350 },
	{ name = "Respected", min = 800 },
	{ name = "Legend", min = 1600 },
}

local BASE_PAYOUT: { [string]: number } = {
	circuit = 1800,
	sprint = 1400,
	drag = 900,
	flash = 1600,
	midnight = 3000,
}

-- Share of the base payout by finishing place.
local PLACE_SHARE = { 1.0, 0.6, 0.4, 0.25 }
local MIN_SHARE = 0.15

-- Bigger fields pay more, capped so solo play is still worth it.
local function fieldMultiplier(fieldSize: number): number
	return 1 + math.min(math.max(fieldSize - 1, 0), 7) * 0.1
end

function Progression.payout(kind: string, place: number, fieldSize: number, dnf: boolean?): number
	if dnf then
		return 0
	end
	local base = BASE_PAYOUT[kind] or BASE_PAYOUT.sprint
	local share = PLACE_SHARE[place] or MIN_SHARE
	return math.floor(base * share * fieldMultiplier(fieldSize) + 0.5)
end

function Progression.repGain(place: number, fieldSize: number, dnf: boolean?): number
	if dnf then
		return 0
	end
	-- Beating people counts more than just showing up.
	local beaten = math.max(fieldSize - place, 0)
	local base = if place == 1 then 30 else 10
	return base + beaten * 8
end

function Progression.tierFor(rep: number): string
	local tier = Progression.RepTiers[1].name
	for _, t in Progression.RepTiers do
		if rep >= t.min then
			tier = t.name
		end
	end
	return tier
end

-- Street name shown over a player's car: their best district.
function Progression.title(repByDistrict: { [string]: number }, districtNames: { [string]: string }): string
	local bestId, bestRep = nil :: string?, 0
	for id, rep in repByDistrict do
		if rep > bestRep or (rep == bestRep and bestId ~= nil and id < bestId) then
			bestId, bestRep = id, rep
		end
	end
	if not bestId or bestRep < Progression.RepTiers[2].min then
		return "Newcomer"
	end
	return `{Progression.tierFor(bestRep)} of {districtNames[bestId] or bestId}`
end

return Progression
