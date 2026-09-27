-- Server entry point. Order matters: data first, then the world, then the
-- services that place cars and races in it.

local DataService = require(script.Parent.DataService)
local WorldBuilder = require(script.Parent.WorldBuilder)
local GarageService = require(script.Parent.GarageService)
local RaceService = require(script.Parent.RaceService)
local WorldEventService = require(script.Parent.WorldEventService)
local DiscoveryService = require(script.Parent.DiscoveryService)

DataService.start()
WorldBuilder.build()
GarageService.start()
RaceService.start()
WorldEventService.start()
DiscoveryService.start()
