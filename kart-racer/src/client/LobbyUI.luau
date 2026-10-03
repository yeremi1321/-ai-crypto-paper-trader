-- Lobby screens: the status bar (phase + countdown, always visible), the
-- READY button, GARAGE and WATCH buttons, the map voting cards, the practice
-- "leave kart" button and spectator controls.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local UI = require(script.Parent.UI)

local LobbyUI = {}

LobbyUI.onReady = nil :: ((boolean) -> ())?
LobbyUI.onVote = nil :: ((string) -> ())?
LobbyUI.onGarage = nil :: (() -> ())?
LobbyUI.onWatch = nil :: (() -> ())?
LobbyUI.onLeavePractice = nil :: (() -> ())?
LobbyUI.onSpectateNext = nil :: ((number) -> ())?
LobbyUI.onStopSpectating = nil :: (() -> ())?

local me = Players.LocalPlayer
local state: any = nil
local hidden = false -- hidden while racing

local root = Instance.new("Frame")
root.Name = "Lobby"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = UI.Screen

-- Status bar ---------------------------------------------------------------
local status = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.new(0, 460, 0, 70) })
local statusTitle = UI.label(status, { Position = UDim2.new(0, 14, 0, 4), Size = UDim2.new(1, -28, 0, 36), Text = "KART CARNIVAL", TextColor3 = UI.Colors.yellow })
local statusSub = UI.label(status, { Position = UDim2.new(0, 14, 0, 40), Size = UDim2.new(1, -28, 0, 24), Text = "", TextColor3 = UI.Colors.muted })

-- Coins (top left) -----------------------------------------------------------
local coinPanel = UI.panel(root, { Position = UDim2.new(0, 14, 0, 14), Size = UDim2.new(0, 150, 0, 50) })
local coinLabel = UI.label(coinPanel, { Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(1, -20, 1, -12), Text = "🪙 0" })

function LobbyUI.setCoins(coins: number)
	coinLabel.Text = `🪙 {coins}`
end

-- Bottom buttons -------------------------------------------------------------
local isReady = false
local readyButton = UI.button(root, "READY UP", UI.Colors.green, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(0, 260, 0, 66) }, function()
	if LobbyUI.onReady then
		LobbyUI.onReady(not isReady)
	end
end)
local garageButton = UI.button(root, "🔧 GARAGE", UI.Colors.blue, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -18), Size = UDim2.new(0, 170, 0, 58) }, function()
	if LobbyUI.onGarage then
		LobbyUI.onGarage()
	end
end)
local watchButton = UI.button(root, "📺 WATCH", UI.Colors.purple, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.new(0, 170, 0, 58), Visible = false }, function()
	if LobbyUI.onWatch then
		LobbyUI.onWatch()
	end
end)
local leaveButton = UI.button(root, "🚪 LEAVE KART", UI.Colors.red, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -92), Size = UDim2.new(0, 220, 0, 52), Visible = false }, function()
	if LobbyUI.onLeavePractice then
		LobbyUI.onLeavePractice()
	end
end)

-- Voting cards ---------------------------------------------------------------
local votePanel = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.new(0, 720, 0, 300), Visible = false })
local voteTitle = UI.label(votePanel, { Position = UDim2.new(0, 16, 0, 8), Size = UDim2.new(1, -32, 0, 34), Text = "VOTE FOR A TRACK", TextColor3 = UI.Colors.yellow })
local cardHolder = Instance.new("Frame")
cardHolder.BackgroundTransparency = 1
cardHolder.Position = UDim2.new(0, 14, 0, 50)
cardHolder.Size = UDim2.new(1, -28, 1, -62)
cardHolder.Parent = votePanel
UI.list(cardHolder, true, 12)

local THEME_COLORS = {
	sunny = Color3.fromRGB(90, 170, 80),
	canyon = Color3.fromRGB(200, 120, 70),
	neon = Color3.fromRGB(120, 60, 200),
	toyroom = Color3.fromRGB(70, 80, 170),
	kitchen = Color3.fromRGB(230, 140, 90),
	backyard = Color3.fromRGB(100, 170, 70),
	carnival = Color3.fromRGB(240, 90, 140),
}
local DIFFICULTY_COLORS = { Easy = UI.Colors.green, Medium = UI.Colors.yellow, Hard = UI.Colors.red }

type Card = { button: TextButton, icon: TextLabel, name: TextLabel, chip: TextLabel, feature: TextLabel, votes: TextLabel, faces: Frame, id: string? }
local cards: { Card } = {}
for i = 1, 3 do
	local card: Card = {} :: any
	card.button = UI.button(cardHolder, "", UI.Colors.panelLight, { Size = UDim2.new(1 / 3, -8, 1, 0), LayoutOrder = i }, function()
		if card.id and LobbyUI.onVote then
			LobbyUI.onVote(card.id)
		end
	end)
	card.icon = UI.label(card.button, { Size = UDim2.new(1, 0, 0, 56), Text = "" })
	card.name = UI.label(card.button, { Position = UDim2.new(0, 0, 0, 58), Size = UDim2.new(1, 0, 0, 28), Text = "" })
	card.chip = UI.label(card.button, { Position = UDim2.new(0.25, 0, 0, 90), Size = UDim2.new(0.5, 0, 0, 22), Text = "", BackgroundTransparency = 0, TextColor3 = Color3.fromRGB(30, 30, 40), TextStrokeTransparency = 1 })
	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UDim.new(1, 0)
	chipCorner.Parent = card.chip
	card.feature = UI.label(card.button, { Position = UDim2.new(0, 0, 0, 116), Size = UDim2.new(1, 0, 0, 40), TextScaled = false, TextSize = 15, Text = "", TextColor3 = UI.Colors.muted })
	card.votes = UI.label(card.button, { Position = UDim2.new(0, 0, 1, -66), Size = UDim2.new(1, 0, 0, 26), Text = "" })
	card.faces = Instance.new("Frame")
	card.faces.BackgroundTransparency = 1
	card.faces.Position = UDim2.new(0, 0, 1, -36)
	card.faces.Size = UDim2.new(1, 0, 0, 30)
	card.faces.Parent = card.button
	UI.list(card.faces, true, 4, true)
	cards[i] = card
end

-- Spectator controls ---------------------------------------------------------
local spectateBar = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(0, 460, 0, 70), Visible = false })
local spectateLabel = UI.label(spectateBar, { Position = UDim2.new(0, 80, 0, 10), Size = UDim2.new(1, -240, 0, 50), Text = "" })
UI.button(spectateBar, "◀", UI.Colors.panelLight, { Position = UDim2.new(0, 10, 0, 10), Size = UDim2.new(0, 60, 0, 50) }, function()
	if LobbyUI.onSpectateNext then
		LobbyUI.onSpectateNext(-1)
	end
end)
UI.button(spectateBar, "▶", UI.Colors.panelLight, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 10), Size = UDim2.new(0, 60, 0, 50) }, function()
	if LobbyUI.onSpectateNext then
		LobbyUI.onSpectateNext(1)
	end
end)
UI.button(spectateBar, "EXIT", UI.Colors.red, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.new(0, 130, 0, 50) }, function()
	if LobbyUI.onStopSpectating then
		LobbyUI.onStopSpectating()
	end
end)

-- Toasts (short messages while in the lobby) ---------------------------------
local toastHolder = Instance.new("Frame")
toastHolder.BackgroundTransparency = 1
toastHolder.AnchorPoint = Vector2.new(0.5, 0)
toastHolder.Position = UDim2.new(0.5, 0, 0, 90)
toastHolder.Size = UDim2.new(0, 420, 0, 200)
toastHolder.Parent = UI.Screen
UI.list(toastHolder, false, 6, true)

function LobbyUI.toast(text: string)
	local t = UI.panel(toastHolder, { Size = UDim2.new(1, 0, 0, 44) })
	UI.label(t, { Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -24, 1, -12), Text = text })
	UI.pop(t)
	task.delay(3.5, function()
		t:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------
local practicing = false
local spectating = false

function LobbyUI.setPracticing(on: boolean)
	practicing = on
	LobbyUI.refresh()
end

function LobbyUI.setSpectating(on: boolean, name: string?)
	spectating = on
	spectateLabel.Text = if name then `Watching {name}` else ""
	LobbyUI.refresh()
end

function LobbyUI.setHidden(on: boolean)
	hidden = on
	LobbyUI.refresh()
end

local function myEntry(): any?
	if not state then
		return nil
	end
	for _, p in state.players do
		if p.userId == me.UserId then
			return p
		end
	end
	return nil
end

function LobbyUI.setState(s: any)
	state = s
	local mine = myEntry()
	isReady = mine ~= nil and mine.ready
	LobbyUI.refresh()
end

function LobbyUI.refresh()
	local s = state
	local mine = myEntry()
	local racing = mine and mine.racing
	root.Visible = not hidden
	if not s then
		return
	end

	readyButton.Visible = not racing and not spectating and s.phase ~= "results"
	readyButton.Text = if isReady then "✓ READY (tap to cancel)" else "READY UP"
	readyButton.BackgroundColor3 = if isReady then UI.Colors.yellow else UI.Colors.green
	readyButton.TextColor3 = if isReady then Color3.fromRGB(40, 40, 50) else UI.Colors.text
	garageButton.Visible = not spectating
	watchButton.Visible = s.phase == "racing" and s.spectate ~= nil and not racing and not spectating
	leaveButton.Visible = practicing and not spectating
	spectateBar.Visible = spectating

	local voting = s.phase == "voting" and mine ~= nil and mine.voter
	votePanel.Visible = voting
	if voting then
		local myVote = nil
		for _, opt in s.options do
			if table.find(opt.voters, me.UserId) then
				myVote = opt.id
			end
		end
		for i, card in cards do
			local opt = s.options[i]
			card.button.Visible = opt ~= nil
			if opt then
				card.id = opt.id
				card.button.BackgroundColor3 = (THEME_COLORS[opt.theme] or UI.Colors.panelLight):Lerp(Color3.new(0, 0, 0), 0.35)
				card.icon.Text = opt.icon
				card.name.Text = opt.name
				card.chip.Text = opt.difficulty
				card.chip.BackgroundColor3 = DIFFICULTY_COLORS[opt.difficulty] or UI.Colors.muted
				card.feature.Text = opt.feature
				card.votes.Text = `{opt.votes} vote{if opt.votes == 1 then "" else "s"}`
				UI.highlight(card.button, opt.id == myVote)
				for _, child in card.faces:GetChildren() do
					if child:IsA("ImageLabel") then
						child:Destroy()
					end
				end
				for n, userId in opt.voters do
					if n > 6 then
						break
					end
					local face = Instance.new("ImageLabel")
					face.Size = UDim2.new(0, 28, 0, 28)
					face.BackgroundColor3 = Color3.new(1, 1, 1)
					face.Image = UI.headshot(userId)
					local corner = Instance.new("UICorner")
					corner.CornerRadius = UDim.new(1, 0)
					corner.Parent = face
					face.Parent = card.faces
				end
			end
		end
	end
end

-- Called every frame for the countdowns.
function LobbyUI.update()
	local s = state
	if not s then
		return
	end
	local t = Workspace:GetServerTimeNow()
	local left = if s.deadline then math.max(0, math.ceil(s.deadline - t)) else nil
	local readyCount = 0
	for _, p in s.players do
		if p.ready then
			readyCount += 1
		end
	end
	if s.phase == "lobby" then
		if left then
			statusTitle.Text = `RACE STARTING · {left}s`
			statusSub.Text = `{readyCount} ready · voting opens soon`
		else
			statusTitle.Text = "KART CARNIVAL"
			statusSub.Text = "Ready up to race · practice loop is south of spawn"
		end
	elseif s.phase == "voting" then
		statusTitle.Text = `VOTING · {left or 0}s`
		statusSub.Text = if myEntry() and myEntry().voter then "Tap a card or stand on a pad" else "Ready up to vote and race"
		voteTitle.Text = `VOTE FOR A TRACK · {left or 0}s`
	elseif s.phase == "racing" then
		statusTitle.Text = "RACE IN PROGRESS"
		statusSub.Text = if s.spectate then `{s.spectate.trackName} · ready up for the next race` else ""
	elseif s.phase == "results" then
		statusTitle.Text = "RESULTS"
		statusSub.Text = `Next round in {left or 0}s`
	end
end

return LobbyUI
