-- Rising Escape — client (v2: escape from inside the volcano)
-- Put this in StarterPlayer > StarterPlayerScripts as a LocalScript named EscapeObbyClient.
-- Builds all of its own UI (phone, tablet and desktop) and runs the team rope,
-- rope swings and eruption rumble for this player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("RisingEscapeRemotes")
local actionEvent = remotes:WaitForChild("Action")
local stateEvent = remotes:WaitForChild("State")

----------------------------------------------------------------------
-- Style
----------------------------------------------------------------------
local COLORS = {
	panel = Color3.fromRGB(28, 22, 20),
	row = Color3.fromRGB(46, 36, 32),
	text = Color3.fromRGB(245, 238, 232),
	muted = Color3.fromRGB(185, 170, 160),
	primary = Color3.fromRGB(255, 130, 40),
	good = Color3.fromRGB(60, 190, 90),
	bad = Color3.fromRGB(215, 70, 60),
	neutral = Color3.fromRGB(80, 66, 60),
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
-- In-round HUD, countdown, toast, rope prompts and results
----------------------------------------------------------------------
local hud = Instance.new("Frame")
hud.Name = "Hud"
hud.AnchorPoint = Vector2.new(0.5, 0)
hud.Position = UDim2.new(0.5, 0, 0, 6)
hud.Size = UDim2.new(0.62, 0, 0, 84)
hud.BackgroundColor3 = COLORS.panel
hud.BackgroundTransparency = 0.2
hud.Visible = false
corner(hud, 10)
padding(hud, 6)
local hudSize = Instance.new("UISizeConstraint")
hudSize.MinSize = Vector2.new(250, 0)
hudSize.MaxSize = Vector2.new(480, math.huge)
hudSize.Parent = hud
hud.Parent = gui

local hudTop = label(hud, "", 26, {
	Font = FONT_BOLD,
	TextXAlignment = Enum.TextXAlignment.Center,
})
local hudHint = label(hud, "", 24, {
	Position = UDim2.new(0, 0, 0, 26),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = COLORS.gold,
})
textSize(hudHint, 11, 16)
local hudBottom = label(hud, "", 20, {
	Position = UDim2.new(0, 0, 0, 52),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = COLORS.muted,
})

local hudLeave = button(gui, "Leave", COLORS.bad, function()
	actionEvent:FireServer("leave")
end)
hudLeave.Name = "HudLeave"
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
toast.Position = UDim2.new(0.5, 0, 0, 98)
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

-- "Don't let go!" banner while dangling from the rope.
local hangBanner = Instance.new("TextLabel")
hangBanner.AnchorPoint = Vector2.new(0.5, 0.5)
hangBanner.Position = UDim2.fromScale(0.5, 0.62)
hangBanner.Size = UDim2.new(0.7, 0, 0, 60)
hangBanner.BackgroundColor3 = Color3.fromRGB(120, 30, 20)
hangBanner.BackgroundTransparency = 0.15
hangBanner.Font = FONT_BOLD
hangBanner.TextColor3 = COLORS.text
hangBanner.TextScaled = true
hangBanner.Text = "DON'T LET GO! Your team can PULL you up"
hangBanner.Visible = false
textSize(hangBanner, 14, 26)
padding(hangBanner, 8)
corner(hangBanner, 10)
hangBanner.Parent = gui

-- Big PULL button, right side, above the mobile jump button.
local pullTarget = nil
local pullButton = button(gui, "PULL!", COLORS.primary, function()
	if pullTarget then
		actionEvent:FireServer("pull", pullTarget)
	end
end)
pullButton.AnchorPoint = Vector2.new(1, 0.5)
pullButton.Position = UDim2.new(1, -12, 0.4, 0)
pullButton.Size = UDim2.new(0, 170, 0, 64)
pullButton.Visible = false
textSize(pullButton, 14, 24)

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
-- Rendering from server state
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
		local count = #my.members
		startButton.Text = count < my.capacity and ("Start now (" .. count .. (count == 1 and " player)" or " players)"))
			or "Start"
	end
end

local function renderResults(round)
	clearRows(resultsList)
	local sectionCount = state.sectionCount or 6
	for index, row in ipairs(round.rows) do
		local line
		if row.status == "won" then
			line = string.format("#%d  %s  -  %.1fs", row.place or index, row.name, row.time or 0)
		else
			line = string.format("%s  -  %s (section %d/%d)", row.name, STATUS_TEXT[row.status] or row.status, row.section or 0, sectionCount)
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

	-- Lobby panel only when not playing; keep the player's Hide choice.
	if inRound or showingResults then
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

----------------------------------------------------------------------
-- Team rope, rope swing and eruption rumble
----------------------------------------------------------------------
local SWING_PUSH = 22 -- helps every swing make it across
local catch = nil -- { userId, length } while the rope holds me
local swing = nil -- { hook, length, dir, releaseX } while swinging
local swingUsed = false
local lastGroundY = nil
local hangingReported = false

local ropeFolder = Instance.new("Folder")
ropeFolder.Name = "RisingEscapeRopes"
ropeFolder.Parent = Workspace
local beams = {} -- [key] = Beam

local swingBeam = Instance.new("Beam")
swingBeam.Width0, swingBeam.Width1 = 0.3, 0.3
swingBeam.FaceCamera = true
swingBeam.Color = ColorSequence.new(Color3.fromRGB(90, 70, 50))
swingBeam.Enabled = false
swingBeam.Parent = ropeFolder

local function rootOf(p)
	local character = p and p.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function ropeAttachment(part)
	local attachment = part:FindFirstChild("RisingEscapeRope")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "RisingEscapeRope"
		attachment.Parent = part
	end
	return attachment
end

local function ropeLength()
	return (state and state.ropeLength) or 14
end

local function myNeighbours(round)
	local chain = round.chain or {}
	local index = table.find(chain, player.UserId)
	if not index then
		return {}
	end
	local list = {}
	if chain[index - 1] then
		table.insert(list, chain[index - 1])
	end
	if chain[index + 1] then
		table.insert(list, chain[index + 1])
	end
	return list
end

local function reportHanging(value)
	if hangingReported ~= value then
		hangingReported = value
		actionEvent:FireServer("hang", value)
	end
end

local function releaseCatch()
	if catch then
		catch = nil
	end
	reportHanging(false)
end

-- Keeps `pos` within `length` of `center`, like a rope. Returns new pos, vel.
local function constrain(root, center, length, pos, vel)
	local offset = pos - center
	local distance = offset.Magnitude
	if distance > length and distance > 0 then
		local n = offset / distance
		pos = center + n * length
		root.CFrame = CFrame.new(pos) * root.CFrame.Rotation
		local outward = vel:Dot(n)
		if outward > 0 then
			vel -= n * outward
		end
	end
	return pos, vel
end

stateEvent.OnClientEvent:Connect(function(kind, data)
	if kind == "state" and typeof(data) == "table" then
		state = data
		render()
	elseif kind == "notice" and typeof(data) == "string" then
		showToast(data)
	elseif kind == "pulled" then
		-- A teammate is hauling me up: shorten the rope and give a lift.
		local root = rootOf(player)
		if catch and root then
			catch.length = math.max(3, catch.length - 3.5)
			local anchor = rootOf(Players:GetPlayerByUserId(catch.userId))
			local toward = Vector3.zero
			if anchor then
				local flat = Vector3.new(anchor.Position.X - root.Position.X, 0, anchor.Position.Z - root.Position.Z)
				if flat.Magnitude > 0.1 then
					toward = flat.Unit * 8
				end
			end
			root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 28, root.AssemblyLinearVelocity.Z) + toward
			if typeof(data) == "string" then
				showToast(data .. " is pulling you up!")
			end
		end
	end
end)

-- Jump while swinging to let go early.
UserInputService.JumpRequest:Connect(function()
	if swing then
		swing = nil
		swingUsed = true
	end
end)

-- Desktop shortcut for PULL.
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.E and pullTarget then
		actionEvent:FireServer("pull", pullTarget)
	end
end)

-- Physics side runs before each physics step.
RunService.Stepped:Connect(function(_, dt)
	local round = state and state.round
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not round or round.phase ~= "running" or round.status ~= "alive" or not humanoid or not root or humanoid.Health <= 0 then
		releaseCatch()
		swing = nil
		lastGroundY = nil
		return
	end

	local pos = root.Position
	local vel = root.AssemblyLinearVelocity
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		lastGroundY = pos.Y
		swingUsed = false
		swing = nil
		releaseCatch()
		return
	end

	-- Grab a swing hook when jumping at it.
	if not swing and not swingUsed and not catch then
		for _, hook in ipairs(CollectionService:GetTagged("RisingEscapeHook")) do
			if hook:IsA("BasePart") then
				local dir = hook:GetAttribute("Dir")
				local startX = hook:GetAttribute("StartX")
				local releaseX = hook:GetAttribute("ReleaseX")
				local maxLength = hook:GetAttribute("MaxLength")
				if typeof(dir) == "number" and typeof(startX) == "number" and typeof(releaseX) == "number" and typeof(maxLength) == "number" then
					local hookPos = hook.Position
					local distance = (hookPos - pos).Magnitude
					if
						dir * (pos.X - startX) >= 0
						and dir * (pos.X - releaseX) < 0
						and math.abs(pos.Z - hookPos.Z) < 5
						and distance <= maxLength
						and pos.Y < hookPos.Y - 2
					then
						swing = { hook = hook, length = math.max(6, distance), dir = dir, releaseX = releaseX }
						break
					end
				end
			end
		end
	end

	if swing then
		if not swing.hook.Parent then
			swing = nil
		else
			pos, vel = constrain(root, swing.hook.Position, swing.length, pos, vel)
			vel += Vector3.new(swing.dir * SWING_PUSH * dt, 0, 0)
			if swing.dir * (pos.X - swing.releaseX) >= 0 then
				-- Past the gap: let go with a hop onto the far ledge.
				vel = Vector3.new(swing.dir * 20, 26, vel.Z * 0.3)
				swing = nil
				swingUsed = true
			end
			root.AssemblyLinearVelocity = vel
			return
		end
	end

	-- Team rope: if I fall off, a teammate standing above me catches me.
	if not catch and lastGroundY and pos.Y < lastGroundY - 3.5 and vel.Y < 0 then
		local best, bestDistance = nil, math.huge
		for _, userId in ipairs(myNeighbours(round)) do
			local anchor = rootOf(Players:GetPlayerByUserId(userId))
			if anchor then
				local distance = (anchor.Position - pos).Magnitude
				local steady = math.abs(anchor.AssemblyLinearVelocity.Y) < 6
				if steady and anchor.Position.Y > pos.Y + 1 and distance <= ropeLength() * 2 and distance < bestDistance then
					best, bestDistance = userId, distance
				end
			end
		end
		if best then
			catch = { userId = best, length = math.max(ropeLength(), bestDistance) }
			reportHanging(true)
		end
	end

	if catch then
		local anchor = rootOf(Players:GetPlayerByUserId(catch.userId))
		if not anchor or anchor.Position.Y < pos.Y - 1 or not table.find(myNeighbours(round), catch.userId) then
			releaseCatch() -- the anchor fell too, or left: nothing holds me now
			return
		end
		pos, vel = constrain(root, anchor.Position + Vector3.new(0, 1, 0), catch.length, pos, vel)
		vel *= 1 - math.min(0.5, 0.8 * dt) -- a little damping so the dangle settles
		root.AssemblyLinearVelocity = vel
	end
end)

-- Visual side: rope beams, PULL prompt, rumble and HUD text.
local shaking = false

RunService.RenderStepped:Connect(function()
	local round = state and state.round
	local t = Workspace:GetServerTimeNow()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local myRoot = character and character:FindFirstChild("HumanoidRootPart")
	local climbing = round ~= nil and round.phase == "running" and round.status == "alive"

	-- Rope beams between neighbouring living teammates.
	local wanted = {}
	if round and (round.phase == "running" or round.phase == "countdown") and round.chain then
		local limit = ropeLength() * 2.5
		for i = 1, #round.chain - 1 do
			local a = rootOf(Players:GetPlayerByUserId(round.chain[i]))
			local b = rootOf(Players:GetPlayerByUserId(round.chain[i + 1]))
			if a and b then
				local distance = (a.Position - b.Position).Magnitude
				if distance <= limit then
					local key = round.chain[i] .. "-" .. round.chain[i + 1]
					wanted[key] = true
					local beam = beams[key]
					if not beam then
						beam = Instance.new("Beam")
						beam.Width0, beam.Width1 = 0.35, 0.35
						beam.FaceCamera = true
						beam.LightEmission = 0.4
						beam.Segments = 1
						beam.Parent = ropeFolder
						beams[key] = beam
					end
					beam.Attachment0 = ropeAttachment(a)
					beam.Attachment1 = ropeAttachment(b)
					local strained = distance > ropeLength() * 1.05
					beam.Color = ColorSequence.new(strained and Color3.fromRGB(255, 70, 40) or Color3.fromRGB(255, 170, 80))
					beam.Enabled = true
				end
			end
		end
	end
	for key, beam in pairs(beams) do
		if not wanted[key] then
			beam:Destroy()
			beams[key] = nil
		end
	end

	-- Swing rope.
	if swing and myRoot then
		swingBeam.Attachment0 = ropeAttachment(swing.hook)
		swingBeam.Attachment1 = ropeAttachment(myRoot)
		swingBeam.Enabled = true
	else
		swingBeam.Enabled = false
	end

	-- PULL prompt: a dangling teammate below me, and I'm standing firm.
	pullTarget = nil
	if climbing and myRoot and humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
		for _, userId in ipairs(round.hanging or {}) do
			if userId ~= player.UserId then
				local other = Players:GetPlayerByUserId(userId)
				local otherRoot = rootOf(other)
				if other and otherRoot and otherRoot.Position.Y < myRoot.Position.Y then
					if (otherRoot.Position - myRoot.Position).Magnitude <= ropeLength() * 2.5 then
						pullTarget = userId
						pullButton.Text = "PULL " .. string.upper(other.DisplayName) .. " UP!"
						break
					end
				end
			end
		end
	end
	pullButton.Visible = pullTarget ~= nil
	hangBanner.Visible = climbing and catch ~= nil

	-- Eruption rumble: shake the camera near glowing or erupting vents.
	local amount = 0
	if climbing and myRoot then
		for _, vent in ipairs(CollectionService:GetTagged("RisingEscapeVent")) do
			if vent:IsA("BasePart") and (vent.Position - myRoot.Position).Magnitude < 30 then
				local ventState = vent:GetAttribute("State")
				if ventState == "active" then
					amount = math.max(amount, 0.35)
				elseif ventState == "warning" then
					amount = math.max(amount, 0.15)
				end
			end
		end
	end
	if humanoid then
		if amount > 0 then
			shaking = true
			humanoid.CameraOffset = Vector3.new(
				(math.random() - 0.5) * 2 * amount,
				(math.random() - 0.5) * 2 * amount,
				(math.random() - 0.5) * 2 * amount
			)
		elseif shaking then
			shaking = false
			humanoid.CameraOffset = Vector3.zero
		end
	end

	-- Countdown and HUD text.
	if not round then
		countdownLabel.Visible = false
		return
	end
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

	local sections = round.sections or {}
	local sectionIndex = math.max(1, round.section or 1)
	local current = sections[sectionIndex]
	local remaining = round.endsAt and math.max(0, round.endsAt - t) or 0
	hudTop.Text = string.format(
		"%ds  |  Section %d/%d  |  %s",
		math.ceil(remaining),
		sectionIndex,
		state.sectionCount or #sections,
		current and current.zone or ""
	)
	hudTop.TextColor3 = remaining <= 20 and COLORS.bad or COLORS.text
	hudHint.Text = current and (current.name .. ": " .. current.hint) or ""

	if round.status ~= "alive" then
		hudBottom.Text = (STATUS_TEXT[round.status] or round.status) .. " - waiting for your party"
		hudBottom.TextColor3 = COLORS.muted
		return
	end

	local lavaTop = round.lavaStartTop
	if round.lavaStartsAt and t > round.lavaStartsAt then
		lavaTop += (t - round.lavaStartsAt) * round.lavaRate
	end
	local parts = {}
	table.insert(parts, round.checkpoint > 0 and ("Checkpoint " .. round.checkpoint) or "No checkpoint")
	if myRoot then
		local gap = (myRoot.Position.Y - 3) - lavaTop
		if gap >= 0 then
			table.insert(parts, string.format("Lava %d studs below", math.floor(gap)))
		end
		hudBottom.TextColor3 = gap < 6 and COLORS.bad or COLORS.muted
		-- Rope status: detached when teammates are far away (e.g. after a respawn).
		local neighbours = myNeighbours(round)
		if #neighbours > 0 then
			local attached = false
			for _, userId in ipairs(neighbours) do
				local other = rootOf(Players:GetPlayerByUserId(userId))
				if other and (other.Position - myRoot.Position).Magnitude <= ropeLength() * 2.5 then
					attached = true
				end
			end
			table.insert(parts, attached and "Roped in" or "Rope detached: catch up!")
		end
	else
		table.insert(parts, "Respawning...")
		hudBottom.TextColor3 = COLORS.muted
	end
	hudBottom.Text = table.concat(parts, "   |   ")
end)

actionEvent:FireServer("refresh")
