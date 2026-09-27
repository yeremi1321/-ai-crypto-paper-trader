--!strict
-- Names of every RemoteEvent the server creates under ReplicatedStorage.Remotes.
-- (World state - flash race, midnight meet, rain - is a JSON attribute
-- "WorldState" on ReplicatedStorage instead, so late joiners see it.)

return {
	-- server -> client
	ProfileUpdated = "ProfileUpdated", -- (summary)
	Notify = "Notify", -- (text, kind)
	RaceState = "RaceState", -- (state table or nil)
	ChallengeReceived = "ChallengeReceived", -- (fromUserId, fromName, destinationName)
	OpenShop = "OpenShop", -- (placeKind)

	-- client -> server
	ShopAction = "ShopAction", -- (action, ...)
	Challenge = "Challenge", -- (targetUserId)
	ChallengeReply = "ChallengeReply", -- (fromUserId, accepted)
	RespawnCar = "RespawnCar", -- ()
}
