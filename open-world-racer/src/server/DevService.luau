-- Test shortcuts for Roblox Studio only. Live servers ignore every request, so
-- this can never be used to cheat in a published game.
--   F6  skip to dusk (meet clue)     F7  skip to the midnight meet
--   F8  open a flash race now        F9  +$50,000

local RunService = game:GetService("RunService")

local DataService = require(script.Parent.DataService)
local GarageService = require(script.Parent.GarageService)
local Net = require(script.Parent.Net)
local WorldEventService = require(script.Parent.WorldEventService)

local DevService = {}

local COMMANDS: { [string]: (Player) -> string } = {
	dusk = function()
		WorldEventService.skipToHour(18.2)
		return "Skipped to dusk - the meet clue is up."
	end,
	meet = function()
		WorldEventService.skipToHour(23.55)
		return "Skipped to 23:30 - the midnight meet is opening."
	end,
	flash = function()
		WorldEventService.flashNow()
		return "Flash race opened."
	end,
	cash = function(player)
		local profile = DataService.get(player)
		if profile then
			profile.cash += 50000
			GarageService.pushProfile(player)
		end
		return "+$50,000"
	end,
}

function DevService.start()
	Net.Dev.OnServerEvent:Connect(function(player, command)
		if not RunService:IsStudio() then
			return
		end
		local run = COMMANDS[tostring(command)]
		if run then
			Net.Notify:FireClient(player, `[Dev] {run(player)}`, "info")
		end
	end)
end

return DevService
