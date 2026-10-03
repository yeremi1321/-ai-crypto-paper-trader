-- In-race screens: place, lap, item slot with roulette, standings, countdown,
-- warnings, speed, touch buttons, and the results screen after each race.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))

local UI = require(script.Parent.UI)

local Hud = {}

local PLACE_COLORS = { Color3.fromRGB(255, 210, 60), Color3.fromRGB(210, 220, 235), Color3.fromRGB(240, 150, 80) }

local race = Instance.new("Frame")
race.Name = "Race"
race.BackgroundTransparency = 1
race.Size = UDim2.fromScale(1, 1)
race.Visible = false
race.Parent = UI.Screen

local placeLabel = UI.label(race, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -20), Size = UDim2.new(0, 210, 0, 110), Text = "" })
local lapPanel = UI.panel(race, { Position = UDim2.new(0, 16, 0, 14), Size = UDim2.new(0, 220, 0, 74) })
local lapLabel = UI.label(lapPanel, { Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -24, 0, 40), Text = "", TextXAlignment = Enum.TextXAlignment.Left })
local trackLabel = UI.label(lapPanel, { Position = UDim2.new(0, 12, 0, 46), Size = UDim2.new(1, -24, 0, 20), Text = "", TextColor3 = UI.Colors.muted, TextXAlignment = Enum.TextXAlignment.Left })

local itemSlot = UI.panel(race, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.new(0, 230, 0, 92) })
local itemIcon = UI.label(itemSlot, { Position = UDim2.new(0, 10, 0, 8), Size = UDim2.new(0, 64, 0, 64), Text = "" })
local itemLabel = UI.label(itemSlot, { Position = UDim2.new(0, 80, 0, 10), Size = UDim2.new(1, -90, 0, 36), Text = "", TextXAlignment = Enum.TextXAlignment.Left })
local itemHint = UI.label(itemSlot, { Position = UDim2.new(0, 80, 0, 50), Size = UDim2.new(1, -90, 0, 30), Text = "", TextColor3 = UI.Colors.muted, TextXAlignment = Enum.TextXAlignment.Left })

local standings = UI.panel(race, { Position = UDim2.new(0, 16, 0, 98), Size = UDim2.new(0, 200, 0, 8 * 24 + 16) })
local standingRows: { TextLabel } = {}
for i = 1, 8 do
	standingRows[i] = UI.label(standings, {
		Position = UDim2.new(0, 12, 0, 8 + (i - 1) * 24),
		Size = UDim2.new(1, -24, 0, 22),
		TextScaled = false,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
end
local bigText = UI.label(race, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.new(0, 520, 0, 130), Text = "", TextColor3 = UI.Colors.yellow, TextStrokeTransparency = 0.2 })
local speedLabel = UI.label(race, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -132), Size = UDim2.new(0, 210, 0, 32), Text = "" })
local warnLabel = UI.label(race, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 112), Size = UDim2.new(0, 420, 0, 42), Text = "", TextColor3 = UI.Colors.red, TextStrokeTransparency = 0.3 })
local timeoutLabel = UI.label(race, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.new(0, 420, 0, 30), Text = "", TextColor3 = UI.Colors.yellow })

local raceInfo: any = nil
local raceState: any = nil
local item: { id: string?, uses: number, readyAt: number } = { id = nil, uses = 0, readyAt = 0 }
local flashUntil, flashText = 0, ""
local warnUntil, warnText = 0, ""

function Hud.raceStarted(info: any)
	raceInfo = info
	raceState = nil
	item = { id = nil, uses = 0, readyAt = 0 }
	race.Visible = true
	trackLabel.Text = info.trackName or ""
	lapLabel.Text = `LAP 1/{info.laps or 3}`
end

function Hud.raceEnded()
	race.Visible = false
	raceInfo = nil
end

function Hud.isRacing(): boolean
	return raceInfo ~= nil
end

function Hud.setRaceState(s: any)
	raceState = s
	lapLabel.Text = if s.finishTime then `🏁 {UI.time(s.finishTime)}` else `LAP {s.lap}/{s.laps}`
	placeLabel.Text = UI.ordinal(s.place)
	placeLabel.TextColor3 = PLACE_COLORS[s.place] or UI.Colors.text
	for i, row in standingRows do
		local r = s.rows[i]
		row.Text = if r then `{i}. {r.name}{if r.finished then "  🏁" else ""}` else ""
		row.TextColor3 = if r and not r.isCpu then UI.Colors.yellow else UI.Colors.text
	end
end

function Hud.setItem(id: string?, uses: number, readyAt: number)
	item = { id = id, uses = uses, readyAt = readyAt }
end

function Hud.flash(message: string, seconds: number?)
	flashText = message
	flashUntil = os.clock() + (seconds or 1.5)
end

function Hud.warn(message: string, seconds: number?)
	warnText = message
	warnUntil = os.clock() + (seconds or 1.5)
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
	if os.clock() < warnUntil then
		warnLabel.Text = warnText
	else
		warnLabel.Text = if info.wrongWay then "WRONG WAY!" elseif info.drafting then "💨 SLIPSTREAM" else ""
		warnLabel.TextColor3 = if info.wrongWay then UI.Colors.red else UI.Colors.blue
	end
end

function Hud.update()
	if not raceInfo then
		return
	end
	local t = Workspace:GetServerTimeNow()
	if raceInfo.goTime and t >= raceInfo.goTime and t < raceInfo.goTime + 1 and os.clock() >= flashUntil then
		bigText.Text = "GO!"
	end
	if raceState and raceState.endAt and not raceState.finishTime then
		timeoutLabel.Text = `⏱ Race ends in {math.max(0, math.ceil(raceState.endAt - t))}s`
	else
		timeoutLabel.Text = ""
	end
	if item.id then
		local def = Items.Defs[item.id]
		if t < item.readyAt then
			-- Roulette: flick through items until it lands.
			local i = math.floor(t * 14) % #Items.Order + 1
			local spin = Items.Defs[Items.Order[i]]
			itemIcon.Text = spin.icon or "?"
			itemLabel.Text = spin.name
			itemHint.Text = ""
		else
			itemIcon.Text = def.icon or "?"
			itemLabel.Text = if item.uses > 1 then `{def.name} x{item.uses}` else def.name
			itemHint.Text = "E / X / ITEM · hold S to aim back"
		end
	else
		itemIcon.Text = "❔"
		itemLabel.Text = "No item"
		itemHint.Text = "Drive through a ? box"
	end
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------
local results = UI.panel(UI.Screen, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 480, 0, 430), Visible = false })
local resultsTitle = UI.label(results, { Position = UDim2.new(0, 20, 0, 12), Size = UDim2.new(1, -40, 0, 40), TextColor3 = UI.Colors.yellow, Text = "" })
local resultsBody = UI.label(results, {
	Position = UDim2.new(0, 24, 0, 62),
	Size = UDim2.new(1, -48, 1, -130),
	TextScaled = false,
	TextSize = 19,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	RichText = true,
	Text = "",
})
UI.button(results, "OK", UI.Colors.green, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(0, 160, 0, 50) }, function()
	results.Visible = false
end)

function Hud.showResults(info: any)
	Hud.raceEnded()
	resultsTitle.Text = `🏁 {info.trackName}`
	local lines = {}
	for _, r in info.rows do
		local name = if r.isCpu then r.name else `<font color="#FFD23C">{r.name}</font>`
		local medal = ({ "🥇", "🥈", "🥉" })[r.place] or `{r.place}.`
		table.insert(lines, `{medal}  {name}   {if r.finished then UI.time(r.time) else "DNF"}`)
	end
	for _, line in info.extra or {} do
		table.insert(lines, line)
	end
	resultsBody.Text = table.concat(lines, "\n")
	results.Visible = true
	UI.pop(results)
	task.delay(10, function()
		results.Visible = false
	end)
end

---------------------------------------------------------------------------
-- Touch buttons
---------------------------------------------------------------------------
-- Touch controls live in their own layer so they also work on the practice loop.
local touch = Instance.new("Frame")
touch.Name = "Touch"
touch.BackgroundTransparency = 1
touch.Size = UDim2.fromScale(1, 1)
touch.Visible = false
touch.Parent = UI.Screen

function Hud.setDriving(on: boolean)
	touch.Visible = on
end

function Hud.addTouchButtons(onDrift: (boolean) -> (), onItem: () -> (), onReset: () -> ())
	local drift = UI.button(touch, "DRIFT", UI.Colors.pink, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -176), Size = UDim2.new(0, 120, 0, 90) })
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
	UI.button(touch, "ITEM", UI.Colors.blue, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -154, 1, -176), Size = UDim2.new(0, 100, 0, 90) }, onItem)
	UI.button(touch, "↺", UI.Colors.panelLight, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -264, 1, -196), Size = UDim2.new(0, 60, 0, 60) }, onReset)
end

return Hud
