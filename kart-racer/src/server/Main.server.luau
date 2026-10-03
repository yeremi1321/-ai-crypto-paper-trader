-- Server entry point.

local DataService = require(script.Parent.DataService)
local RaceService = require(script.Parent.RaceService)
local RoundService = require(script.Parent.RoundService)

DataService.start()
RaceService.start()
RoundService.start()

print("[KartRacer] server ready - walk under the READY arch (or press READY) to race")
