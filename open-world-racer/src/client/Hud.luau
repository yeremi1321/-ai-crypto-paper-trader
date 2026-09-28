-- On-screen HUD built in code: cash and street title, speedometer, race info,
-- the world panel (flash races, midnight meet clue, weather), toasts,
-- challenge invites and race results.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Records = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Records"))

local Hud = {}

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local ACCENT = {
	info = Color3.fromRGB(230, 230, 235),
	error = Color3.fromRGB(255, 110, 110),
	race = Color3.fromRGB(255, 200, 40),
	flash = Color3.fromRGB(255, 120, 40),
	meet = Color3.fromRGB(180, 110, 255),
	discovery = Color3.fromRGB(90, 230, 160),
	trap = Color3.fromRGB(80, 190, 255),
}

local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = f
	return f
end

local function label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end

local function button(parent: Instance, text: string, pos: UDim2, size: UDim2, color: Color3, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Position = pos
	b.Size = size
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = b
	b.Activated:Connect(onClick)
	return b
end
Hud.button = button
Hud.frame = frame
Hud.label = label
Hud.gui = gui

-- Cash and title --------------------------------------------------------------
local wallet = frame({ Position = UDim2.new(0, 12, 0, 12), Size = UDim2.new(0, 260, 0, 64), Parent = gui })
local cashLabel = label({ Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -24, 0, 30), Font = Enum.Font.GothamBlack, Text = "$0", Parent = wallet })
local titleLabel = label({ Position = UDim2.new(0, 12, 0, 38), Size = UDim2.new(1, -24, 0, 18), TextColor3 = Color3.fromRGB(190, 190, 200), Text = "Newcomer", Parent = wallet })

-- Speedometer ----------------------------------------------------------------
local speedo = frame({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.new(0, 190, 0, 96), Parent = gui })
speedo.Visible = false
local speedLabel = label({ Position = UDim2.new(0, 12, 0, 4), Size = UDim2.new(0.62, 0, 0, 56), Font = Enum.Font.GothamBlack, Text = "0", Parent = speedo })
label({ Position = UDim2.new(0.62, 0, 0, 30), Size = UDim2.new(0.35, 0, 0, 22), Text = "MPH", TextColor3 = Color3.fromRGB(160, 160, 170), Parent = speedo })
local gearLabel = label({ Position = UDim2.new(0.62, 0, 0, 6), Size = UDim2.new(0.35, 0, 0, 24), Font = Enum.Font.GothamBlack, Text = "1", TextColor3 = ACCENT.race, Parent = speedo })
local classLabel = label({ Position = UDim2.new(0, 12, 0, 64), Size = UDim2.new(1, -24, 0, 22), Text = "", TextColor3 = Color3.fromRGB(190, 190, 200), Parent = speedo })

function Hud.setSpeedo(visible: boolean, mph: number?, gear: number?, className: string?, rating: number?, carName: string?)
	speedo.Visible = visible
	if visible then
		speedLabel.Text = tostring(mph or 0)
		gearLabel.Text = tostring(gear or 1)
		classLabel.Text = `{carName or ""}  {className or "?"} {rating or ""}`
	end
end

-- Race panel -----------------------------------------------------------------
local racePanel = frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.new(0, 360, 0, 92), Parent = gui })
racePanel.Visible = false
local raceTitle = label({ Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -24, 0, 22), Font = Enum.Font.GothamBold, TextColor3 = ACCENT.race, Parent = racePanel })
local raceMain = label({ Position = UDim2.new(0, 12, 0, 30), Size = UDim2.new(1, -24, 0, 34), Font = Enum.Font.GothamBlack, Parent = racePanel })
local raceSub = label({ Position = UDim2.new(0, 12, 0, 66), Size = UDim2.new(1, -24, 0, 18), TextColor3 = Color3.fromRGB(190, 190, 200), Parent = racePanel })

local raceState: any = nil

function Hud.setRace(state: any)
	raceState = state
	if state and state.phase == "results" then
		Hud.showResults(state)
		raceState = nil
	end
end

-- Called every frame so timers stay smooth between server updates.
function Hud.updateRace()
	local s = raceState
	racePanel.Visible = s ~= nil
	if not s then
		return
	end
	local t = Workspace:GetServerTimeNow()
	raceTitle.Text = s.name
	if s.phase == "lobby" then
		local left = math.max(0, math.ceil(s.startsAt - t))
		raceMain.Text = `Starting in {left}s`
		raceSub.Text = `{s.drivers} driver(s)  -  Class {s.classCap or "open"}  -  stay in the zone`
	elseif s.phase == "racing" then
		if t < s.startTime then
			raceMain.Text = tostring(math.ceil(s.startTime - t))
		elseif s.finished then
			raceMain.Text = `Finished  {Records.formatTime(s.finished)}`
		else
			raceMain.Text = `P{s.place}/{s.field}   {Records.formatTime(t - s.startTime)}`
		end
		local lapText = if s.laps > 1 then `Lap {s.lap}/{s.laps}  -  ` else ""
		local cpText = if s.isFinishNext then "Finish line next" else `Checkpoint {s.checkpoint}/{s.checkpoints}`
		raceSub.Text = lapText .. cpText
	end
end

function Hud.raceTarget(): (any, any, boolean)
	local s = raceState
	if s and s.phase == "racing" and not s.finished and not s.dnf then
		return s.next, s.after, s.isFinishNext
	end
	return nil, nil, false
end

-- Results --------------------------------------------------------------------
local results = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.new(0, 380, 0, 330), Parent = gui })
results.Visible = false
local resultsText = label({ Position = UDim2.new(0, 16, 0, 12), Size = UDim2.new(1, -32, 1, -64), TextScaled = false, TextSize = 18, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Parent = results })
button(results, "Continue", UDim2.new(0.5, -70, 1, -46), UDim2.new(0, 140, 0, 34), Color3.fromRGB(60, 60, 70), function()
	results.Visible = false
end)

function Hud.showResults(s: any)
	local lines = { `<b>{s.name}</b>`, "" }
	for _, r in s.results do
		local time = if r.dnf then "DNF" elseif r.time then Records.formatTime(r.time) else ""
		table.insert(lines, `{r.place}. {r.name}   {time}`)
	end
	table.insert(lines, "")
	table.insert(lines, `+${s.cash}   +{s.rep} rep in {s.district}`)
	if s.recordRank then
		table.insert(lines, `New local record: #{s.recordRank}`)
	end
	resultsText.RichText = true
	resultsText.Text = table.concat(lines, "\n")
	results.Visible = true
	task.delay(12, function()
		results.Visible = false
	end)
end

-- World panel ----------------------------------------------------------------
local worldPanel = frame({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.new(0, 280, 0, 112), Parent = gui })
local flashLabel = label({ Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0, 30), TextScaled = false, TextSize = 14, TextWrapped = true, TextColor3 = ACCENT.flash, Parent = worldPanel })
local meetLabel = label({ Position = UDim2.new(0, 12, 0, 40), Size = UDim2.new(1, -24, 0, 46), TextScaled = false, TextSize = 14, TextWrapped = true, TextColor3 = ACCENT.meet, Parent = worldPanel })
local weatherLabel = label({ Position = UDim2.new(0, 12, 0, 88), Size = UDim2.new(1, -24, 0, 18), TextScaled = false, TextSize = 13, TextColor3 = Color3.fromRGB(170, 170, 180), Parent = worldPanel })

local worldState: any = nil
function Hud.setWorld(state: any)
	worldState = state
end

function Hud.updateWorld()
	local s = worldState
	if not s then
		return
	end
	local t = Workspace:GetServerTimeNow()
	if s.flash and t < s.flash.closesAt then
		flashLabel.Text = `FLASH RACE at {s.flash.name} - {s.flash.event} - {math.ceil(s.flash.closesAt - t)}s`
	else
		flashLabel.Text = "No flash race right now. Keep cruising."
	end
	if s.meet.phase == "open" then
		meetLabel.Text = `MIDNIGHT MEET is live at {s.meet.spotName}. Featured: {s.meet.featured}`
	elseif s.meet.phase == "clue" then
		meetLabel.Text = `Tonight's meet clue: "{s.meet.clue}"`
	else
		meetLabel.Text = "The midnight meet clue drops at dusk."
	end
	local clock = game:GetService("Lighting").ClockTime
	weatherLabel.Text = string.format("%02d:%02d  %s", math.floor(clock), math.floor((clock % 1) * 60), if s.raining then "Rain" else "Clear")
end

-- Profile --------------------------------------------------------------------
function Hud.setProfile(p: any)
	cashLabel.Text = `${p.cash}`
	titleLabel.Text = p.title
end

-- Toasts ---------------------------------------------------------------------
local toastList = Instance.new("Frame")
toastList.BackgroundTransparency = 1
toastList.AnchorPoint = Vector2.new(0.5, 0)
toastList.Position = UDim2.new(0.5, 0, 0, 116)
toastList.Size = UDim2.new(0, 460, 0, 200)
toastList.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = toastList

function Hud.notify(text: string, kind: string?)
	local toast = frame({ Size = UDim2.new(1, 0, 0, 34), Parent = toastList })
	label({
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(1, -24, 1, 0),
		TextScaled = false,
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		TextColor3 = ACCENT[kind or "info"] or ACCENT.info,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = text,
		Parent = toast,
	})
	task.delay(5, function()
		toast:Destroy()
	end)
end

-- Challenges -----------------------------------------------------------------
local invite = frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -130), Size = UDim2.new(0, 380, 0, 96), Parent = gui })
invite.Visible = false
local inviteText = label({ Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0, 40), TextScaled = false, TextSize = 16, TextWrapped = true, Parent = invite })
local inviteReply: ((boolean) -> ())? = nil
button(invite, "Race (Y)", UDim2.new(0, 12, 1, -42), UDim2.new(0.5, -18, 0, 32), Color3.fromRGB(40, 150, 80), function()
	Hud.answerInvite(true)
end)
button(invite, "Pass (N)", UDim2.new(0.5, 6, 1, -42), UDim2.new(0.5, -18, 0, 32), Color3.fromRGB(120, 50, 55), function()
	Hud.answerInvite(false)
end)

function Hud.showInvite(fromName: string, destination: string, reply: (boolean) -> ())
	inviteText.Text = `{fromName} challenges you: first to {destination}.`
	inviteReply = reply
	invite.Visible = true
	task.delay(18, function()
		if inviteReply == reply then
			Hud.answerInvite(false)
		end
	end)
end

function Hud.answerInvite(accepted: boolean)
	local reply = inviteReply
	inviteReply = nil
	invite.Visible = false
	if reply then
		reply(accepted)
	end
end

function Hud.hasInvite(): boolean
	return inviteReply ~= nil
end

-- Controls hint --------------------------------------------------------------
local hint = label({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -12),
	Size = UDim2.new(0, 520, 0, 18),
	TextScaled = false,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(200, 200, 210),
	TextStrokeTransparency = 0.6,
	Text = "WASD drive  -  Shift handbrake  -  R reset car  -  C challenge nearby driver  -  E at shops",
	Parent = gui,
})

-- Touch controls -------------------------------------------------------------
local touchPanel: Frame? = nil

type TouchActions = { handbrake: (boolean) -> (), reset: () -> (), challenge: () -> () }

function Hud.setTouchControls(actions: TouchActions)
	hint.Visible = false
	-- Stack the speedometer's column: buttons sit just above it on the right.
	local panel = Instance.new("Frame")
	panel.BackgroundTransparency = 1
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -16, 1, -122)
	panel.Size = UDim2.new(0, 190, 0, 150)
	panel.Visible = false
	panel.Parent = gui
	touchPanel = panel

	local brake = button(panel, "DRIFT", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 70), Color3.fromRGB(170, 60, 40), function() end)
	brake.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			actions.handbrake(true)
		end
	end)
	brake.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			actions.handbrake(false)
		end
	end)
	button(panel, "RESET", UDim2.new(0, 0, 0, 80), UDim2.new(0.5, -4, 0, 60), Color3.fromRGB(60, 60, 70), actions.reset)
	button(panel, "RACE", UDim2.new(0.5, 4, 0, 80), UDim2.new(0.5, -4, 0, 60), Color3.fromRGB(40, 110, 200), actions.challenge)
end

-- Touch buttons only show while driving.
function Hud.setDriving(driving: boolean)
	if touchPanel then
		touchPanel.Visible = driving
	end
end

return Hud
