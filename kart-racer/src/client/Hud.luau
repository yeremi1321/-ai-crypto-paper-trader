-- All screens, built in code: lobby (pick a kart, ready up), race HUD (place,
-- lap, item slot with roulette, standings, countdown, wrong-way warning),
-- race results, cup results and touch buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Karts = require(Shared:WaitForChild("Karts"))

local Hud = {}

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "KartHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local YELLOW = Color3.fromRGB(255, 210, 50)
local PLACE_COLORS = { Color3.fromRGB(255, 210, 50), Color3.fromRGB(200, 210, 225), Color3.fromRGB(230, 140, 70) }

local function frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = f
	f.Parent = parent
	return f
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	l.TextStrokeTransparency = 0.5
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function button(parent: Instance, label: string, props: { [string]: any }, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	b.Text = label
	for k, v in props do
		(b :: any)[k] = v
	end
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = b
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

local function ordinal(n: number): string
	local suffix = "th"
	if n % 100 < 11 or n % 100 > 13 then
		suffix = ({ "st", "nd", "rd" })[n % 10] or "th"
	end
	return `{n}{suffix}`
end

local function fmtTime(t: number?): string
	if not t then
		return "--"
	end
	local m = math.floor(t / 60)
	return string.format("%d:%05.2f", m, t - m * 60)
end

---------------------------------------------------------------------------
-- Lobby
---------------------------------------------------------------------------
local lobby = frame(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 620, 0, 420) })
text(lobby, { Position = UDim2.new(0, 20, 0, 14), Size = UDim2.new(1, -40, 0, 44), Text = "KART RACER" , TextColor3 = YELLOW })
local lobbySub = text(lobby, { Position = UDim2.new(0, 20, 0, 60), Size = UDim2.new(1, -40, 0, 22), Font = Enum.Font.GothamMedium, Text = "" })
local cards = Instance.new("Frame")
cards.BackgroundTransparency = 1
cards.Position = UDim2.new(0, 20, 0, 96)
cards.Size = UDim2.new(1, -40, 0, 170)
cards.Parent = lobby
local cardLayout = Instance.new("UIListLayout")
cardLayout.FillDirection = Enum.FillDirection.Horizontal
cardLayout.Padding = UDim.new(0, 10)
cardLayout.Parent = cards
local playersLabel = text(lobby, { Position = UDim2.new(0, 20, 0, 276), Size = UDim2.new(1, -40, 0, 60), Font = Enum.Font.GothamMedium, TextScaled = false, TextSize = 15, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "" })

local chosenKart = Karts.Default
local isReady = false
local cardButtons: { [string]: TextButton } = {}
Hud.onChooseKart = nil :: ((string) -> ())?
Hud.onReady = nil :: ((boolean) -> ())?

local function statBar(n: number, lo: number, hi: number): string
	local filled = math.clamp(math.floor((n - lo) / (hi - lo) * 5 + 0.5), 1, 5)
	return string.rep("■", filled) .. string.rep("□", 5 - filled)
end

for _, def in Karts.List do
	local c = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
	local card = button(cards, "", { Size = UDim2.new(1 / 3, -7, 1, 0), BackgroundColor3 = c:Lerp(Color3.new(0, 0, 0), 0.55) }, function()
		chosenKart = def.id
		if Hud.onChooseKart then
			Hud.onChooseKart(def.id)
		end
		Hud.refreshCards()
	end)
	text(card, { Position = UDim2.new(0, 10, 0, 8), Size = UDim2.new(1, -20, 0, 30), Text = def.name, TextColor3 = c })
	text(card, {
		Position = UDim2.new(0, 10, 0, 42),
		Size = UDim2.new(1, -20, 0, 120),
		Font = Enum.Font.GothamMedium,
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = `{def.blurb}\n\nSpeed  {statBar(def.stats.topSpeed, 88, 108)}\nAccel  {statBar(def.stats.accel, 44, 72)}\nTurn    {statBar(def.stats.handling, 1.9, 2.4)}\nWeight {statBar(def.stats.weight, 1, 5)}`,
	})
	cardButtons[def.id] = card
end

function Hud.refreshCards()
	for id, card in cardButtons do
		local stroke = card:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		stroke.Thickness = if id == chosenKart then 4 else 0
		stroke.Color = YELLOW
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = card
	end
end
Hud.refreshCards()

local readyButton = button(lobby, "READY", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(0, 240, 0, 52), BackgroundColor3 = Color3.fromRGB(40, 160, 80) }, function()
	isReady = not isReady
	if Hud.onReady then
		Hud.onReady(isReady)
	end
end)

local lobbyState: any = nil
function Hud.setLobby(state: any)
	lobbyState = state
	lobby.Visible = state.phase == "lobby"
	local lines = {}
	for _, p in state.players do
		local kart = Karts.get(p.kart).name
		table.insert(lines, `{if p.ready then "✔" else "…"} {p.name} ({kart})`)
		if p.name == player.DisplayName then
			isReady = p.ready
		end
	end
	playersLabel.Text = table.concat(lines, "    ")
	readyButton.Text = if isReady then "NOT READY" else "READY"
	readyButton.BackgroundColor3 = if isReady then Color3.fromRGB(150, 60, 60) else Color3.fromRGB(40, 160, 80)
end

function Hud.updateLobby()
	local s = lobbyState
	if not s or s.phase ~= "lobby" then
		if s and s.phase ~= "lobby" then
			lobbySub.Text = "Race in progress - you'll join the next cup."
		end
		return
	end
	local t = Workspace:GetServerTimeNow()
	if s.startsAt then
		lobbySub.Text = `{s.cupName}: {s.raceCount} races. Starting in {math.max(0, math.ceil(s.startsAt - t))}s (or when everyone is ready)`
	else
		lobbySub.Text = `{s.cupName}: {s.raceCount} races. Pick a kart and press READY. CPU drivers fill empty spots.`
	end
end

---------------------------------------------------------------------------
-- Race HUD
---------------------------------------------------------------------------
local race = Instance.new("Frame")
race.BackgroundTransparency = 1
race.Size = UDim2.fromScale(1, 1)
race.Visible = false
race.Parent = gui

local placeLabel = text(race, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -20), Size = UDim2.new(0, 200, 0, 110), Text = "" })
local lapLabel = text(race, { Position = UDim2.new(0, 20, 0, 16), Size = UDim2.new(0, 220, 0, 44), Text = "" , TextXAlignment = Enum.TextXAlignment.Left })
local trackLabel = text(race, { Position = UDim2.new(0, 20, 0, 60), Size = UDim2.new(0, 300, 0, 22), Font = Enum.Font.GothamMedium, Text = "", TextXAlignment = Enum.TextXAlignment.Left })
local itemSlot = frame(race, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.new(0, 210, 0, 74) })
local itemLabel = text(itemSlot, { Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(1, -20, 0, 40), Text = "" })
local itemHint = text(itemSlot, { Position = UDim2.new(0, 10, 0, 48), Size = UDim2.new(1, -20, 0, 18), Font = Enum.Font.GothamMedium, Text = "" })
local standings = frame(race, { Position = UDim2.new(0, 20, 0, 96), Size = UDim2.new(0, 190, 0, 8 * 24 + 12) })
local standingRows: { TextLabel } = {}
for i = 1, 8 do
	standingRows[i] = text(standings, {
		Position = UDim2.new(0, 10, 0, 6 + (i - 1) * 24),
		Size = UDim2.new(1, -20, 0, 22),
		Font = Enum.Font.GothamBold,
		TextScaled = false,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
end
local bigText = text(race, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.new(0, 500, 0, 120), Text = "", TextColor3 = YELLOW })
local speedLabel = text(race, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -132), Size = UDim2.new(0, 200, 0, 30), Font = Enum.Font.GothamBold, Text = "" })
local warnLabel = text(race, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 100), Size = UDim2.new(0, 360, 0, 40), Text = "", TextColor3 = Color3.fromRGB(255, 80, 80) })

local raceInfo: any = nil
local item: { id: string?, uses: number, readyAt: number } = { id = nil, uses = 0, readyAt = 0 }
local flashUntil = 0
local flashText = ""
local raceState: any = nil

function Hud.raceStarted(info: any)
	raceInfo = info
	raceState = nil
	race.Visible = true
	lobby.Visible = false
	trackLabel.Text = `{info.trackName}  -  Race {info.raceNumber}/{info.raceCount}`
end

function Hud.raceEnded()
	race.Visible = false
	raceInfo = nil
end

function Hud.setRaceState(s: any)
	raceState = s
	if s.finishTime then
		lapLabel.Text = fmtTime(s.finishTime)
	else
		lapLabel.Text = `LAP {s.lap}/{s.laps}`
	end
	placeLabel.Text = ordinal(s.place)
	placeLabel.TextColor3 = PLACE_COLORS[s.place] or Color3.new(1, 1, 1)
	for i, row in standingRows do
		local r = s.rows[i]
		row.Text = if r then `{i}. {r.name}{if r.finished then "  ✓" else ""}` else ""
		row.TextColor3 = if r and not r.isCpu then YELLOW else Color3.new(1, 1, 1)
	end
end

function Hud.setItem(id: string?, uses: number, readyAt: number)
	item = { id = id, uses = uses, readyAt = readyAt }
end

function Hud.flash(message: string, seconds: number?)
	flashText = message
	flashUntil = os.clock() + (seconds or 1.5)
end

function Hud.setKart(info: any)
	if info.countdown and info.countdown > 0 then
		local n = math.ceil(info.countdown)
		bigText.Text = if n <= 3 then tostring(n) else "GET READY"
	elseif os.clock() < flashUntil then
		bigText.Text = flashText
	else
		bigText.Text = ""
	end
	speedLabel.Text = `{math.floor(math.abs(info.speed or 0) * 0.6 + 0.5)} km/h`
	warnLabel.Text = if info.wrongWay then "WRONG WAY!" else ""
end

function Hud.updateRace()
	if not raceInfo then
		return
	end
	local t = Workspace:GetServerTimeNow()
	if raceInfo.goTime and t >= raceInfo.goTime and t < raceInfo.goTime + 1 and os.clock() >= flashUntil then
		bigText.Text = "GO!"
	end
	if item.id then
		local def = Items.Defs[item.id]
		if t < item.readyAt then
			-- Roulette: flick through items until it lands.
			local i = math.floor(t * 14) % #Items.Order + 1
			itemLabel.Text = Items.Defs[Items.Order[i]].name
			itemHint.Text = ""
		else
			itemLabel.Text = if item.uses > 1 then `{def.name} x{item.uses}` else def.name
			itemHint.Text = "Press E (X / ITEM) to use"
		end
	else
		itemLabel.Text = ""
		itemHint.Text = "Drive through a ? box"
	end
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------
local results = frame(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 460, 0, 400), Visible = false })
local resultsTitle = text(results, { Position = UDim2.new(0, 20, 0, 12), Size = UDim2.new(1, -40, 0, 38), TextColor3 = YELLOW, Text = "" })
local resultsBody = text(results, {
	Position = UDim2.new(0, 24, 0, 60),
	Size = UDim2.new(1, -48, 1, -76),
	Font = Enum.Font.GothamBold,
	TextScaled = false,
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	RichText = true,
	Text = "",
})

function Hud.showResults(info: any)
	Hud.raceEnded()
	local lines = {}
	if info.kind == "race" then
		resultsTitle.Text = `{info.trackName} results`
		for _, r in info.rows do
			local name = if r.isCpu then r.name else `<font color="#FFD232">{r.name}</font>`
			table.insert(lines, `{ordinal(r.place)}  {name}   {fmtTime(r.time)}   +{r.gained}  ({r.total})`)
		end
		table.insert(lines, "")
		table.insert(lines, if info.lastRace then "Final standings next..." else "Next race coming up...")
	else
		resultsTitle.Text = `{info.cupName} final standings`
		for _, r in info.rows do
			table.insert(lines, `{ordinal(r.place)}  {r.name}   {r.total} pts`)
		end
	end
	resultsBody.Text = table.concat(lines, "\n")
	results.Visible = true
	task.delay(if info.kind == "cup" then 13 else 8.5, function()
		results.Visible = false
	end)
end

---------------------------------------------------------------------------
-- Touch buttons
---------------------------------------------------------------------------
function Hud.addTouchButtons(onDrift: (boolean) -> (), onItem: () -> ())
	local drift = button(race, "DRIFT", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -170), Size = UDim2.new(0, 110, 0, 80), BackgroundColor3 = Color3.fromRGB(170, 70, 40) }, function() end)
	drift.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			onDrift(true)
		end
	end)
	drift.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			onDrift(false)
		end
	end)
	button(race, "ITEM", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -144, 1, -170), Size = UDim2.new(0, 90, 0, 80), BackgroundColor3 = Color3.fromRGB(50, 110, 210) }, onItem)
end

return Hud
