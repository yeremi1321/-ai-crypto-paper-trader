-- Drives your kart: reads input, runs KartPhysics on this client (you own the
-- kart's physics), handles drift / items / rocket starts, and runs the chase
-- camera.
--
-- Two modes: "race" (server tracks laps, respawns and items) and "practice"
-- (the lobby loop; nothing is scored and resets happen here on the client).
--
-- Controls: W/S or stick to drive, A/D steer, Space or Shift to drift,
-- E to use your item (hold S to aim it behind you), R to reset a stuck kart.
-- Gamepad: R2/L2 gas and brake, R1 drift, X item, Y reset.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local KartPhysics = require(Shared:WaitForChild("KartPhysics"))
local Karts = require(Shared:WaitForChild("Karts"))
local RaceRules = require(Shared:WaitForChild("RaceRules"))
local Track = require(Shared:WaitForChild("Track"))
local Tracks = require(Shared:WaitForChild("Tracks"))
local KartRig = require(ReplicatedStorage:WaitForChild("Common"):WaitForChild("KartRig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local KartController = {}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()

type Session = {
	mode: string, -- "race" | "practice"
	kart: Model,
	track: Track.Built,
	stats: Karts.KartStats,
	state: KartPhysics.State,
	goTime: number,
	hint: number?,
	throttleDownAt: number?,
	started: boolean,
	camYaw: number,
}

local session: Session? = nil
local driftHeld = false
local gasHeld, brakeHeld = false, false
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Hooks set by Main so the HUD can show speed, drift charge and warnings.
KartController.onUpdate = nil :: ((info: any) -> ())?
KartController.onTurbo = nil :: ((level: number) -> ())?
KartController.onWarning = nil :: ((text: string) -> ())?
KartController.onStopped = nil :: ((mode: string) -> ())?

local function refreshRayFilter()
	local ignore: { Instance } = {}
	for _, name in { "Karts", "Items", "PracticeKarts" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
end

local function setRacingControls(racing: boolean)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.JumpHeight = if racing then 0 else 7.2
		humanoid.JumpPower = if racing then 0 else 50
	end
	if racing then
		-- Bound above the default controls so Space drifts instead of jumping out.
		ContextActionService:BindActionAtPriority("KartDrift", function(_, inputState)
			driftHeld = inputState == Enum.UserInputState.Begin
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR1)
		ContextActionService:BindActionAtPriority("KartItem", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				KartController.useItem()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
		ContextActionService:BindActionAtPriority("KartReset", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				KartController.reset()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
		ContextActionService:BindActionAtPriority("KartPedals", function(action, inputState, input)
			local down = inputState ~= Enum.UserInputState.End
			if input.KeyCode == Enum.KeyCode.ButtonR2 then
				gasHeld = down
			else
				brakeHeld = down
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2)
	else
		ContextActionService:UnbindAction("KartDrift")
		ContextActionService:UnbindAction("KartItem")
		ContextActionService:UnbindAction("KartPedals")
		ContextActionService:UnbindAction("KartReset")
		driftHeld, gasHeld, brakeHeld = false, false, false
	end
end

-- Touch buttons call these.
function KartController.setDrift(on: boolean)
	driftHeld = on
end
local readInput: () -> (number, number)

function KartController.useItem()
	local s = session
	if not s or s.mode ~= "race" then
		return
	end
	-- Holding brake/back while using an item throws or drops it behind you.
	local throttle = readInput()
	Remotes.UseItem:FireServer(throttle < -0.3)
end

function KartController.isRacing(): boolean
	return session ~= nil and session.mode == "race"
end

function KartController.mode(): string?
	return session and session.mode
end

-- Puts the kart back on the road. In races the server does it (with a short
-- cooldown); on the practice loop the client does it directly.
function KartController.reset()
	local s = session
	if not s or not s.kart.PrimaryPart then
		return
	end
	if s.mode == "race" then
		Remotes.Respawn:FireServer()
		return
	end
	local root = s.kart.PrimaryPart
	local proj = Track.project(s.track, Track.v(root.Position.X, root.Position.Y, root.Position.Z))
	local pos = Track.spot(s.track, proj.distance, 0)
	local _, tan = Track.at(s.track, proj.distance)
	local yaw = math.atan2(-tan.x, -tan.z)
	KartRig.place(s.kart, CFrame.new(pos.x, pos.y, pos.z) * CFrame.Angles(0, yaw, 0))
	s.state.speed = 0
	s.state.yaw = yaw
	s.state.drift = 0
	s.state.charge = 0
	s.camYaw = yaw
	s.hint = nil
end

local function stop()
	local mode = session and session.mode
	session = nil
	setRacingControls(false)
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	if mode and KartController.onStopped then
		KartController.onStopped(mode)
	end
end

-- Stops driving without touching the camera (used when a racer finishes and
-- switches to spectating while the server drives their kart home).
function KartController.handOff()
	if session then
		session = nil
		setRacingControls(false)
		camera.FieldOfView = 70
	end
end

local function begin(info: any, mode: string)
	local kart: Model = info.kart
	local deadline = os.clock() + 10
	while (not kart or not kart.PrimaryPart) and os.clock() < deadline do
		task.wait()
	end
	if not kart or not kart.PrimaryPart then
		warn("[KartController] kart never arrived")
		return
	end
	session = {
		mode = mode,
		kart = kart,
		track = Track.build(Tracks.get(info.trackId)),
		stats = Karts.get(info.kartId).stats,
		state = KartPhysics.newState(info.yaw),
		goTime = info.goTime or (Workspace:GetServerTimeNow() - 1),
		hint = nil,
		throttleDownAt = nil,
		started = mode ~= "race",
		camYaw = info.yaw,
	}
	refreshRayFilter()
	setRacingControls(true)
	camera.CameraType = Enum.CameraType.Scriptable
end

function readInput(): (number, number)
	local move = controls:GetMoveVector()
	local steer = math.clamp(move.X, -1, 1)
	local throttle = math.clamp(-move.Z, -1, 1)
	if gasHeld then
		throttle = 1
	elseif brakeHeld then
		throttle = -1
	end
	return throttle, steer
end

local function updateCamera(s: Session, dt: number)
	local root = s.kart.PrimaryPart
	if not root then
		return
	end
	-- The camera follows travel direction, so drifts show the kart sliding.
	local diff = (s.state.yaw - s.camYaw + math.pi) % (2 * math.pi) - math.pi
	s.camYaw += diff * math.min(1, dt * 6)
	local fx, fz = KartPhysics.forward(s.camYaw)
	local forward = Vector3.new(fx, 0, fz)
	local target = root.Position + Vector3.new(0, 6.5, 0) - forward * 17
	local look = root.Position + forward * 10 + Vector3.new(0, 2, 0)
	camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(target, look), math.min(1, dt * 10))
	local fov = if s.state.boost > 0 then 84 else 70
	camera.FieldOfView += (fov - camera.FieldOfView) * math.min(1, dt * 5)
end

local function step(dt: number)
	local s = session
	if not s then
		return
	end
	if not s.kart.Parent or not s.kart.PrimaryPart then
		stop()
		return
	end
	local root = s.kart.PrimaryPart :: BasePart
	local t = Workspace:GetServerTimeNow()
	local throttle, steer = readInput()

	if t < s.goTime then
		-- Countdown: remember when the gas went down for the rocket start.
		if throttle > 0.5 then
			s.throttleDownAt = s.throttleDownAt or (t - s.goTime)
		else
			s.throttleDownAt = nil
		end
		if KartController.onUpdate then
			KartController.onUpdate({ speed = 0, drift = 0, wrongWay = false, countdown = s.goTime - t })
		end
		return
	end
	if not s.started then
		s.started = true
		local boost = RaceRules.startBoost(s.throttleDownAt)
		if boost > 0 then
			KartPhysics.giveBoost(s.state, boost)
			if KartController.onTurbo then
				KartController.onTurbo(0)
			end
		end
	end
	if root.Anchored then
		return
	end
	-- Off the edge of the practice area: put the kart back.
	if s.mode == "practice" and root.Position.Y < -25 then
		KartController.reset()
		return
	end

	local sensed = KartRig.sense(s.kart, rayParams)
	local pos = Track.v(root.Position.X, root.Position.Y, root.Position.Z)
	local proj = Track.project(s.track, pos, s.hint)
	s.hint = proj.index
	local surface = Track.surfaceAt(s.track, proj)
	if s.mode == "practice" and (surface == "offroad" or surface == "wall") then
		surface = "road" -- the practice area is open tarmac
	end

	local _, released = KartPhysics.step(s.stats, s.state, {
		throttle = throttle,
		steer = steer,
		drift = driftHeld,
		grounded = sensed.grounded,
		surface = if surface == "wall" then "offroad" else surface,
	}, dt)
	KartRig.sync(s.kart, s.state)
	KartRig.apply(s.kart, s.state, sensed)
	local level = if s.state.drift ~= 0 then KartPhysics.chargeLevel(s.state.charge) else 0
	KartRig.setEffects(s.kart, level, s.state.boost > 0)
	if released > 0 and KartController.onTurbo then
		KartController.onTurbo(released)
	end

	if KartController.onUpdate then
		local fx, fz = KartPhysics.forward(s.state.yaw)
		KartController.onUpdate({
			speed = s.state.speed,
			drift = level,
			boosting = s.state.boost > 0,
			invincible = s.state.invincible > 0,
			wrongWay = s.mode == "race" and s.state.speed > 15 and Track.wrongWay(s.track, proj, fx, fz),
		})
	end
end

local function onKartEvent(kind: string, value: any)
	local s = session
	if not s then
		return
	end
	if kind == "warning" then
		if KartController.onWarning then
			KartController.onWarning(tostring(value))
		end
	elseif kind == "hit" or kind == "spin" then
		KartPhysics.hit(s.state)
	elseif kind == "slow" then
		KartPhysics.slow(s.state, 2)
	elseif kind == "launch" then
		KartPhysics.hit(s.state)
		local root = s.kart.PrimaryPart
		if root then
			root.AssemblyLinearVelocity += Vector3.new(0, 70, 0)
		end
	elseif kind == "boost" then
		KartPhysics.giveBoost(s.state, tonumber(value) or 1)
	elseif kind == "overdrive" then
		KartPhysics.overdrive(s.state, tonumber(value) or 6)
	elseif kind == "respawn" then
		s.state.speed = 0
		s.state.yaw = tonumber(value) or s.state.yaw
		s.state.drift = 0
		s.state.charge = 0
		s.camYaw = s.state.yaw
		s.hint = nil
	end
end

function KartController.start()
	Remotes.RaceStart.OnClientEvent:Connect(function(info)
		task.spawn(begin, info, "race")
	end)
	Remotes.PracticeStart.OnClientEvent:Connect(function(info)
		task.spawn(begin, info, "practice")
	end)
	Remotes.KartEvent.OnClientEvent:Connect(onKartEvent)
	Remotes.Results.OnClientEvent:Connect(function()
		if session and session.mode == "race" then
			stop()
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, math.min(dt, 0.1))
		if not ok then
			warn("[KartController]", err)
		end
	end)
	-- Camera runs every rendered frame so it stays smooth.
	RunService:BindToRenderStep("KartCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if session and session.kart.PrimaryPart then
			updateCamera(session, dt)
		end
	end)
	player.CharacterAdded:Connect(function()
		if session then
			task.defer(refreshRayFilter)
		end
	end)
end

return KartController
