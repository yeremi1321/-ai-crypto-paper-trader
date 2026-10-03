-- Client entry point: wires remotes to the lobby screens, garage, race HUD,
-- kart controller, spectator camera and lighting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Atmos = require(ReplicatedStorage:WaitForChild("Common"):WaitForChild("Atmos"))

local GarageUI = require(script.Parent.GarageUI)
local Hud = require(script.Parent.Hud)
local KartController = require(script.Parent.KartController)
local LobbyUI = require(script.Parent.LobbyUI)
local Spectate = require(script.Parent.Spectate)

local roundState: any = nil

Atmos.apply("carnival")
KartController.start()

local function namesOf(rows: { any }): { string }
	local names = {}
	for _, r in rows do
		table.insert(names, r.kart or r.name)
	end
	return names
end

local function stopSpectating()
	Spectate.stop()
	LobbyUI.setSpectating(false)
	if not KartController.isRacing() then
		Atmos.apply("carnival")
	end
end

local function startSpectating(rows: { any }, theme: string?)
	if theme then
		Atmos.apply(theme)
	end
	GarageUI.close()
	Spectate.start(namesOf(rows), function(name)
		LobbyUI.setSpectating(true, name)
	end)
end

-- Lobby ----------------------------------------------------------------------
LobbyUI.onReady = function(ready)
	Remotes.Ready:FireServer(ready)
end
LobbyUI.onVote = function(trackId)
	Remotes.Vote:FireServer(trackId)
end
LobbyUI.onGarage = GarageUI.toggle
LobbyUI.onWatch = function()
	if roundState and roundState.spectate then
		startSpectating(roundState.spectate.rows, roundState.spectate.theme)
	end
end
LobbyUI.onLeavePractice = function()
	Remotes.LeavePractice:FireServer()
end
LobbyUI.onSpectateNext = Spectate.cycle
LobbyUI.onStopSpectating = stopSpectating

GarageUI.onChooseKart = function(kartId)
	Remotes.ChooseKart:FireServer(kartId)
end
GarageUI.onLook = function(look)
	Remotes.ChooseLook:FireServer(look)
end

Remotes.Round.OnClientEvent:Connect(function(state)
	roundState = state
	LobbyUI.setState(state)
	if Spectate.isActive() and not KartController.isRacing() then
		if state.spectate then
			Spectate.setOrder(namesOf(state.spectate.rows))
		elseif state.phase ~= "racing" then
			stopSpectating()
		end
	end
end)
Remotes.OpenGarage.OnClientEvent:Connect(GarageUI.open)
Remotes.Spectate.OnClientEvent:Connect(LobbyUI.onWatch)

-- Racing ---------------------------------------------------------------------
Remotes.RaceStart.OnClientEvent:Connect(function(info)
	stopSpectating()
	GarageUI.close()
	LobbyUI.setHidden(true)
	Hud.raceStarted(info)
	Hud.setDriving(true)
	Atmos.apply(info.theme or "sunny")
end)
Remotes.PracticeStart.OnClientEvent:Connect(function()
	GarageUI.close()
	LobbyUI.setPracticing(true)
	Hud.setDriving(true)
	LobbyUI.toast("Practice! Drift, jump and boost. R resets the kart.")
end)
KartController.onStopped = function(mode)
	Hud.setDriving(false)
	if mode == "practice" then
		LobbyUI.setPracticing(false)
	end
end

Remotes.RaceState.OnClientEvent:Connect(function(s)
	Hud.setRaceState(s)
	-- Finished: the server drives your kart home while you watch the others.
	if s.finishTime and KartController.isRacing() then
		KartController.handOff()
		Hud.setDriving(false)
		startSpectating(s.rows)
	elseif Spectate.isActive() then
		Spectate.setOrder(namesOf(s.rows))
	end
end)
Remotes.ItemState.OnClientEvent:Connect(Hud.setItem)
Remotes.Results.OnClientEvent:Connect(function(info)
	stopSpectating()
	Hud.setDriving(false)
	Hud.showResults(info)
	LobbyUI.setHidden(false)
	Atmos.apply("carnival")
end)
Remotes.Notify.OnClientEvent:Connect(function(message)
	if Hud.isRacing() then
		Hud.flash(message, 1.6)
	else
		LobbyUI.toast(message)
	end
end)

KartController.onUpdate = Hud.setKart
KartController.onWarning = function(text)
	Hud.warn(text, 1.5)
end
KartController.onTurbo = function(level)
	Hud.flash(if level == 0 then "ROCKET START!" elseif level == 3 then "ULTRA TURBO!" elseif level == 2 then "SUPER TURBO!" else "TURBO!", 0.8)
end

if UserInputService.TouchEnabled then
	Hud.addTouchButtons(KartController.setDrift, KartController.useItem, KartController.reset)
end

-- Spinning things (Ferris wheel, golden tokens, item boxes) turn on each client.
local spinners: { Instance } = {}
local function track(inst: Instance)
	if inst:GetAttribute("Spin") then
		table.insert(spinners, inst)
	end
end
for _, d in Workspace:GetDescendants() do
	track(d)
end
Workspace.DescendantAdded:Connect(track)

RunService.RenderStepped:Connect(function(dt)
	LobbyUI.update()
	Hud.update()
	for i = #spinners, 1, -1 do
		local inst = spinners[i]
		if not inst.Parent then
			table.remove(spinners, i)
			continue
		end
		local rate = inst:GetAttribute("Spin") or 0
		if inst:IsA("Model") then
			inst:PivotTo(inst:GetPivot() * CFrame.Angles(rate * dt, 0, 0))
		elseif inst:IsA("BasePart") then
			inst.CFrame *= CFrame.Angles(0, rate * dt, 0)
		end
	end
	local items = Workspace:FindFirstChild("Items")
	if items then
		for _, box in items:GetChildren() do
			if box:GetAttribute("ItemBox") and box:IsA("BasePart") then
				box.CFrame *= CFrame.Angles(0, dt * 2, 0)
			end
		end
	end
end)
