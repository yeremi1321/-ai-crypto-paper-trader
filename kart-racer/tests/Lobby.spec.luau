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

T.test("practice loop sits inside the practice area, away from the chamber", function()
	local track = Track.build(LobbyLayout.PracticeTrack)
	local area = LobbyLayout.PracticeArea
	for _, p in track.points do
		T.ok(p.x > area.min.x and p.x < area.max.x and p.z > area.min.z and p.z < area.max.z, "loop leaves the practice area")
		T.ok(not LobbyLayout.inChamber(p.x, p.z), "loop crosses the chamber")
	end
	T.eq(Tracks.get("practice"), LobbyLayout.PracticeTrack)
	T.ok(#LobbyLayout.PracticeTrack.ramps >= 1, "practice has a jump ramp")
end)

T.test("vote pool tracks have voting card info", function()
	for _, id in Tracks.VotePool do
		local def = Tracks.get(id)
		T.ok(def.difficulty and def.feature and def.icon, `{id} missing card info`)
	end
	T.ok(#Tracks.VotePool >= 3)
end)
