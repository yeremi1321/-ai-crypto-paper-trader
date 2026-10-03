-- Server entry point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Cars modelled in Blender (ReplicatedStorage.KartAssets.Bodies) join the
-- garage before anyone's saved data is checked against the list.
require(ReplicatedStorage.Common.Assets).registerBodies()

local DataService = require(script.Parent.DataService)
local RaceService = require(script.Parent.RaceService)
local RoundService = require(script.Parent.RoundService)

DataService.start()
RaceService.start()
RoundService.start()

print("[KartRacer] server ready - press READY or step onto a vote pad to race")
