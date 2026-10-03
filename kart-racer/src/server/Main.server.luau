-- Server entry point.

local RaceService = require(script.Parent.RaceService)
local RoundService = require(script.Parent.RoundService)

RaceService.start()
RoundService.start()

print("[KartRacer] server ready - walk under the READY arch (or press READY) to race")
