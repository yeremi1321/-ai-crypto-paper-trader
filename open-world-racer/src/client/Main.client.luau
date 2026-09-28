-- Client entry point: wires remotes to the HUD, menus, driving and ambience.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Ambience = require(script.Parent.Ambience)
local DriveController = require(script.Parent.DriveController)
local Hud = require(script.Parent.Hud)
local ShopMenu = require(script.Parent.ShopMenu)

local STUDS_TO_MPH = 0.28 * 2.237
local CHALLENGE_RANGE = 150
local player = Players.LocalPlayer

DriveController.start()
Ambience.start()

Remotes.ProfileUpdated.OnClientEvent:Connect(function(profile)
	Hud.setProfile(profile)
	ShopMenu.setProfile(profile)
end)
Remotes.Notify.OnClientEvent:Connect(Hud.notify)
Remotes.RaceState.OnClientEvent:Connect(Hud.setRace)
Remotes.OpenShop.OnClientEvent:Connect(ShopMenu.open)

Remotes.ChallengeReceived.OnClientEvent:Connect(function(fromUserId, fromName, destination)
	Hud.showInvite(fromName, destination, function(accepted)
		Remotes.ChallengeReply:FireServer(fromUserId, accepted)
	end)
end)

local function applyWorldState()
	local raw = ReplicatedStorage:GetAttribute("WorldState")
	if type(raw) == "string" then
		local ok, state = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok then
			Hud.setWorld(state)
			Ambience.setWorld(state)
		end
	end
end
ReplicatedStorage:GetAttributeChangedSignal("WorldState"):Connect(applyWorldState)
applyWorldState()

-- Challenge the closest other driver.
local function challengeNearest()
	local myCar = DriveController.currentCar()
	local cars = Workspace:FindFirstChild("Cars")
	if not myCar or not myCar.PrimaryPart or not cars then
		Hud.notify("Get in your car to challenge someone.", "error")
		return
	end
	local best, bestDist = nil, CHALLENGE_RANGE
	for _, car in cars:GetChildren() do
		local owner = car:GetAttribute("OwnerUserId")
		if car ~= myCar and owner ~= player.UserId and car.PrimaryPart then
			local d = (car.PrimaryPart.Position - myCar.PrimaryPart.Position).Magnitude
			if d < bestDist then
				best, bestDist = owner, d
			end
		end
	end
	if best then
		Remotes.Challenge:FireServer(best)
	else
		Hud.notify("No other drivers close enough.", "error")
	end
end

-- Studio-only test keys (the server ignores them on live servers).
local DEV_KEYS = {
	[Enum.KeyCode.F6] = "dusk",
	[Enum.KeyCode.F7] = "meet",
	[Enum.KeyCode.F8] = "flash",
	[Enum.KeyCode.F9] = "cash",
}
local isStudio = RunService:IsStudio()
if isStudio then
	Hud.notify("Studio test keys: F6 dusk, F7 midnight meet, F8 flash race, F9 +$50k", "info")
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if isStudio and DEV_KEYS[input.KeyCode] then
		Remotes.Dev:FireServer(DEV_KEYS[input.KeyCode])
	elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.DPadUp then
		challengeNearest()
	elseif Hud.hasInvite() and input.KeyCode == Enum.KeyCode.Y then
		Hud.answerInvite(true)
	elseif Hud.hasInvite() and input.KeyCode == Enum.KeyCode.N then
		Hud.answerInvite(false)
	end
end)

-- Touch screens get on-screen buttons for everything that isn't steering.
-- (The default Roblox thumbstick already drives the VehicleSeat.)
if UserInputService.TouchEnabled then
	Hud.setTouchControls({
		handbrake = DriveController.setHandbrake,
		reset = function()
			Remotes.RespawnCar:FireServer()
		end,
		challenge = challengeNearest,
	})
end

RunService.RenderStepped:Connect(function(dt)
	local car = DriveController.currentCar()
	local engine = Ambience.updateCars(dt, car)
	if car and car.PrimaryPart then
		local vel = car.PrimaryPart.AssemblyLinearVelocity
		local mph = math.floor(Vector3.new(vel.X, 0, vel.Z).Magnitude * STUDS_TO_MPH + 0.5)
		Hud.setDriving(true)
		Hud.setSpeedo(true, mph, engine and engine.gear, car:GetAttribute("Class"), car:GetAttribute("Rating"), car:GetAttribute("CarName"))
	else
		Hud.setDriving(false)
		Hud.setSpeedo(false)
	end
	Hud.updateRace()
	Hud.updateWorld()
	Ambience.updateWeather()
	Ambience.setCheckpoint(Hud.raceTarget())
end)
