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
UI.Gui = screen

-- Every screen is laid out in "design pixels" for a 1600x900 window and
-- scaled to fit: crisp and roomy at 1080p, compact on phones. The root frame
-- is grown by 1/scale so scale-based sizes (full-screen frames) still fill
-- the window after the UIScale shrinks or grows them.
UI.DesignSize = Vector2.new(1600, 900)
UI.MinScale = 0.72 -- below this, buttons get too small for thumbs
UI.MaxScale = 1.3
UI.scale = 1

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = screen
local rootScale = Instance.new("UIScale")
rootScale.Parent = root
UI.Screen = root

-- Panels that must fit the window (garage, results) get their own scale.
type Fit = { gui: GuiObject, size: Vector2 }
local fits: { Fit } = {}

local function fitScaleOf(fit: Fit): number
	local available = screen.AbsoluteSize / UI.scale
	if available.X <= 0 or available.Y <= 0 then
		return 1
	end
	return math.min(1, available.X * 0.96 / fit.size.X, available.Y * 0.94 / fit.size.Y)
end

local function rescale()
	local size = screen.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local s = math.min(size.X / UI.DesignSize.X, size.Y / UI.DesignSize.Y)
	s = math.clamp(s, UI.MinScale, UI.MaxScale)
	UI.scale = s
	rootScale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
	for _, fit in fits do
		local f = fitScaleOf(fit)
		fit.gui:SetAttribute("FitScale", f)
		local scale = fit.gui:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = f
		end
	end
end
screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
task.defer(rescale)

-- Keeps a fixed-size panel inside the window (it shrinks, never grows).
function UI.fit(gui: GuiObject, designSize: Vector2)
	local fit = { gui = gui, size = designSize }
	table.insert(fits, fit)
	local scale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = gui
	local f = fitScaleOf(fit)
	scale.Scale = f
	gui:SetAttribute("FitScale", f)
end

-- True on phones and tablets (touch with no keyboard): keep the thumbstick
-- and jump corners clear.
function UI.isTouch(): boolean
	local UserInputService = game:GetService("UserInputService")
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

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

-- Pops a panel in with a quick scale bounce (respecting UI.fit).
function UI.pop(gui: GuiObject)
	local scale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = gui
	local target = gui:GetAttribute("FitScale") or 1
	scale.Scale = target * 0.85
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = target }):Play()
end

local thumbs: { [string]: string } = {}
-- Avatar headshot for a user (cached). Empty string until it loads. `big`
-- fetches a sharper one for the wall screen.
function UI.headshot(userId: number, big: boolean?): string
	local key = `{userId}:{if big then 150 else 48}`
	if thumbs[key] then
		return thumbs[key]
	end
	thumbs[key] = ""
	task.spawn(function()
		local size = if big then Enum.ThumbnailSize.Size150x150 else Enum.ThumbnailSize.Size48x48
		local ok, content = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, size)
		if ok then
			thumbs[key] = content
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
