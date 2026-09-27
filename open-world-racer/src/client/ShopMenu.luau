-- Menus for the physical shops: the dealership sells cars, the tuning shop
-- sells and fits parts, and your garage switches cars, expands bays and
-- manages saved builds (street / drag / drift / track) and paint.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared:WaitForChild("CarCatalog"))
local Performance = require(Shared:WaitForChild("Performance"))
local PlayerProfile = require(Shared:WaitForChild("PlayerProfile"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Hud = require(script.Parent.Hud)

local ShopMenu = {}

local PAINTS = {
	{ 200, 200, 205 },
	{ 20, 20, 24 },
	{ 200, 30, 40 },
	{ 250, 140, 20 },
	{ 245, 210, 40 },
	{ 40, 170, 80 },
	{ 30, 110, 220 },
	{ 140, 60, 200 },
}

local profile: any = nil
local openKind: string? = nil

local panel = Hud.frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 520, 0, 460), Parent = Hud.gui })
panel.Visible = false
local title = Hud.label({ Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -80, 0, 30), Font = Enum.Font.GothamBlack, Parent = panel })
Hud.button(panel, "X", UDim2.new(1, -46, 0, 10), UDim2.new(0, 34, 0, 30), Color3.fromRGB(90, 40, 45), function()
	ShopMenu.close()
end)
local list = Instance.new("ScrollingFrame")
list.Position = UDim2.new(0, 12, 0, 50)
list.Size = UDim2.new(1, -24, 1, -62)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local order = 0
local function row(text: string, actionText: string?, color: Color3?, onClick: (() -> ())?)
	order += 1
	local r = Instance.new("Frame")
	r.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	r.BorderSizePixel = 0
	r.Size = UDim2.new(1, -10, 0, 40)
	r.LayoutOrder = order
	r.Parent = list
	Hud.label({ Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -140, 1, 0), TextScaled = false, TextSize = 15, TextWrapped = true, Text = text, Parent = r })
	if actionText and onClick then
		Hud.button(r, actionText, UDim2.new(1, -120, 0, 5), UDim2.new(0, 112, 0, 30), color or Color3.fromRGB(50, 110, 200), onClick)
	end
end

local function header(text: string)
	order += 1
	Hud.label({ Size = UDim2.new(1, -10, 0, 26), LayoutOrder = order, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 200, 40), Text = text, Parent = list })
end

local function act(...)
	Remotes.ShopAction:FireServer(...)
end

local function activeCar(): any
	return profile and profile.cars[profile.activeCar]
end

local function partsSection(canBuy: boolean)
	local car = activeCar()
	if not car then
		return
	end
	header(`Installed on {car.name} ({car.class} {car.rating})`)
	if #car.parts == 0 then
		row("Stock - nothing installed yet.")
	end
	for _, partId in car.parts do
		local part = CarCatalog.getPart(partId)
		row(part and part.name or partId, "Remove", Color3.fromRGB(110, 60, 60), function()
			act("remove", partId)
		end)
	end

	header("Your spare parts")
	local any = false
	for partId, count in profile.inventory do
		if count > 0 then
			any = true
			local part = CarCatalog.getPart(partId)
			local rating, class = Performance.forBuild(car.carId, (function()
				local test = table.clone(car.parts)
				table.insert(test, 1, partId) -- new part wins its slot
				return test
			end)())
			row(`{part and part.name or partId} x{count}  ->  {class} {rating}`, "Install", nil, function()
				act("install", partId)
			end)
		end
	end
	if not any then
		row("No spare parts. Find stashes around the city or buy some.")
	end

	if canBuy then
		header("Parts for sale")
		local ids = {}
		for id in CarCatalog.Parts do
			table.insert(ids, id)
		end
		table.sort(ids, function(a, b)
			return CarCatalog.Parts[a].price < CarCatalog.Parts[b].price
		end)
		for _, id in ids do
			local part = CarCatalog.Parts[id]
			row(`{part.name} ({part.slot})  ${part.price}`, "Buy", Color3.fromRGB(40, 140, 80), function()
				act("buyPart", id)
			end)
		end
	end
end

local function buildsSection()
	local car = activeCar()
	if not car then
		return
	end
	header("Saved builds")
	for _, slot in PlayerProfile.BuildSlots do
		local saved = table.find(car.builds, slot) ~= nil
		row(`{slot:upper()} build {if saved then "(saved)" else "(empty)"}`, "Save current", Color3.fromRGB(70, 70, 90), function()
			act("saveBuild", slot)
		end)
		if saved then
			row(`   Switch to {slot} setup`, "Load", nil, function()
				act("loadBuild", slot)
			end)
		end
	end
end

local function paintSection()
	header("Paint")
	for i, c in PAINTS do
		row(`Colour {i}`, "Paint", Color3.fromRGB(c[1], c[2], c[3]), function()
			act("paint", c[1], c[2], c[3])
		end)
	end
end

local function render()
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	order = 0
	if not profile or not openKind then
		return
	end

	if openKind == "dealership" then
		title.Text = `Crown Motors  -  ${profile.cash}`
		header(`Garage bays used: {#profile.cars}/{profile.garageBays}`)
		local ids = {}
		for id in CarCatalog.Cars do
			table.insert(ids, id)
		end
		table.sort(ids, function(a, b)
			return CarCatalog.Cars[a].price < CarCatalog.Cars[b].price
		end)
		for _, id in ids do
			local car = CarCatalog.Cars[id]
			local rating, class = Performance.forBuild(id, {})
			row(`{car.name} - {car.archetype}\n{class} {rating}  -  {car.stats.drivetrain}  -  ${car.price}`, "Buy", Color3.fromRGB(40, 140, 80), function()
				act("buyCar", id)
			end)
		end
	elseif openKind == "tuning" then
		title.Text = `Torque Lab Tuning  -  ${profile.cash}`
		partsSection(true)
		buildsSection()
		paintSection()
	elseif openKind == "garage" then
		title.Text = `Your Garage  -  ${profile.cash}`
		header(`Cars ({#profile.cars}/{profile.garageBays} bays)`)
		for i, car in profile.cars do
			local isActive = i == profile.activeCar
			row(`{car.name}  {car.class} {car.rating}{if isActive then "  (driving)" else ""}`, if isActive then nil else "Take out", nil, if isActive
				then nil
				else function()
					act("select", i)
				end)
		end
		if profile.nextBayPrice then
			row(`Add a garage bay`, `$ {profile.nextBayPrice}`, Color3.fromRGB(40, 140, 80), function()
				act("buyBay")
			end)
		end
		header("Street reputation")
		for _, r in profile.rep do
			row(`{r.name}: {r.tier} ({r.rep})`)
		end
		row(`Races {profile.stats.races}  -  Wins {profile.stats.wins}`)
		partsSection(false)
		buildsSection()
		paintSection()
	end
end

function ShopMenu.open(kind: string)
	openKind = kind
	panel.Visible = true
	render()
end

function ShopMenu.close()
	openKind = nil
	panel.Visible = false
end

function ShopMenu.setProfile(p: any)
	profile = p
	if openKind then
		render()
	end
end

return ShopMenu
