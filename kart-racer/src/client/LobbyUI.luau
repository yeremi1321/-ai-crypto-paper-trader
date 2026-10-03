-- Lobby screens: the status bar (phase + countdown, always visible), coins,
-- GARAGE / WATCH buttons, the READY button, the map voting row (three track
-- cards + Random), the winner reveal, the practice "leave kart" button and
-- spectator controls.
--
-- Layout keeps the bottom-left (thumbstick) and bottom-right (jump) corners
-- free on phones: side buttons sit top-left, and the vote row is centred.
-- The vote row matches the chamber's wall screen and pads (same colours,
-- numbers and previews), and both draw from the same round state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyLayout = require(Shared:WaitForChild("LobbyLayout"))
local Voting = require(Shared:WaitForChild("Voting"))

local TrackPreview = require(script.Parent.TrackPreview)
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

local CYAN = Color3.fromRGB(0, 225, 255)
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local PAD_COLORS = {}
for i, c in LobbyLayout.PadColors do
	PAD_COLORS[i] = rgb(c)
end
local DIFFICULTY_COLORS = { Easy = UI.Colors.green, Medium = UI.Colors.yellow, Hard = UI.Colors.red }

local root = Instance.new("Frame")
root.Name = "Lobby"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = UI.Screen

-- Status bar ---------------------------------------------------------------
local status = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.new(0, 460, 0, 70) })
UI.stroke(status, CYAN, 2, 0.4)
local statusTitle = UI.label(status, { Position = UDim2.new(0, 14, 0, 4), Size = UDim2.new(1, -28, 0, 36), Text = "KART HQ", TextColor3 = UI.Colors.yellow })
local statusSub = UI.label(status, { Position = UDim2.new(0, 14, 0, 40), Size = UDim2.new(1, -28, 0, 24), Text = "", TextColor3 = UI.Colors.muted })

-- Left column: coins, garage, watch ------------------------------------------
local coinPanel = UI.panel(root, { Position = UDim2.new(0, 14, 0, 14), Size = UDim2.new(0, 150, 0, 50) })
local coinLabel = UI.label(coinPanel, { Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(1, -20, 1, -12), Text = "🪙 0" })

function LobbyUI.setCoins(coins: number)
	coinLabel.Text = `🪙 {coins}`
end

local garageButton = UI.button(root, "🔧 GARAGE", UI.Colors.blue, { Position = UDim2.new(0, 14, 0, 74), Size = UDim2.new(0, 150, 0, 50) }, function()
	if LobbyUI.onGarage then
		LobbyUI.onGarage()
	end
end)
local watchButton = UI.button(root, "📺 WATCH", UI.Colors.purple, { Position = UDim2.new(0, 14, 0, 132), Size = UDim2.new(0, 150, 0, 50), Visible = false }, function()
	if LobbyUI.onWatch then
		LobbyUI.onWatch()
	end
end)

-- Bottom centre: ready / leave kart ------------------------------------------
local isReady = false
local readyButton = UI.button(root, "READY UP", UI.Colors.green, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(0, 260, 0, 66) }, function()
	if LobbyUI.onReady then
		LobbyUI.onReady(not isReady)
	end
end)
local leaveButton = UI.button(root, "🚪 LEAVE KART", UI.Colors.red, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -92), Size = UDim2.new(0, 220, 0, 52), Visible = false }, function()
	if LobbyUI.onLeavePractice then
		LobbyUI.onLeavePractice()
	end
end)

-- Vote row: three tracks + Random -------------------------------------------
local CARD_W, CARD_H, GAP = 152, 196, 12
local ROW_W = CARD_W * 4 + GAP * 3 + 20
local votePanel = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(0, ROW_W, 0, CARD_H + 64), Visible = false })
UI.stroke(votePanel, CYAN, 2, 0.35)
local voteTitle = UI.label(votePanel, { Position = UDim2.new(0, 14, 0, 6), Size = UDim2.new(0, 300, 0, 30), Text = "VOTE FOR A TRACK", TextColor3 = UI.Colors.yellow, TextXAlignment = Enum.TextXAlignment.Left })
UI.label(votePanel, { Position = UDim2.new(0, 14, 0, 36), Size = UDim2.new(1, -130, 0, 18), Text = "Tap a card or stand on its pad · 🎲 Random votes for one of these three, picked for you", TextColor3 = UI.Colors.muted, TextXAlignment = Enum.TextXAlignment.Left })
local leaveRace = UI.button(votePanel, "Leave race", UI.Colors.panelLight, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.new(0, 110, 0, 34) }, function()
	if LobbyUI.onReady then
		LobbyUI.onReady(false)
	end
end)
local cardHolder = Instance.new("Frame")
cardHolder.BackgroundTransparency = 1
cardHolder.Position = UDim2.new(0, 10, 0, 58)
cardHolder.Size = UDim2.new(1, -20, 0, CARD_H)
cardHolder.Parent = votePanel
UI.list(cardHolder, true, GAP)

type Card = {
	index: number,
	button: TextButton,
	art: Frame,
	badge: TextLabel,
	mine: TextLabel,
	name: TextLabel,
	chip: TextLabel,
	votes: TextLabel,
	faces: Frame,
	choice: string?,
	preview: TrackPreview.Preview?,
}

local function makeCard(index: number): Card
	local card: Card = { index = index } :: any
	card.button = UI.button(cardHolder, "", UI.Colors.panelLight, { Size = UDim2.new(0, CARD_W, 1, 0), LayoutOrder = index, AutoButtonColor = true }, function()
		if card.choice and LobbyUI.onVote then
			LobbyUI.onVote(card.choice)
		end
	end)
	card.art = Instance.new("Frame")
	card.art.Name = "Art"
	card.art.Position = UDim2.new(0, -4, 0, -2)
	card.art.Size = UDim2.new(1, 8, 0, 84)
	card.art.BackgroundColor3 = Color3.fromRGB(14, 18, 36)
	card.art.BorderSizePixel = 0
	card.art.Parent = card.button
	local artCorner = Instance.new("UICorner")
	artCorner.CornerRadius = UDim.new(0, 10)
	artCorner.Parent = card.art
	card.badge = UI.label(card.button, { Position = UDim2.new(0, -6, 0, -6), Size = UDim2.new(0, 28, 0, 28), Text = if index == LobbyLayout.RandomPad then "?" else tostring(index), BackgroundTransparency = 0, BackgroundColor3 = PAD_COLORS[index], TextColor3 = Color3.fromRGB(16, 22, 44), TextStrokeTransparency = 1, ZIndex = 3 })
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = card.badge
	card.mine = UI.label(card.button, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.new(0.86, 0, 0, 20), Text = "✓ YOUR VOTE", BackgroundTransparency = 0, BackgroundColor3 = UI.Colors.yellow, TextColor3 = Color3.fromRGB(30, 30, 40), TextStrokeTransparency = 1, Visible = false, ZIndex = 3 })
	local mineCorner = Instance.new("UICorner")
	mineCorner.CornerRadius = UDim.new(1, 0)
	mineCorner.Parent = card.mine
	card.name = UI.label(card.button, { Position = UDim2.new(0, 0, 0, 86), Size = UDim2.new(1, 0, 0, 24), Text = "" })
	card.chip = UI.label(card.button, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 112), Size = UDim2.new(0.62, 0, 0, 18), Text = "", BackgroundTransparency = 0, TextColor3 = Color3.fromRGB(30, 30, 40), TextStrokeTransparency = 1 })
	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UDim.new(1, 0)
	chipCorner.Parent = card.chip
	card.votes = UI.label(card.button, { Position = UDim2.new(0, 0, 0, 134), Size = UDim2.new(1, 0, 0, 20), Text = "" })
	card.faces = Instance.new("Frame")
	card.faces.BackgroundTransparency = 1
	card.faces.Position = UDim2.new(0, 0, 1, -28)
	card.faces.Size = UDim2.new(1, 0, 0, 24)
	card.faces.Parent = card.button
	UI.list(card.faces, true, 3, true)
	return card
end

local cards: { Card } = {}
for i = 1, 4 do
	cards[i] = makeCard(i)
end
-- The Random card's art: a big die on the Random colour.
local dice = UI.label(cards[4].art, { Size = UDim2.fromScale(1, 1), Text = "🎲", TextScaled = true })
local diceGradient = Instance.new("UIGradient")
diceGradient.Color = ColorSequence.new(PAD_COLORS[4], Color3.fromRGB(60, 40, 120))
diceGradient.Rotation = 90
diceGradient.Parent = cards[4].art
cards[4].art.BackgroundColor3 = Color3.new(1, 1, 1)

-- Winner reveal ----------------------------------------------------------------
local announce = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(0, 460, 0, 268), Visible = false })
UI.stroke(announce, UI.Colors.yellow, 3, 0.1)
UI.label(announce, { Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(1, 0, 0, 26), Text = "NEXT TRACK", TextColor3 = UI.Colors.yellow })
local announceArt = Instance.new("Frame")
announceArt.BackgroundTransparency = 1
announceArt.Position = UDim2.new(0, 14, 0, 36)
announceArt.Size = UDim2.new(1, -28, 0, 168)
announceArt.Parent = announce
local announceName = UI.label(announce, { Position = UDim2.new(0, 10, 0, 206), Size = UDim2.new(1, -20, 0, 34), Text = "" })
local announceSub = UI.label(announce, { Position = UDim2.new(0, 10, 0, 240), Size = UDim2.new(1, -20, 0, 20), Text = "Head for the departure doors!", TextColor3 = UI.Colors.muted })
local announcePreview: TrackPreview.Preview? = nil

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

local function setFaces(holder: Frame, userIds: { number }, max: number)
	for _, child in holder:GetChildren() do
		if child:IsA("ImageLabel") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for n, userId in userIds do
		if n > max then
			UI.label(holder, { Size = UDim2.new(0, 26, 0, 24), Text = `+{#userIds - max}`, LayoutOrder = n })
			break
		end
		local face = Instance.new("ImageLabel")
		face.Size = UDim2.new(0, 24, 0, 24)
		face.BackgroundColor3 = Color3.new(1, 1, 1)
		face.Image = UI.headshot(userId)
		face.LayoutOrder = n
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = face
		face.Parent = holder
	end
end

local function optionById(s: any, id: string?): any?
	for _, opt in s.options do
		if opt.id == id then
			return opt
		end
	end
	return nil
end

function LobbyUI.refresh()
	local s = state
	local mine = myEntry()
	local racing = mine and mine.racing
	root.Visible = not hidden
	if not s then
		return
	end

	local voter = mine ~= nil and mine.voter
	local voting = s.phase == "voting" and voter and not spectating
	local announcing = s.phase == "announce" and not racing and not spectating

	readyButton.Visible = not racing and not spectating and not voting and not announcing and s.phase ~= "results"
	readyButton.Text = if isReady then "✓ READY (tap to cancel)" else "READY UP"
	readyButton.BackgroundColor3 = if isReady then UI.Colors.yellow else UI.Colors.green
	readyButton.TextColor3 = if isReady then Color3.fromRGB(40, 40, 50) else UI.Colors.text
	garageButton.Visible = not spectating
	watchButton.Visible = s.phase == "racing" and s.spectate ~= nil and not racing and not spectating
	leaveButton.Visible = practicing and not spectating and not voting
	spectateBar.Visible = spectating

	-- Vote row.
	if voting ~= votePanel.Visible then
		votePanel.Visible = voting
		if voting then
			UI.pop(votePanel)
		end
	end
	leaveRace.Visible = voting
	if voting then
		local myVote = nil
		for _, opt in s.options do
			if table.find(opt.voters, me.UserId) then
				myVote = opt.id
			end
		end
		local myRandom = table.find(s.randomVoters or {}, me.UserId) ~= nil
		for i = 1, 3 do
			local card = cards[i]
			local opt = s.options[i]
			card.button.Visible = opt ~= nil
			if opt then
				card.choice = opt.id
				if not card.preview or card.preview.trackId ~= opt.id then
					if card.preview then
						card.preview:destroy()
					end
					card.preview = TrackPreview.new(card.art, opt.id)
				end
				card.button.BackgroundColor3 = UI.Colors.panelLight
				card.name.Text = `{opt.icon} {opt.name}`
				card.chip.Text = opt.difficulty
				card.chip.BackgroundColor3 = DIFFICULTY_COLORS[opt.difficulty] or UI.Colors.muted
				card.votes.Text = `{opt.votes} vote{if opt.votes == 1 then "" else "s"}`
				local selected = opt.id == myVote and not myRandom
				card.mine.Visible = selected
				UI.highlight(card.button, selected)
				card.button.BackgroundColor3 = if selected then PAD_COLORS[i]:Lerp(Color3.new(0, 0, 0), 0.55) else UI.Colors.panelLight
				setFaces(card.faces, opt.voters, 4)
			end
		end
		local random = cards[4]
		random.choice = Voting.Random
		random.name.Text = "RANDOM"
		random.chip.Text = "Surprise!"
		random.chip.BackgroundColor3 = PAD_COLORS[4]
		local picked = if myRandom then optionById(s, myVote) else nil
		random.votes.Text = if picked then `🎲 → {picked.name}` else "One of these 3"
		random.votes.TextColor3 = if picked then UI.Colors.yellow else UI.Colors.muted
		random.mine.Visible = myRandom
		UI.highlight(random.button, myRandom)
		random.button.BackgroundColor3 = if myRandom then PAD_COLORS[4]:Lerp(Color3.new(0, 0, 0), 0.55) else UI.Colors.panelLight
		setFaces(random.faces, s.randomVoters or {}, 4)
	end

	-- Winner reveal (everyone in the lobby sees it, like the wall screen).
	if announcing ~= announce.Visible then
		announce.Visible = announcing
		if announcing then
			UI.pop(announce)
		end
	end
	if announcing and s.winner then
		local opt = optionById(s, s.winner)
		if not announcePreview or announcePreview.trackId ~= s.winner then
			if announcePreview then
				announcePreview:destroy()
			end
			announcePreview = TrackPreview.new(announceArt, s.winner)
			-- The winning preview grows into place.
			local grow = Instance.new("UIScale")
			grow.Scale = 0.55
			grow.Parent = announcePreview.frame
			TweenService:Create(grow, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		announceName.Text = if opt then `{opt.icon} {opt.name}!` else ""
		announceSub.Text = if voter then "Head for the departure doors!" else "Ready up to race the next one"
	end
end

-- Called every frame for countdowns and animated previews.
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
			statusTitle.Text = "KART HQ"
			statusSub.Text = "Press READY or step onto a vote pad to race"
		end
	elseif s.phase == "voting" then
		statusTitle.Text = `VOTING · {left or 0}s`
		local mine = myEntry()
		statusSub.Text = if mine and mine.voter then "Pick a track below or stand on its pad" else "Step onto a pad to join this race"
		voteTitle.Text = `VOTE FOR A TRACK · {left or 0}s`
	elseif s.phase == "announce" then
		local opt = optionById(s, s.winner)
		statusTitle.Text = "TRACK LOCKED IN!"
		statusSub.Text = if opt then `{opt.name} · starting in {left or 0}s` else ""
	elseif s.phase == "racing" then
		statusTitle.Text = "RACE IN PROGRESS"
		statusSub.Text = if s.spectate then `{s.spectate.trackName} · ready up for the next race` else ""
	elseif s.phase == "results" then
		statusTitle.Text = "RESULTS"
		statusSub.Text = `Next round in {left or 0}s`
	end

	if votePanel.Visible then
		for _, card in cards do
			if card.preview and card.button.Visible then
				card.preview:step(os.clock())
			end
		end
	end
	if announce.Visible and announcePreview then
		announcePreview:step(os.clock())
	end
end

return LobbyUI
