-- Spectator camera: follows a racer's kart from behind. Used by lobby players
-- watching a race and by racers who have already finished.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Spectate = {}

local camera = Workspace.CurrentCamera
local active = false
local order: { string } = {} -- kart (driver) names in race order
local index = 1
local onTargetChanged: ((string?) -> ())? = nil

local function karts(): Instance?
	return Workspace:FindFirstChild("Karts")
end

local function target(): Model?
	local folder = karts()
	if not folder or #order == 0 then
		return nil
	end
	index = (index - 1) % #order + 1
	local m = folder:FindFirstChild(order[index])
	return if m and m:IsA("Model") then m else nil
end

function Spectate.isActive(): boolean
	return active
end

-- `names` is the race order (leader first).
function Spectate.setOrder(names: { string })
	local current = order[index]
	order = names
	local found = table.find(order, current)
	index = found or 1
end

function Spectate.start(names: { string }?, changed: ((string?) -> ())?)
	active = true
	onTargetChanged = changed
	if names then
		order = names
		index = 1
	end
	camera.CameraType = Enum.CameraType.Scriptable
	if onTargetChanged then
		onTargetChanged(order[index])
	end
end

function Spectate.cycle(step: number)
	if #order == 0 then
		return
	end
	index = (index - 1 + step) % #order + 1
	if onTargetChanged then
		onTargetChanged(order[index])
	end
end

function Spectate.stop()
	if not active then
		return
	end
	active = false
	camera.CameraType = Enum.CameraType.Custom
	local character = game:GetService("Players").LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

RunService:BindToRenderStep("SpectateCamera", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if not active then
		return
	end
	local m = target()
	local root = m and m.PrimaryPart
	if not root then
		return
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.zAxis
	end
	flat = flat.Unit
	local goal = CFrame.lookAt(root.Position - flat * 20 + Vector3.new(0, 8, 0), root.Position + flat * 8)
	camera.CFrame = camera.CFrame:Lerp(goal, math.min(1, dt * 6))
end)

return Spectate
