-- Client entry point: wires remotes to the lobby screens, garage, race HUD,
-- kart controller, spectator camera and lighting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Atmos = require(ReplicatedStorage:WaitForChild("Common"):WaitForChild("Atmos"))

-- Same car list as the server: add the Blender-made cars (KartAssets.Bodies).
if not game:IsLoaded() then
	game.Loaded:Wait()
end
require(ReplicatedStorage.Common.Assets).registerBodies()

local GarageUI = require(script.Parent.GarageUI)
local Hud = require(script.Parent.Hud)
local KartVisuals = require(script.Parent.KartVisuals)
local KartController = require(script.Parent.KartController)
local LobbyUI = require(script.Parent.LobbyUI)
local LobbyScreens = require(script.Parent.LobbyScreens)
local Spectate = require(script.Parent.Spectate)
local TrackAnimator = require(script.Parent.TrackAnimator)

local roundState: any = nil

Atmos.apply("hq")
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
		Atmos.apply("hq")
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

GarageUI.onAction = function(action, kind, value)
	Remotes.GarageAction:FireServer(action, kind, value)
end

-- Your saved data: garage, settings, and which golden tokens you've found.
local Cosmetics = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Cosmetics"))
Remotes.Profile.OnClientEvent:Connect(function(data, canSave)
	GarageUI.setData(data, canSave)
	KartController.settings.autoAccelerate = data.settings.autoAccelerate
	KartController.settings.cameraFar = data.settings.cameraFar
	KartVisuals.reduced = data.settings.reducedEffects
	LobbyUI.setCoins(data.coins)
	local lobby = Workspace:FindFirstChild("Lobby")
	local tokens = lobby and lobby:FindFirstChild("Tokens")
	if tokens then
		for _, token in tokens:GetChildren() do
			local id = tostring(token:GetAttribute("TokenId"))
			if data.tokens[id] and token:IsA("BasePart") then
				token.LocalTransparencyModifier = 1
			end
		end
	end
end)

-- Horns: a bubble over whoever honked (and their sound, if one is set).
local Players = game:GetService("Players")
Remotes.Honk.OnClientEvent:Connect(function(_name, hornId, userId)
	local horn = Cosmetics.find("horn", hornId)
	local who = Players:GetPlayerByUserId(userId)
	local character = who and who.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not horn then
		return
	end
	local bubble = Instance.new("BillboardGui")
	bubble.Size = UDim2.new(0, 160, 0, 50)
	bubble.StudsOffset = Vector3.new(0, 4, 0)
	bubble.AlwaysOnTop = true
	bubble.MaxDistance = 150
	bubble.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 60)
	label.TextStrokeTransparency = 0
	label.Text = `{horn.icon} {horn.text}`
	label.Parent = bubble
	if horn.soundId ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = horn.soundId
		sound.Parent = head
		sound:Play()
		task.delay(3, function()
			sound:Destroy()
		end)
	end
	task.delay(1.6, function()
		bubble:Destroy()
	end)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and (input.KeyCode == Enum.KeyCode.H or input.KeyCode == Enum.KeyCode.DPadUp) then
		Remotes.HonkRequest:FireServer()
	end
end)

Remotes.Round.OnClientEvent:Connect(function(state)
	roundState = state
	LobbyUI.setState(state)
	LobbyScreens.setState(state)
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
	-- Awards for everyone, plus your own coins, badges and challenges.
	local extra = {}
	if info.awards and #info.awards > 0 then
		table.insert(extra, "")
		for _, a in info.awards do
			table.insert(extra, `{a.icon} {a.name}: {a.winner}`)
		end
	end
	if info.me then
		table.insert(extra, "")
		for _, line in info.me.lines do
			table.insert(extra, line)
		end
		table.insert(extra, `<b>Total: +{info.me.coins} 🪙</b>`)
	end
	info.extra = extra
	stopSpectating()
	Hud.setDriving(false)
	Hud.showResults(info)
	LobbyUI.setHidden(false)
	Atmos.apply("hq")
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
	local text = if level == 0 then "ROCKET START!"
		elseif level == 3 then "ULTRA TURBO!"
		elseif level == 2 then "SUPER TURBO!"
		elseif level == 10 then "TRICK!"
		elseif level == 11 then "SLIPSTREAM!"
		else "TURBO!"
	Hud.flash(text, 0.8)
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
	LobbyScreens.step(dt)
	Hud.update()
	KartVisuals.step(dt)
	TrackAnimator.step()
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
