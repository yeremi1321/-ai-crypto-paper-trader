-- The garage: choose your kart type (stats), body design and paint. Opens
-- from the GARAGE button or the garage building in the lobby.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local KartBodies = require(Shared:WaitForChild("KartBodies"))
local Karts = require(Shared:WaitForChild("Karts"))

local UI = require(script.Parent.UI)

local GarageUI = {}

GarageUI.onChooseKart = nil :: ((string) -> ())?
GarageUI.onLook = nil :: ((any) -> ())?

local chosenKart = Karts.Default
local look = { body = KartBodies.Default, main = 1, accent = 10 }

local panel = UI.panel(UI.Screen, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 640, 0, 520), Visible = false })
UI.label(panel, { Position = UDim2.new(0, 20, 0, 10), Size = UDim2.new(1, -100, 0, 44), Text = "🔧 GARAGE", TextColor3 = UI.Colors.yellow, TextXAlignment = Enum.TextXAlignment.Left })
UI.button(panel, "✕", UI.Colors.red, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.new(0, 52, 0, 46) }, function()
	GarageUI.close()
end)

local function statBar(n: number, lo: number, hi: number): string
	local filled = math.clamp(math.floor((n - lo) / (hi - lo) * 5 + 0.5), 1, 5)
	return string.rep("●", filled) .. string.rep("○", 5 - filled)
end

-- Kart type cards (these set the stats).
local cards = Instance.new("Frame")
cards.BackgroundTransparency = 1
cards.Position = UDim2.new(0, 20, 0, 64)
cards.Size = UDim2.new(1, -40, 0, 160)
cards.Parent = panel
UI.list(cards, true, 10)
local cardButtons: { [string]: TextButton } = {}
for _, def in Karts.List do
	local c = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
	local card = UI.button(cards, "", c:Lerp(Color3.new(0, 0, 0), 0.55), { Size = UDim2.new(1 / 3, -7, 1, 0) }, function()
		chosenKart = def.id
		if GarageUI.onChooseKart then
			GarageUI.onChooseKart(def.id)
		end
		GarageUI.refresh()
	end)
	UI.label(card, { Size = UDim2.new(1, 0, 0, 30), Text = def.name, TextColor3 = c })
	UI.label(card, {
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		TextScaled = false,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = `{def.blurb}\nSpeed  {statBar(def.stats.topSpeed, 88, 108)}\nAccel  {statBar(def.stats.accel, 44, 72)}\nTurn   {statBar(def.stats.handling, 1.9, 2.4)}`,
	})
	cardButtons[def.id] = card
end

local function row(y: number, title: string, height: number): Frame
	UI.label(panel, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(0, 80, 0, height), TextScaled = false, TextSize = 18, Text = title, TextXAlignment = Enum.TextXAlignment.Left })
	local r = Instance.new("Frame")
	r.BackgroundTransparency = 1
	r.Position = UDim2.new(0, 100, 0, y)
	r.Size = UDim2.new(1, -120, 0, height)
	r.Parent = panel
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.new(0, 6, 0, 6)
	grid.CellSize = if height > 60 then UDim2.new(0, 160, 0, 40) else UDim2.new(0, 36, 0, 36)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = r
	return r
end

local bodyButtons: { [string]: TextButton } = {}
local mainSwatches: { TextButton } = {}
local accentSwatches: { TextButton } = {}

local function sendLook()
	if GarageUI.onLook then
		GarageUI.onLook(look)
	end
	GarageUI.refresh()
end

local bodyRow = row(238, "Body", 132)
for _, body in KartBodies.List do
	bodyButtons[body.id] = UI.button(bodyRow, body.name, UI.Colors.panelLight, {}, function()
		look.body = body.id
		sendLook()
	end)
end

local function swatches(y: number, title: string, list: { TextButton }, key: string)
	local r = row(y, title, 36)
	for i, c in KartBodies.Palette do
		list[i] = UI.button(r, "", Color3.fromRGB(c[1], c[2], c[3]), {}, function()
			look[key] = i
			sendLook()
		end)
	end
end
swatches(384, "Paint", mainSwatches, "main")
swatches(432, "Trim", accentSwatches, "accent")

function GarageUI.refresh()
	for id, card in cardButtons do
		UI.highlight(card, id == chosenKart)
	end
	for id, b in bodyButtons do
		UI.highlight(b, id == look.body)
	end
	for i, b in mainSwatches do
		UI.highlight(b, i == look.main)
	end
	for i, b in accentSwatches do
		UI.highlight(b, i == look.accent)
	end
end
GarageUI.refresh()

function GarageUI.open()
	panel.Visible = true
	UI.pop(panel)
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
