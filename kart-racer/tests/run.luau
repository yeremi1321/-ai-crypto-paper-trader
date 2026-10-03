-- Run with: lune run tests/run   (from the kart-racer folder)
local process = require("@lune/process")
local T = require("./TestLib")

require("./KartPhysics.spec")
require("./Track.spec")
require("./TrackFeatures.spec")
require("./Items.spec")
require("./RaceRules.spec")
require("./Progression.spec")
require("./Voting.spec")
require("./Lobby.spec")
require("./Scenery.spec")
require("./Landscape.spec")
require("./KartBodies.spec")
require("./Simulation.spec")

print(`{T.passed} passed, {T.failed} failed`)
if T.failed > 0 then
	process.exit(1)
end
