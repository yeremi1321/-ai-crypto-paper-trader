local T = require("./TestLib")
local LobbyLayout = require("../src/shared/LobbyLayout")
local Track = require("../src/shared/Track")
local Tracks = require("../src/shared/Tracks")

T.test("lobby is far away from every race track", function()
	local o = LobbyLayout.Origin
	for _, def in Tracks.List do
		local track = Track.build(def)
		for _, p in track.points do
			local d = math.sqrt((p.x - o.x) ^ 2 + (p.z - o.z) ^ 2)
			T.ok(d > 2000, `{def.id} comes within {math.floor(d)} studs of the lobby`)
		end
	end
end)

T.test("vote pads are found by position and don't overlap", function()
	T.eq(#LobbyLayout.VotePads, 4)
	for i, pad in LobbyLayout.VotePads do
		T.eq(LobbyLayout.padAt(pad.x, pad.z), i)
	end
	T.eq(LobbyLayout.padAt(LobbyLayout.Spawn.x, LobbyLayout.Spawn.z), nil)
	T.ok(LobbyLayout.inChamber(LobbyLayout.Spawn.x, LobbyLayout.Spawn.z))
end)

T.test("compact lobby has no practice or viewing rooms", function()
 T.eq(LobbyLayout.roomById("practice"), nil)
 T.eq(LobbyLayout.roomById("lounge"), nil)
 T.ok(LobbyLayout.HalfWidth * 2 <= 140)
 T.ok(LobbyLayout.HalfDepth * 2 <= 160)
 for _, token in LobbyLayout.Collectibles do
  local accessible = LobbyLayout.inChamber(token.x, token.z)
  for _, room in LobbyLayout.Rooms do
   accessible = accessible or LobbyLayout.inBox(room.box, token.x, token.z)
  end
  T.ok(accessible, "collectible is inside a retained area")
 end
end)

T.test("vote pool tracks have voting card info", function()
	for _, id in Tracks.VotePool do
		local def = Tracks.get(id)
		T.ok(def.difficulty and def.feature and def.icon, `{id} missing card info`)
	end
	T.ok(#Tracks.VotePool >= 3)
end)
