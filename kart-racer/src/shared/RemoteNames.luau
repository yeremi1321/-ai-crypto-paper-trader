--!strict
-- Names of every RemoteEvent the server creates under ReplicatedStorage.Remotes.

return {
	-- server -> client
	Lobby = "Lobby", -- (state) lobby screen: who's ready, countdown
	RaceStart = "RaceStart", -- (info) track id, your kart, grid yaw, GO time
	RaceState = "RaceState", -- (info) standings, your lap/place, about 5x a second
	KartEvent = "KartEvent", -- (kind, value) "hit" | "boost" | "overdrive" | "respawn"
	ItemState = "ItemState", -- (itemId?, uses, readyAt)
	Results = "Results", -- (info) race results or final cup standings
	Notify = "Notify", -- (text)

	-- client -> server
	ChooseKart = "ChooseKart", -- (kartId)
	Ready = "Ready", -- (isReady)
	UseItem = "UseItem", -- ()
}
