-- The garage: a live 3D preview of your kart plus tabs for kart type (stats),
-- body, paint, wheels, stickers, horn, trail, name & plate, records and
-- settings. Locked items show their coin price; tap to unlock. Every change
-- goes to the server, which checks it, saves it and sends your data back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local KartBodies = require(Shared:WaitForChild("KartBodies"))
local Karts = require(Shared:WaitForChild("Karts"))
local Rewards = require(Shared:WaitForChild("Rewards"))
local Track = require(Shared:WaitForChild("Track"))
local Tracks = require(Shared:WaitForChild("Tracks"))
local KartRig = require(ReplicatedStorage:WaitForChild("Common"):WaitForChild("KartRig"))

local UI = require(script.Parent.UI)

local GarageUI = {}

-- Set by Main: (action, kind, value) sent to the server.
GarageUI.onAction = nil :: ((string, string, any) -> ())?

local data: any = nil
local canSave = true
local tab = "kart"

local panel = UI.panel(UI.Screen, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 860, 0, 560), Visible = false })
UI.label(panel, { Position = UDim2.new(0, 20, 0, 10), Size = UDim2.new(0, 260, 0, 44), Text = "🔧 GARAGE", TextColor3 = UI.Colors.yellow, TextXAlignment = Enum.TextXAlignment.Left })
local coinsLabel = UI.label(panel, { Position = UDim2.new(0, 280, 0, 14), Size = UDim2.new(0, 200, 0, 36), Text = "🪙 0", TextXAlignment = Enum.TextXAlignment.Left })
local saveNote = UI.label(panel, { Position = UDim2.new(0, 480, 0, 18), Size = UDim2.new(0, 280, 0, 28), Text = "", TextColor3 = UI.Colors.red })
UI.button(panel, "✕", UI.Colors.red, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.new(0, 52, 0, 46) }, function()
	GarageUI.close()
end)

-- Preview ------------------------------------------------------------------
local viewport = Instance.new("ViewportFrame")
viewport.Position = UDim2.new(0, 20, 0, 66)
viewport.Size = UDim2.new(0, 300, 0, 300)
viewport.BackgroundColor3 = Color3.fromRGB(60, 56, 100)
viewport.Ambient = Color3.fromRGB(170, 170, 190)
viewport.LightColor = Color3.fromRGB(255, 250, 240)
viewport.LightDirection = Vector3.new(-1, -2, -1)
viewport.Parent = panel
local vpCorner = Instance.new("UICorner")
vpCorner.CornerRadius = UDim.new(0, 18)
vpCorner.Parent = viewport
local world = Instance.new("WorldModel")
world.Parent = viewport
local vpCamera = Instance.new("Camera")
vpCamera.FieldOfView = 40
vpCamera.CFrame = CFrame.lookAt(Vector3.new(11, 7, -13), Vector3.new(0, 1.6, 0))
vpCamera.Parent = viewport
viewport.CurrentCamera = vpCamera
local floor = Instance.new("Part")
floor.Anchored = true
floor.Shape = Enum.PartType.Cylinder
floor.Size = Vector3.new(0.4, 16, 16)
floor.CFrame = CFrame.new(0, -0.2, 0) * CFrame.Angles(0, 0, math.rad(90))
floor.Color = Color3.fromRGB(230, 225, 240)
floor.Parent = world
local previewKart: Model? = nil
local nameLabel = UI.label(panel, { Position = UDim2.new(0, 20, 0, 372), Size = UDim2.new(0, 300, 0, 30), Text = "" })
local statsLabel = UI.label(panel, { Position = UDim2.new(0, 20, 0, 404), Size = UDim2.new(0, 300, 0, 60), TextScaled = false, TextSize = 16, Text = "", TextColor3 = UI.Colors.muted })

local function rebuildPreview()
	if previewKart then
		previewKart:Destroy()
		previewKart = nil
	end
	if not data then
		return
	end
	local e = data.equipped
	local look = { body = e.body, main = e.main, accent = e.accent, wheels = e.wheels, sticker = e.sticker, trail = "none", plate = e.plate }
	local ok, kart = pcall(KartRig.build, e.kart, if e.name ~= "" then e.name else "My Kart", CFrame.new(0, 0, 0), world, look)
	if ok then
		previewKart = kart
		local tag = kart:FindFirstChild("NameTag")
		if tag then
			tag:Destroy()
		end
	end
	nameLabel.Text = if e.name ~= "" then `"{e.name}"` else KartBodies.get(e.body).name
	local stats = Karts.get(e.kart)
	statsLabel.Text = `{stats.name} engine · {stats.blurb}`
end

RunService.RenderStepped:Connect(function()
	if previewKart and panel.Visible then
		local yaw = os.clock() * 0.6
		local pivot = CFrame.new(0, 0, 0) * CFrame.Angles(0, yaw, 0)
		previewKart:PivotTo(pivot + Vector3.new(0, KartRig.BallRadius + 0.2, 0))
	end
end)

-- Tabs -----------------------------------------------------------------------
local TABS = {
	{ id = "kart", name = "Engine" },
	{ id = "body", name = "Body" },
	{ id = "paint", name = "Paint" },
	{ id = "wheels", name = "Wheels" },
	{ id = "sticker", name = "Stickers" },
	{ id = "horn", name = "Horn" },
	{ id = "trail", name = "Trail" },
	{ id = "name", name = "Name & Plate" },
	{ id = "records", name = "Records" },
	{ id = "settings", name = "Settings" },
}
local tabBar = Instance.new("Frame")
tabBar.BackgroundTransparency = 1
tabBar.Position = UDim2.new(0, 340, 0, 66)
tabBar.Size = UDim2.new(1, -360, 0, 92)
tabBar.Parent = panel
local tabGrid = Instance.new("UIGridLayout")
tabGrid.CellSize = UDim2.new(0, 96, 0, 40)
tabGrid.CellPadding = UDim2.new(0, 6, 0, 6)
tabGrid.SortOrder = Enum.SortOrder.LayoutOrder
tabGrid.Parent = tabBar
local tabButtons: { [string]: TextButton } = {}
for i, t in TABS do
	tabButtons[t.id] = UI.button(tabBar, t.name, UI.Colors.panelLight, { LayoutOrder = i, TextScaled = true }, function()
		tab = t.id
		GarageUI.render()
	end)
end

local content = Instance.new("ScrollingFrame")
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.Position = UDim2.new(0, 340, 0, 168)
content.Size = UDim2.new(1, -360, 1, -184)
content.ScrollBarThickness = 8
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new()
content.Parent = panel

local function clear()
	for _, child in content:GetChildren() do
		child:Destroy()
	end
end

local function grid(cell: UDim2)
	local g = Instance.new("UIGridLayout")
	g.CellSize = cell
	g.CellPadding = UDim2.new(0, 8, 0, 8)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = content
end

local function act(action: string, kind: string, value: any)
	if GarageUI.onAction then
		GarageUI.onAction(action, kind, value)
	end
end

-- A tile for one cosmetic: equipped (highlighted), owned (tap to equip) or locked (tap to buy).
local function itemTile(kind: string, item: any, order: number)
	local owned = data.owned[kind] and data.owned[kind][item.id]
	local equipped = data.equipped[kind] == item.id
	local price = item.price or 0
	local color = if equipped then UI.Colors.green elseif owned then UI.Colors.panelLight else Color3.fromRGB(70, 60, 90)
	local tile = UI.button(content, "", color, { LayoutOrder = order }, function()
		if owned then
			act("equip", kind, item.id)
		else
			act("buy", kind, item.id)
		end
	end)
	UI.label(tile, { Size = UDim2.new(1, 0, 0.55, 0), Text = item.icon or "🏎️" })
	UI.label(tile, { Position = UDim2.new(0, 0, 0.55, 0), Size = UDim2.new(1, 0, 0.25, 0), Text = item.name })
	UI.label(tile, {
		Position = UDim2.new(0, 0, 0.8, 0),
		Size = UDim2.new(1, 0, 0.2, 0),
		Text = if equipped then "Equipped" elseif owned then "Owned" else `🪙 {price}`,
		TextColor3 = if owned then UI.Colors.muted else UI.Colors.yellow,
	})
	UI.highlight(tile, equipped)
end

local function textRow(order: number, title: string, kind: string, maxLength: number)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -10, 0, 56)
	row.LayoutOrder = order
	row.Parent = content
	UI.label(row, { Size = UDim2.new(0, 120, 1, 0), Text = title, TextXAlignment = Enum.TextXAlignment.Left })
	local box = Instance.new("TextBox")
	box.Position = UDim2.new(0, 130, 0, 6)
	box.Size = UDim2.new(1, -260, 0, 44)
	box.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
	box.TextColor3 = Color3.fromRGB(40, 40, 60)
	box.Font = UI.Font
	box.TextScaled = true
	box.ClearTextOnFocus = false
	box.PlaceholderText = `up to {maxLength} letters`
	box.Text = data.equipped[kind] or ""
	box.Parent = row
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = box
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > maxLength then
			box.Text = string.sub(box.Text, 1, maxLength)
		end
	end)
	UI.button(row, "SAVE", UI.Colors.green, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 6), Size = UDim2.new(0, 110, 0, 44) }, function()
		act("text", kind, box.Text)
	end)
end

function GarageUI.render()
	for id, b in tabButtons do
		b.BackgroundColor3 = if id == tab then UI.Colors.purple else UI.Colors.panelLight
	end
	clear()
	if not data then
		return
	end
	coinsLabel.Text = `🪙 {data.coins}`
	saveNote.Text = if canSave then "" else "⚠ Progress isn't saving this session"

	if tab == "kart" then
		grid(UDim2.new(0, 150, 0, 150))
		for i, def in Karts.List do
			local equipped = data.equipped.kart == def.id
			local tile = UI.button(content, "", if equipped then UI.Colors.green else UI.Colors.panelLight, { LayoutOrder = i }, function()
				act("equip", "kart", def.id)
			end)
			UI.label(tile, { Size = UDim2.new(1, 0, 0, 30), Text = def.name })
			UI.label(tile, { Position = UDim2.new(0, 0, 0, 34), Size = UDim2.new(1, 0, 1, -34), TextScaled = false, TextSize = 14, TextWrapped = true, Text = def.blurb, TextColor3 = UI.Colors.muted })
			UI.highlight(tile, equipped)
		end
	elseif tab == "body" then
		grid(UDim2.new(0, 112, 0, 112))
		for i, body in KartBodies.List do
			itemTile("body", { id = body.id, name = body.name, icon = (body :: any).icon or "🏎️", price = (body :: any).price or 0 }, i)
		end
	elseif tab == "paint" then
		UI.list(content, false, 8)
		for section, key in { "Paint", "Trim" } do
			local title = if key == "Paint" then "main" else "accent"
			UI.label(content, { LayoutOrder = section * 2 - 1, Size = UDim2.new(1, -10, 0, 30), Text = key, TextColor3 = UI.Colors.yellow, TextXAlignment = Enum.TextXAlignment.Left })
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.LayoutOrder = section * 2
			row.Size = UDim2.new(1, -10, 0, 108)
			row.Parent = content
			local g = Instance.new("UIGridLayout")
			g.CellSize = UDim2.new(0, 46, 0, 46)
			g.CellPadding = UDim2.new(0, 8, 0, 8)
			g.SortOrder = Enum.SortOrder.LayoutOrder
			g.Parent = row
			for i, c in KartBodies.Palette do
				local b = UI.button(row, "", Color3.fromRGB(c[1], c[2], c[3]), { LayoutOrder = i }, function()
					act("equip", title, i)
				end)
				UI.highlight(b, data.equipped[title] == i)
			end
		end
	elseif tab == "wheels" or tab == "sticker" or tab == "horn" or tab == "trail" then
		grid(UDim2.new(0, 112, 0, 112))
		for i, item in Cosmetics.Lists[tab] do
			itemTile(tab, item, i)
		end
	elseif tab == "name" then
		UI.list(content, false, 10)
		textRow(1, "Kart name", "name", Cosmetics.NameMaxLength)
		textRow(2, "Plate", "plate", Cosmetics.PlateMaxLength)
		UI.label(content, { LayoutOrder = 3, Size = UDim2.new(1, -10, 0, 40), TextScaled = false, TextSize = 15, Text = "Names and plates are checked by Roblox's text filter before others see them.", TextColor3 = UI.Colors.muted })
	elseif tab == "records" then
		UI.list(content, false, 6)
		local order = 0
		local function line(text: string, color: Color3?)
			order += 1
			UI.label(content, { LayoutOrder = order, Size = UDim2.new(1, -10, 0, 28), TextScaled = false, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, Text = text, TextColor3 = color or UI.Colors.text })
		end
		line("Track mastery", UI.Colors.yellow)
		for _, def in Tracks.List do
			local m = data.mastery[def.id]
			local length = Track.build(def).length
			local badge = if m then Rewards.badge(m, length) else 0
			local icon = if badge > 0 then Rewards.BadgeIcons[badge] else "▫️"
			local best = if m and m.bestLap then UI.time(m.bestLap) else "--"
			local wins = if m then m.wins else 0
			line(`{icon} {def.name}   best lap {best}   wins {wins}   gold lap {UI.time(Rewards.goldLap(length))}`)
		end
		line(" ")
		line("Challenges", UI.Colors.yellow)
		for _, c in Rewards.Challenges do
			local done = data.challenges[c.id]
			line(`{if done then "✅" else "⬜"} {c.name}   (+{c.reward} 🪙)`, if done then UI.Colors.muted else nil)
		end
		local tokens = 0
		for _ in data.tokens do
			tokens += 1
		end
		line(" ")
		line(`Golden tokens found: {tokens}   Races: {data.stats.races}   Wins: {data.stats.wins}`)
	elseif tab == "settings" then
		UI.list(content, false, 10)
		local options = {
			{ key = "autoAccelerate", name = "Auto-accelerate (great on phones)" },
			{ key = "reducedEffects", name = "Fewer effects (faster on older devices)" },
			{ key = "cameraFar", name = "Camera further back" },
		}
		for i, o in options do
			local on = data.settings[o.key]
			UI.button(content, `{if on then "✅" else "⬜"}  {o.name}`, if on then UI.Colors.green else UI.Colors.panelLight, { LayoutOrder = i, Size = UDim2.new(1, -10, 0, 52) }, function()
				act("setting", o.key, not on)
			end)
		end
	end
end

function GarageUI.setData(newData: any, saving: boolean?)
	data = newData
	canSave = saving ~= false
	if panel.Visible then
		GarageUI.render()
		rebuildPreview()
	end
end

function GarageUI.open()
	panel.Visible = true
	UI.pop(panel)
	GarageUI.render()
	rebuildPreview()
end

function GarageUI.close()
	panel.Visible = false
end

function GarageUI.toggle()
	if panel.Visible then
		GarageUI.close()
	else
		GarageUI.open()
	end
end

return GarageUI
