-- Run with: lune run tests/run   (from the kart-racer folder)
local process = require("@lune/process")
local T = require("./TestLib")

require("./KartPhysics.spec")
require("./Track.spec")
require("./Items.spec")
require("./RaceRules.spec")
require("./Simulation.spec")

print(`{T.passed} passed, {T.failed} failed`)
if T.failed > 0 then
	process.exit(1)
end
