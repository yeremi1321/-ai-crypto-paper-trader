--!strict
-- Names of every RemoteEvent the server creates under ReplicatedStorage.Remotes.

return {
	-- server -> client
	Round = "Round", -- (state) lobby phase, countdowns, vote options, live race summary
	RaceStart = "RaceStart", -- (info) track id, your kart, grid yaw, GO time
	PracticeStart = "PracticeStart", -- (info) your practice kart on the lobby loop
	RaceState = "RaceState", -- (info) standings, your lap/place, about 5x a second
	KartEvent = "KartEvent", -- (kind, value) "spin" | "slow" | "launch" | "boost" | "overdrive" | "respawn" | "warning"
	ItemState = "ItemState", -- (itemId?, uses, readyAt)
	Results = "Results", -- (info) placements and rewards
	Notify = "Notify", -- (text)
	OpenGarage = "OpenGarage", -- () the garage prompt was used
	Profile = "Profile", -- (data, canSave) your coins, unlocks, equipped kart, settings, records
	Honk = "Honk", -- (kartName, text) someone honked
	Spectate = "Spectate", -- () start watching the current race

	-- client -> server
	GarageAction = "GarageAction", -- (action, kind, value) buy / equip / text / setting
	HonkRequest = "HonkRequest", -- () press H to honk your horn
	Ready = "Ready", -- (isReady)
	Vote = "Vote", -- (trackId) same as standing on a vote pad
	UseItem = "UseItem", -- (aimBack) aimBack = throw/drop behind you
	Respawn = "Respawn", -- () put my stuck kart back on the road
	LeavePractice = "LeavePractice", -- ()
}
