-- Rising Escape Obby — client UI
-- Put this in StarterPlayer > StarterPlayerScripts as a LocalScript named EscapeObbyClient.
-- It builds all of its own UI, sized for phones, tablets and desktop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("RisingEscapeRemotes")
local actionEvent = remotes:WaitForChild("Action")
local stateEvent = remotes:WaitForChild("State")

----------------------------------------------------------------------
-- Style
----------------------------------------------------------------------
local COLORS = {
	panel = Color3.fromRGB(24, 26, 34),
	row = Color3.fromRGB(38, 41, 54),
	text = Color3.fromRGB(240, 240, 245),
	muted = Color3.fromRGB(170, 175, 190),
	primary = Color3.fromRGB(255, 140, 40),
	good = Color3.fromRGB(60, 190, 90),
	bad = Color3.fromRGB(215, 70, 60),
	neutral = Color3.fromRGB(70, 75, 95),
	gold = Color3.fromRGB(255, 205, 60),
}
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold
local ROW_HEIGHT = 44 -- comfortable touch target

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function padding(parent, px)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
	return p
end

local function textSize(parent, minSize, maxSize)
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = minSize
	c.MaxTextSize = maxSize
	c.Parent = parent
end

local function label(parent, text, height, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, height)
	l.Font = FONT
	l.Text = text
	l.TextColor3 = COLORS.text
	l.TextScaled = true
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	textSize(l, 12, 20)
	for key, value in pairs(props or {}) do
		l[key] = value
	end
	l.Parent = parent
	return l
end

local function button(parent, text, color, onActivated)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color
	b.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	b.Font = FONT_BOLD
	b.Text = text
	b.TextColor3 = COLORS.text
	b.TextScaled = true
	textSize(b, 12, 20)
	padding(b, 8)
	corner(b)
	b.Activated:Connect(onActivated) -- works for mouse, touch and gamepad
	b.Parent = parent
	return b
end

local function listLayout(parent, spacing)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, spacing or 6)
	layout.Parent = parent
	return layout
end

local function clearRows(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

----------------------------------------------------------------------
-- Root GUI
----------------------------------------------------------------------
local oldGui = playerGui:FindFirstChild("RisingEscapeGui")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "RisingEscapeGui"
gui.ResetOnSpawn = false -- keep the UI when the character dies
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- stay clear of notches and the Roblox top bar
gui.Parent = playerGui

----------------------------------------------------------------------
-- Lobby panel (top-centre, leaves the bottom free for thumbstick/jump)
----------------------------------------------------------------------
local panel = Instance.new("Frame")
panel.Name = "LobbyPanel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 6)
panel.Size = UDim2.new(0.55, 0, 0.62, 0)
panel.BackgroundColor3 = COLORS.panel
panel.BackgroundTransparency = 0.08
corner(panel, 12)
padding(panel, 10)
local panelSize = Instance.new("UISizeConstraint")
panelSize.MinSize = Vector2.new(260, 180)
panelSize.MaxSize = Vector2.new(400, 460)
panelSize.Parent = panel
panel.Parent = gui

local header = Instance.new("Frame")
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 36)
header.Parent = panel

label(header, "RISING ESCAPE", 36, {
	Size = UDim2.new(1, -90, 1, 0),
	Font = FONT_BOLD,
	TextColor3 = COLORS.primary,
})

local showButton -- defined below
local hideButton = button(header, "Hide", COLORS.neutral, function()
	panel.Visible = false
	showButton.Visible = true
end)
hideButton.AnchorPoint = Vector2.new(1, 0)
hideButton.Position = UDim2.new(1, 0, 0, 0)
hideButton.Size = UDim2.new(0, 80, 1, 0)

local body = Instance.new("ScrollingFrame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.Position = UDim2.new(0, 0, 0, 42)
body.Size = UDim2.new(1, 0, 1, -42)
body.CanvasSize = UDim2.new()
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.ScrollingDirection = Enum.ScrollingDirection.Y
body.ScrollBarThickness = 6
body.Parent = panel
listLayout(body, 8)

showButton = button(gui, "Party", COLORS.primary, function()
	panel.Visible = true
	showButton.Visible = false
end)
showButton.AnchorPoint = Vector2.new(0.5, 0)
showButton.Position = UDim2.new(0.5, 0, 0, 6)
showButton.Size = UDim2.new(0, 120, 0, ROW_HEIGHT)
showButton.Visible = false

local noticeLabel = label(body, "Connecting...", 24, { LayoutOrder = 1, TextColor3 = COLORS.muted })

-- "Create party" section
local createSection = Instance.new("Frame")
createSection.BackgroundTransparency = 1
createSection.Size = UDim2.new(1, 0, 0, 0)
createSection.AutomaticSize = Enum.AutomaticSize.Y
createSection.LayoutOrder = 2
createSection.Parent = body
listLayout(createSection, 6)

label(createSection, "Party size (max players)", 22, { LayoutOrder = 1, TextColor3 = COLORS.muted })

local selectedCapacity = 4

local sizeRow = Instance.new("Frame")
sizeRow.BackgroundTransparency = 1
sizeRow.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
sizeRow.LayoutOrder = 2
sizeRow.Parent = createSection

local sizeLabel = label(sizeRow, "", ROW_HEIGHT, {
	Size = UDim2.new(1, -120, 1, 0),
	Position = UDim2.new(0, 60, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = FONT_BOLD,
})

local function refreshSizeLabel()
	sizeLabel.Text = selectedCapacity == 1 and "1 player (solo)" or (selectedCapacity .. " players")
end
refreshSizeLabel()

local minusButton = button(sizeRow, "-", COLORS.neutral, function()
	selectedCapacity = math.max(1, selectedCapacity - 1)
	refreshSizeLabel()
end)
minusButton.Size = UDim2.new(0, 54, 1, 0)

local plusButton = button(sizeRow, "+", COLORS.neutral, function()
	selectedCapacity = math.min(6, selectedCapacity + 1)
	refreshSizeLabel()
end)
plusButton.AnchorPoint = Vector2.new(1, 0)
plusButton.Position = UDim2.new(1, 0, 0, 0)
plusButton.Size = UDim2.new(0, 54, 1, 0)

local createButton = button(createSection, "Create party", COLORS.primary, function()
	actionEvent:FireServer("create", selectedCapacity)
end)
createButton.LayoutOrder = 3

label(createSection, "Open parties", 22, { LayoutOrder = 4, TextColor3 = COLORS.muted })

local partyList = Instance.new("Frame")
partyList.BackgroundTransparency = 1
partyList.Size = UDim2.new(1, 0, 0, 0)
partyList.AutomaticSize = Enum.AutomaticSize.Y
partyList.LayoutOrder = 5
partyList.Parent = createSection
listLayout(partyList, 6)

-- "My party" section
local mySection = Instance.new("Frame")
mySection.BackgroundTransparency = 1
mySection.Size = UDim2.new(1, 0, 0, 0)
mySection.AutomaticSize = Enum.AutomaticSize.Y
mySection.LayoutOrder = 3
mySection.Visible = false
mySection.Parent = body
listLayout(mySection, 6)

local myTitle = label(mySection, "", 26, { LayoutOrder = 1, Font = FONT_BOLD })

local myCapacity = 1
local capacityRow = Instance.new("Frame")
capacityRow.BackgroundTransparency = 1
capacityRow.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
capacityRow.LayoutOrder = 2
capacityRow.Parent = mySection

local capacityLabel = label(capacityRow, "", ROW_HEIGHT, {
	Size = UDim2.new(1, -120, 1, 0),
	Position = UDim2.new(0, 60, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Center,
})
local capMinus = button(capacityRow, "-", COLORS.neutral, function()
	actionEvent:FireServer("capacity", myCapacity - 1)
end)
capMinus.Size = UDim2.new(0, 54, 1, 0)
local capPlus = button(capacityRow, "+", COLORS.neutral, function()
	actionEvent:FireServer("capacity", myCapacity + 1)
end)
capPlus.AnchorPoint = Vector2.new(1, 0)
capPlus.Position = UDim2.new(1, 0, 0, 0)
capPlus.Size = UDim2.new(0, 54, 1, 0)

local memberList = Instance.new("Frame")
memberList.BackgroundTransparency = 1
memberList.Size = UDim2.new(1, 0, 0, 0)
memberList.AutomaticSize = Enum.AutomaticSize.Y
memberList.LayoutOrder = 3
memberList.Parent = mySection
listLayout(memberList, 4)

local startButton = button(mySection, "Start", COLORS.good, function()
	actionEvent:FireServer("start")
end)
startButton.LayoutOrder = 4

local leaveButton = button(mySection, "Leave party", COLORS.bad, function()
	actionEvent:FireServer("leave")
end)
leaveButton.LayoutOrder = 5

----------------------------------------------------------------------
-- In-round HUD (top-centre bar), countdown, toast and results
----------------------------------------------------------------------
local hud = Instance.new("Frame")
hud.Name = "Hud"
hud.AnchorPoint = Vector2.new(0.5, 0)
hud.Position = UDim2.new(0.5, 0, 0, 6)
hud.Size = UDim2.new(0.6, 0, 0, 64)
hud.BackgroundColor3 = COLORS.panel
hud.BackgroundTransparency = 0.2
hud.Visible = false
corner(hud, 10)
padding(hud, 6)
local hudSize = Instance.new("UISizeConstraint")
hudSize.MinSize = Vector2.new(240, 0)
hudSize.MaxSize = Vector2.new(460, math.huge)
hudSize.Parent = hud
hud.Parent = gui

local hudTop = label(hud, "", 28, {
	Font = FONT_BOLD,
	TextXAlignment = Enum.TextXAlignment.Center,
})
local hudBottom = label(hud, "", 22, {
	Position = UDim2.new(0, 0, 0, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = COLORS.muted,
})

local hudLeave = button(gui, "Leave", COLORS.bad, function()
	actionEvent:FireServer("leave")
end)
hudLeave.Name = "HudLeave"
hudLeave.AnchorPoint = Vector2.new(0, 0)
hudLeave.Position = UDim2.new(0, 6, 0, 6)
hudLeave.Size = UDim2.new(0, 80, 0, 40)
hudLeave.Visible = false

local countdownLabel = Instance.new("TextLabel")
countdownLabel.BackgroundTransparency = 1
countdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
countdownLabel.Position = UDim2.fromScale(0.5, 0.4)
countdownLabel.Size = UDim2.fromScale(0.5, 0.25)
countdownLabel.Font = FONT_BOLD
countdownLabel.TextScaled = true
countdownLabel.TextColor3 = COLORS.gold
countdownLabel.TextStrokeTransparency = 0.2
countdownLabel.Visible = false
textSize(countdownLabel, 24, 120)
countdownLabel.Parent = gui

local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 78)
toast.Size = UDim2.new(0.6, 0, 0, 34)
toast.BackgroundColor3 = COLORS.row
toast.BackgroundTransparency = 0.15
toast.Font = FONT_BOLD
toast.TextColor3 = COLORS.text
toast.TextScaled = true
toast.Visible = false
toast.ZIndex = 5
textSize(toast, 12, 20)
padding(toast, 6)
corner(toast)
toast.Parent = gui

local results = Instance.new("Frame")
results.Name = "Results"
results.AnchorPoint = Vector2.new(0.5, 0.5)
results.Position = UDim2.fromScale(0.5, 0.45)
results.Size = UDim2.fromScale(0.6, 0.7)
results.BackgroundColor3 = COLORS.panel
results.BackgroundTransparency = 0.08
results.Visible = false
corner(results, 12)
padding(results, 10)
local resultsSize = Instance.new("UISizeConstraint")
resultsSize.MinSize = Vector2.new(260, 180)
resultsSize.MaxSize = Vector2.new(420, 440)
resultsSize.Parent = results
results.Parent = gui

local resultsTitle = label(results, "Results", 34, {
	Font = FONT_BOLD,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = COLORS.gold,
})
local resultsList = Instance.new("ScrollingFrame")
resultsList.BackgroundTransparency = 1
resultsList.BorderSizePixel = 0
resultsList.Position = UDim2.new(0, 0, 0, 40)
resultsList.Size = UDim2.new(1, 0, 1, -64)
resultsList.CanvasSize = UDim2.new()
resultsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
resultsList.ScrollBarThickness = 6
resultsList.Parent = results
listLayout(resultsList, 4)
local resultsFooter = label(results, "", 20, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = COLORS.muted,
})

----------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------
local state = nil
local toastToken = 0

local STATUS_TEXT = {
	alive = "Climbing",
	won = "Escaped!",
	eliminated = "Burned",
	timeout = "Out of time",
	left = "Left",
	spectating = "Watching",
}

local function showToast(text)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(3, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

local function rowFrame(parent, order)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = COLORS.row
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.LayoutOrder = order
	corner(row)
	padding(row, 6)
	row.Parent = parent
	return row
end

local function renderPartyList(parties)
	clearRows(partyList)
	local shown = 0
	for index, info in ipairs(parties) do
		if info.phase == "lobby" and info.count < info.capacity then
			shown += 1
			local row = rowFrame(partyList, index)
			label(row, string.format("%s's party  %d/%d", info.host, info.count, info.capacity), ROW_HEIGHT - 12, {
				Size = UDim2.new(1, -90, 1, 0),
			})
			local join = button(row, "Join", COLORS.good, function()
				actionEvent:FireServer("join", info.id)
			end)
			join.AnchorPoint = Vector2.new(1, 0)
			join.Position = UDim2.new(1, 0, 0, 0)
			join.Size = UDim2.new(0, 80, 1, 0)
		end
	end
	if shown == 0 then
		label(partyList, "No open parties yet. Create one!", 22, { TextColor3 = COLORS.muted })
	end
end

local function renderMyParty(my)
	myCapacity = my.capacity
	myTitle.Text = string.format("Your party  %d/%d", #my.members, my.capacity)
	capacityRow.Visible = my.isHost and my.phase == "lobby"
	capacityLabel.Text = "Max " .. my.capacity .. " players"
	clearRows(memberList)
	for index, member in ipairs(my.members) do
		label(memberList, (member.isHost and "[Host] " or "- ") .. member.name, 24, { LayoutOrder = index })
	end
	startButton.Visible = my.isHost and my.phase == "lobby"
	if my.isHost then
		startButton.Text = #my.members < my.capacity and "Start now (" .. #my.members .. " player" .. (#my.members == 1 and ")" or "s)")
			or "Start"
	end
end

local function renderResults(round)
	clearRows(resultsList)
	for index, row in ipairs(round.rows) do
		local line
		if row.status == "won" then
			line = string.format("#%d  %s  -  %.1fs", row.place or index, row.name, row.time or 0)
		else
			line = string.format("%s  -  %s (stage %d/%d)", row.name, STATUS_TEXT[row.status] or row.status, row.stage or 0, state.stageCount or 12)
		end
		local r = rowFrame(resultsList, index)
		r.Size = UDim2.new(1, 0, 0, 36)
		label(r, line, 24, { TextColor3 = row.status == "won" and COLORS.gold or COLORS.text })
	end
	local mine = STATUS_TEXT[round.status] or round.status
	resultsTitle.Text = round.status == "won" and "You escaped!" or ("Result: " .. mine)
end

local function render()
	if not state then
		return
	end
	local my = state.myParty
	local round = state.round
	local inRound = round ~= nil and (round.phase == "countdown" or round.phase == "running")
	local showingResults = round ~= nil and round.phase == "results"

	-- Lobby panel only when not playing; keep the user's Hide choice.
	local lobbyAllowed = not inRound and not showingResults
	if not lobbyAllowed then
		panel.Visible = false
		showButton.Visible = false
	elseif not panel.Visible and not showButton.Visible then
		panel.Visible = true
	end

	createSection.Visible = my == nil
	mySection.Visible = my ~= nil
	if my then
		noticeLabel.Text = my.isHost and "You are the host. Start whenever you're ready."
			or "Waiting for the host to start..."
		renderMyParty(my)
	else
		noticeLabel.Text = "Create a party or join one below."
		renderPartyList(state.parties or {})
	end

	hud.Visible = inRound
	hudLeave.Visible = inRound
	results.Visible = showingResults
	if showingResults then
		renderResults(round)
	end
end

stateEvent.OnClientEvent:Connect(function(kind, data)
	if kind == "state" and typeof(data) == "table" then
		state = data
		render()
	elseif kind == "notice" and typeof(data) == "string" then
		showToast(data)
	end
end)

-- Per-frame text: timer, countdown, lava distance.
RunService.RenderStepped:Connect(function()
	local round = state and state.round
	if not round then
		countdownLabel.Visible = false
		return
	end
	local t = Workspace:GetServerTimeNow()

	if round.phase == "countdown" and round.goAt then
		countdownLabel.Visible = true
		countdownLabel.Text = tostring(math.max(1, math.ceil(round.goAt - t)))
	elseif round.phase == "running" and round.goAt and t - round.goAt < 1 then
		countdownLabel.Visible = true
		countdownLabel.Text = "GO!"
	else
		countdownLabel.Visible = false
	end

	if round.phase == "results" then
		local left = math.max(0, math.ceil((round.resultsEndAt or t) - t))
		resultsFooter.Text = "Back to lobby in " .. left .. "s"
		return
	end

	local remaining = round.endsAt and math.max(0, round.endsAt - t) or 0
	local stageText = string.format("Stage %d/%d", round.stage or 0, state.stageCount or 12)
	hudTop.Text = string.format("%ds   |   %s", math.ceil(remaining), stageText)
	hudTop.TextColor3 = remaining <= 15 and COLORS.bad or COLORS.text

	if round.status ~= "alive" then
		hudBottom.Text = (STATUS_TEXT[round.status] or round.status) .. " - waiting for your party"
		hudBottom.TextColor3 = COLORS.muted
		return
	end

	local lavaTop = round.lavaStartTop
	if round.lavaStartsAt and t > round.lavaStartsAt then
		lavaTop += (t - round.lavaStartsAt) * round.lavaRate
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local checkpointText = round.checkpoint > 0 and ("Checkpoint " .. round.checkpoint) or "No checkpoint"
	if root then
		local gap = (root.Position.Y - 3) - lavaTop
		if gap < 0 then
			hudBottom.Text = checkpointText .. "   |   Respawning..."
			hudBottom.TextColor3 = COLORS.muted
		else
			hudBottom.Text = string.format("%s   |   Lava %d studs below", checkpointText, math.floor(gap))
			hudBottom.TextColor3 = gap < 6 and COLORS.bad or COLORS.muted
		end
	else
		hudBottom.Text = checkpointText .. "   |   Respawning..."
		hudBottom.TextColor3 = COLORS.muted
	end
end)

actionEvent:FireServer("refresh")
