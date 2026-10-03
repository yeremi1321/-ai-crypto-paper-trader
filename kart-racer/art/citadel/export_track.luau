-- Export the actual playable track for the Blender scenery generator.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Track = require("../../src/shared/Track")
local Tracks = require("../../src/shared/Tracks")
local RoadGeometry = require("../../src/shared/RoadGeometry")
local track = Track.build(Tracks.get("emberfort"))
fs.writeFile("art/citadel/track.json", serde.encode("json", {
 id = track.def.id, name = track.def.name, width = track.def.width,
 length = track.length, frames = RoadGeometry.frames(track),
 itemRows = track.def.itemRows, boostPads = track.def.boostPads,
}, true))
print(`Exported {#track.points} road frames, {track.length} studs`)
