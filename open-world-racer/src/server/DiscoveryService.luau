-- Things to find between races: speed traps, drift zones, hidden parts and
-- scenic roads. Scores go on local leaderboards at each spot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CarCatalog = require(Shared.CarCatalog)
local PlayerProfile = require(Shared.PlayerProfile)
local WorldMap = require(Shared.WorldMap)

local DataService = require(script.Parent.DataService)
local GarageService = require(script.Parent.GarageService)
local Net = require(script.Parent.Net)

local DiscoveryService = {}

local STEP = 0.2
local STUDS_TO_MPH = 0.28 * 2.237 -- 1 stud ~ 0.28 m
local SCENIC_REWARD = 250
local DRIFT_MIN_SPEED = 30
local DRIFT_MIN_ANGLE = math.rad(12)

type DriftRun = { zoneId: string, score: number }
local drifts: { [Player]: DriftRun } = {}
local insideTrap: { [Player]: string } = {}

local function flatDist(a: Vector3, pt: WorldMap.Point): number
	return Vector3.new(a.X - pt.x, 0, a.Z - pt.z).Magnitude
end

local function mph(speed: number): number
	return math.floor(speed * STUDS_TO_MPH + 0.5)
end

local function firstFind(player: Player, d: WorldMap.Discovery)
	local profile = DataService.get(player)
	if not profile or not PlayerProfile.discover(profile, d.id) then
		return
	end
	if d.kind == "hiddenPart" and d.reward then
		PlayerProfile.givePart(profile, d.reward)
		local part = CarCatalog.getPart(d.reward)
		Net.Notify:FireClient(player, `Found a stash: {part and part.name or d.reward}! Install it at your garage.`, "discovery")
	elseif d.kind == "scenic" then
		profile.cash += SCENIC_REWARD
		Net.Notify:FireClient(player, `Scenic road discovered: {d.name} (+${SCENIC_REWARD})`, "discovery")
	else
		Net.Notify:FireClient(player, `Discovered {d.name}`, "discovery")
	end
	GarageService.pushProfile(player)
end

local function endDrift(player: Player)
	local run = drifts[player]
	drifts[player] = nil
	if not run or run.score < 100 then
		return
	end
	local score = math.floor(run.score)
	local car = GarageService.getCar(player)
	local rank = DataService.submitRecord(`drift:{run.zoneId}`, {
		userId = player.UserId,
		name = player.DisplayName,
		time = score,
		carId = if car then car:GetAttribute("CarId") else "",
	}, true)
	local profile = DataService.get(player)
	if profile then
		profile.cash += math.floor(score / 20)
		GarageService.pushProfile(player)
	end
	Net.Notify:FireClient(player, `Drift score {score}` .. (if rank then ` - #{rank} here!` else ""), "discovery")
end

local function stepPlayer(player: Player)
	if not GarageService.isDriving(player) then
		endDrift(player)
		insideTrap[player] = nil
		return
	end
	local car = GarageService.getCar(player)
	local root = car and car.PrimaryPart
	if not root then
		return
	end
	local pos = root.Position
	local vel = root.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local speed = flatVel.Magnitude

	local inDriftZone: string? = nil
	for _, d in WorldMap.Discoveries do
		if flatDist(pos, d.pos) > d.radius then
			if insideTrap[player] == d.id then
				insideTrap[player] = nil
			end
			continue
		end
		firstFind(player, d)

		if d.kind == "speedTrap" and insideTrap[player] ~= d.id then
			insideTrap[player] = d.id
			local value = mph(speed)
			local rank = DataService.submitRecord(`trap:{d.id}`, {
				userId = player.UserId,
				name = player.DisplayName,
				time = value,
				carId = car:GetAttribute("CarId"),
			}, true)
			Net.Notify:FireClient(player, `{d.name}: {value} mph` .. (if rank then ` - #{rank} here!` else ""), "trap")
		elseif d.kind == "driftZone" then
			inDriftZone = d.id
			local run = drifts[player]
			if not run or run.zoneId ~= d.id then
				run = { zoneId = d.id, score = 0 }
				drifts[player] = run
			end
			if speed >= DRIFT_MIN_SPEED then
				local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
				local angle = math.acos(math.clamp(look:Dot(flatVel.Unit), -1, 1))
				if angle >= DRIFT_MIN_ANGLE and angle <= math.rad(100) then
					run.score += speed * math.sin(angle) * STEP
				end
			end
		end
	end

	if not inDriftZone and drifts[player] then
		endDrift(player)
	end
end

function DiscoveryService.start()
	Players.PlayerRemoving:Connect(function(player)
		drifts[player] = nil
		insideTrap[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(STEP)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(stepPlayer, player)
				if not ok then
					warn("[DiscoveryService]", err)
				end
			end
		end
	end)
end

return DiscoveryService
