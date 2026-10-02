-- Client entry point: wires remotes to the HUD and the kart controller.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Hud = require(script.Parent.Hud)
local KartController = require(script.Parent.KartController)

KartController.start()

Hud.onChooseKart = function(kartId)
	Remotes.ChooseKart:FireServer(kartId)
end
Hud.onReady = function(ready)
	Remotes.Ready:FireServer(ready)
end

KartController.onUpdate = Hud.setKart
KartController.onTurbo = function(level)
	Hud.flash(if level == 0 then "ROCKET START!" elseif level == 3 then "ULTRA TURBO!" elseif level == 2 then "SUPER TURBO!" else "TURBO!", 0.8)
end

Remotes.Lobby.OnClientEvent:Connect(Hud.setLobby)
Remotes.RaceStart.OnClientEvent:Connect(Hud.raceStarted)
Remotes.RaceState.OnClientEvent:Connect(Hud.setRaceState)
Remotes.ItemState.OnClientEvent:Connect(Hud.setItem)
Remotes.Results.OnClientEvent:Connect(Hud.showResults)
Remotes.Notify.OnClientEvent:Connect(function(message)
	Hud.flash(message, 1.6)
end)

if UserInputService.TouchEnabled then
	Hud.addTouchButtons(KartController.setDrift, KartController.useItem)
end

-- Spin the item boxes (visual only; pickups are decided by the server).
RunService.RenderStepped:Connect(function(dt)
	Hud.updateLobby()
	Hud.updateRace()
	local items = workspace:FindFirstChild("Items")
	if items then
		for _, box in items:GetChildren() do
			if box:GetAttribute("ItemBox") and box:IsA("BasePart") then
				box.CFrame *= CFrame.Angles(0, dt * 2, 0)
			end
		end
	end
end)
