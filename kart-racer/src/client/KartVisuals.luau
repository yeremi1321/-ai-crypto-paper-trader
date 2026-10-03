-- Makes every nearby kart look alive, on this client only: the body leans into
-- turns, dips under braking, bounces on bumps and squashes on landing; front
-- wheels steer; all wheels spin; exhaust puffs harder when accelerating. Your
-- own kart also shows the trick barrel roll.
--
-- It only sets Motor6D.Transform, which is purely visual and never affects
-- the physics.

local Workspace = game:GetService("Workspace")

local KartVisuals = {}

type Anim = { spin: number, lastSpeed: number, lastVy: number, squash: number, lean: number, pitch: number, steer: number }
local anims: { [Model]: Anim } = setmetatable({}, { __mode = "k" }) :: any

local FOLDERS = { "Karts", "PracticeKarts" }
local RANGE = 260

-- Set by KartController for the local player's kart.
local ownKart: Model? = nil
local ownSteer = 0
local ownTrickRoll = 0

function KartVisuals.setOwn(kart: Model?, steer: number, trickRoll: number)
	ownKart = kart
	ownSteer = steer
	ownTrickRoll = trickRoll
end

local function approach(a: number, b: number, rate: number): number
	return a + (b - a) * math.min(1, rate)
end

local function animate(kart: Model, dt: number, t: number)
	local root = kart.PrimaryPart
	if not root then
		return
	end
	local anim = anims[kart]
	if not anim then
		anim = { spin = 0, lastSpeed = 0, lastVy = 0, squash = 0, lean = 0, pitch = 0, steer = 0 }
		anims[kart] = anim
	end
	local vel = root.AssemblyLinearVelocity
	local look = root.CFrame.LookVector
	local speed = vel.X * look.X + vel.Z * look.Z
	local yawRate = root.AssemblyAngularVelocity.Y
	local accel = (speed - anim.lastSpeed) / math.max(dt, 1e-3)

	-- Landing squash: falling fast last frame, stopped now.
	if anim.lastVy < -25 and vel.Y > -5 then
		anim.squash = math.clamp(-anim.lastVy / 120, 0.1, 0.5)
	end
	anim.squash = math.max(0, anim.squash - dt * 2.5)
	anim.lastSpeed = speed
	anim.lastVy = vel.Y

	local isOwn = kart == ownKart
	-- Positive yaw rate is a left turn. Lean into the turn (positive Z roll
	-- dips the left side), lift the nose when accelerating, dip it when braking.
	local leanTarget = math.clamp(yawRate * speed * 0.0035, -0.2, 0.2)
	local pitchTarget = math.clamp(accel * 0.0012, -0.09, 0.09)
	anim.lean = approach(anim.lean, leanTarget, dt * 8)
	anim.pitch = approach(anim.pitch, pitchTarget, dt * 6)
	-- Steer is "right = positive", matching player input.
	local steerTarget = if isOwn then ownSteer * 0.45 else math.clamp(-yawRate * 0.25, -0.45, 0.45)
	anim.steer = approach(anim.steer, steerTarget, dt * 12)

	local speedFrac = math.clamp(math.abs(speed) / 100, 0, 1)
	local bob = math.sin(t * 21 + root.Position.X) * 0.035 * speedFrac - anim.squash * 0.5
	local trick = if isOwn then ownTrickRoll else 0

	local bodyJoint = root:FindFirstChild("BodyJoint") :: Motor6D?
	if bodyJoint then
		bodyJoint.Transform = CFrame.new(0, bob, 0) * CFrame.Angles(anim.pitch, 0, anim.lean + trick)
	end

	local radius = kart:GetAttribute("WheelRadius") or 0.8
	anim.spin = (anim.spin + speed / radius * dt) % (math.pi * 2)
	for _, joint in root:GetChildren() do
		if joint:IsA("Motor6D") and joint.Name == "WheelJoint" then
			local steer = if joint:GetAttribute("Front") then anim.steer else 0
			-- Rolling forward (-z) turns the wheel's top toward the front.
			joint.Transform = CFrame.Angles(0, -steer, 0) * CFrame.Angles(-anim.spin, 0, 0)
		end
	end

	local exhaust = kart:FindFirstChild("Exhaust")
	local puff = exhaust and exhaust:FindFirstChild("ExhaustPuff") :: ParticleEmitter?
	if puff then
		puff.Rate = if accel > 5 then 22 elseif math.abs(speed) > 5 then 8 else 4
	end
end

function KartVisuals.step(dt: number)
	local t = os.clock()
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	for _, name in FOLDERS do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			for _, kart in folder:GetChildren() do
				if kart:IsA("Model") and kart.PrimaryPart and (kart.PrimaryPart.Position - camPos).Magnitude < RANGE then
					animate(kart, dt, t)
				end
			end
		end
	end
end

return KartVisuals
