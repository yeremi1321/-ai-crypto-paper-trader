-- Shared look for every screen: rounded panels, chunky buttons sized for
-- thumbs, a friendly rounded font, soft outlines and gentle gradients.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UI = {}

UI.Font = Enum.Font.FredokaOne
UI.Colors = {
	panel = Color3.fromRGB(28, 26, 48),
	panelLight = Color3.fromRGB(48, 44, 80),
	text = Color3.fromRGB(255, 255, 255),
	muted = Color3.fromRGB(190, 190, 215),
	yellow = Color3.fromRGB(255, 210, 60),
	pink = Color3.fromRGB(255, 95, 140),
	green = Color3.fromRGB(70, 200, 120),
	red = Color3.fromRGB(230, 80, 90),
	blue = Color3.fromRGB(80, 150, 255),
	purple = Color3.fromRGB(150, 100, 240),
}

local screen = Instance.new("ScreenGui")
screen.Name = "KartUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
UI.Screen = screen

local function round(gui: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = gui
end

local function stroke(gui: GuiObject, color: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = gui
	return s
end
UI.stroke = stroke

local function apply(gui: Instance, props: { [string]: any }?)
	for k, v in props or {} do
		(gui :: any)[k] = v
	end
end

function UI.panel(parent: Instance, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UI.Colors.panel
	f.BackgroundTransparency = 0.08
	f.BorderSizePixel = 0
	round(f, 18)
	stroke(f, Color3.new(1, 1, 1), 2, 0.75)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 220))
	g.Parent = f
	apply(f, props)
	f.Parent = parent
	return f
end

function UI.label(parent: Instance, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UI.Font
	l.TextColor3 = UI.Colors.text
	l.TextScaled = true
	l.TextWrapped = true
	l.TextStrokeTransparency = 0.7
	apply(l, props)
	l.Parent = parent
	return l
end

-- A chunky rounded button with a little press bounce.
function UI.button(parent: Instance, text: string, color: Color3, props: { [string]: any }?, onClick: (() -> ())?): TextButton
	local b = Instance.new("TextButton")
	b.Font = UI.Font
	b.TextScaled = true
	b.TextColor3 = UI.Colors.text
	b.TextStrokeTransparency = 0.6
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Text = text
	round(b, 14)
	stroke(b, Color3.new(1, 1, 1), 2, 0.6)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = b
	apply(b, props)
	b.Parent = parent
	if onClick then
		b.Activated:Connect(function()
			local scale = b:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			scale.Parent = b
			scale.Scale = 0.92
			TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			onClick()
		end)
	end
	return b
end

function UI.list(parent: Instance, horizontal: boolean, padding: number, center: boolean?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, padding)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	if center then
		l.HorizontalAlignment = Enum.HorizontalAlignment.Center
		l.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	l.Parent = parent
	return l
end

function UI.highlight(gui: GuiObject, on: boolean)
	local s = gui:FindFirstChild("Highlight") :: UIStroke?
	if not s then
		s = stroke(gui, UI.Colors.yellow, 4)
		s.Name = "Highlight"
	end
	s.Enabled = on
end

-- Pops a panel in with a quick scale bounce.
function UI.pop(gui: GuiObject)
	local scale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = gui
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local thumbs: { [number]: string } = {}
-- Avatar headshot for a user (cached). Empty string until it loads.
function UI.headshot(userId: number): string
	if thumbs[userId] then
		return thumbs[userId]
	end
	thumbs[userId] = ""
	task.spawn(function()
		local ok, content = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		if ok then
			thumbs[userId] = content
		end
	end)
	return ""
end

function UI.ordinal(n: number): string
	local suffix = "th"
	if n % 100 < 11 or n % 100 > 13 then
		suffix = ({ "st", "nd", "rd" })[n % 10] or "th"
	end
	return `{n}{suffix}`
end

function UI.time(t: number?): string
	if not t then
		return "--"
	end
	local m = math.floor(t / 60)
	return string.format("%d:%05.2f", m, t - m * 60)
end

return UI
