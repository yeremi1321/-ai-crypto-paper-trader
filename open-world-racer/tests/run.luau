-- Run with: lune run tests/run   (from the open-world-racer folder)
local process = require("@lune/process")
local T = require("./TestLib")

require("./CarCatalog.spec")
require("./RaceLogic.spec")
require("./Progression.spec")
require("./Records.spec")
require("./WorldMap.spec")
require("./WorldClock.spec")
require("./EngineAudio.spec")
require("./PlayerProfile.spec")

print(`{T.passed} passed, {T.failed} failed`)
if T.failed > 0 then
	process.exit(1)
end
