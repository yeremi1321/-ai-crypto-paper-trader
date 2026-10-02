-- Builds a kart and connects KartPhysics to Roblox physics. Shared by the
-- server (CPU karts) and the client (your own kart, which you own physics for).
--
-- How it moves: an invisible sphere carries the kart. A LinearVelocity pushes
-- it horizontally at the speed KartPhysics wants (vertical is left to
-- gravity, so hills and jumps just work), and an AlignOrientation turns the
-- visible body to match the heading and the slope of the road.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- FindFirstChild first so the smoke test (Lune has no WaitForChild) can load this.
local function child(parent: Instance, name: string): Instance
	return parent:FindFirstChild(name) or parent:WaitForChild(name)
end

local Shared = child(ReplicatedStorage, "Shared")
local KartPhysics = require(child(Shared, "KartPhysics"))
local KartBodies = require(child(Shared, "KartBodies"))
local Karts = require(child(Shared, "Karts"))

local KartRig = {}

KartRig.BallRadius = 2
local BODY_DROP = 1.0 -- body center sits this far below the ball center

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function visual(model: Model, root: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: string?): BasePart
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		if shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		end
		p = part
	end
	p.Name = name
	p.Size = size
	p.CFrame = root.CFrame * offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	weld(root, p)
	return p
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Colour and material for each body part role.
local function roleStyle(role: string, main: Color3, accent: Color3): (Color3, Enum.Material, number)
	if role == "main" then
		return main, Enum.Material.SmoothPlastic, 0
	elseif role == "accent" then
		return accent, Enum.Material.SmoothPlastic, 0
	elseif role == "glass" then
		return Color3.fromRGB(150, 210, 255), Enum.Material.Glass, 0.45
	elseif role == "chrome" then
		return Color3.fromRGB(205, 210, 220), Enum.Material.Metal, 0
	elseif role == "light" then
		return Color3.fromRGB(255, 250, 220), Enum.Material.Neon, 0
	end
	return Color3.fromRGB(35, 35, 40), Enum.Material.SmoothPlastic, 0
end

-- `cf` is where the kart should sit on the road (position on the surface).
-- `look` picks the body design and paint (see KartBodies); stats come from `kartId`.
function KartRig.build(kartId: string, driverName: string, cf: CFrame, parent: Instance, look: KartBodies.Look?): Model
	local def = Karts.get(kartId)
	local chosen = look or { body = KartBodies.Default, main = 1, accent = 10 }
	local body = KartBodies.get(chosen.body)
	local main = rgb(KartBodies.color(chosen.main))
	local accent = rgb(KartBodies.color(chosen.accent))

	local model = Instance.new("Model")
	model.Name = driverName

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.one * KartRig.BallRadius * 2
	root.CFrame = cf + Vector3.new(0, KartRig.BallRadius + 0.2, 0)
	root.Transparency = 1
	-- No friction: the LinearVelocity decides speed, walls just deflect.
	root.CustomPhysicalProperties = PhysicalProperties.new(0.6 + def.stats.weight * 0.25, 0, 0.1, 100, 1)
	root.Parent = model
	model.PrimaryPart = root

	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = root

	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"
	drive.Attachment0 = center
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	drive.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	drive.MaxAxesForce = Vector3.zero
	drive.VectorVelocity = Vector3.zero
	drive.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "Align"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = center
	align.MaxTorque = math.huge
	align.Responsiveness = 40
	align.CFrame = cf.Rotation
	align.Parent = root

	local drop = CFrame.new(0, -BODY_DROP, 0)
	for i, part in body.parts do
		local color, material, transparency = roleStyle(part.role, main, accent)
		local rot = part.rotation or { 0, 0, 0 }
		local offset = drop
			* CFrame.new(part.offset[1], part.offset[2], part.offset[3])
			* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
		local p = visual(model, root, `Body{i}`, Vector3.new(part.size[1], part.size[2], part.size[3]), offset, color, material, part.shape)
		p.Transparency = transparency
	end
	local ex = body.exhaust
	local exhaust = visual(model, root, "Exhaust", Vector3.new(1.2, 0.6, 0.4), drop * CFrame.new(ex[1], ex[2], ex[3]), Color3.fromRGB(255, 140, 40), Enum.Material.Neon)
	exhaust.Transparency = 1

	-- Wheels sit on the road: the body's center rides BODY_DROP below the ball's center.
	local groundToBody = KartRig.BallRadius - BODY_DROP
	local wheelY = body.wheelRadius - groundToBody
	local rearZ = -math.huge
	for _, w in body.wheels do
		rearZ = math.max(rearZ, w[2])
	end
	for i, w in body.wheels do
		local name = if w[2] >= rearZ then (if w[1] < 0 then "WheelRL" else "WheelRR") else `Wheel{i}`
		local d = body.wheelRadius * 2
		local wheel = visual(model, root, name, Vector3.new(body.wheelWidth, d, d), drop * CFrame.new(w[1], wheelY, w[2]), Color3.fromRGB(20, 20, 22), nil, "Cylinder")
		local hub = visual(model, root, `{name}Hub`, Vector3.new(body.wheelWidth + 0.05, d * 0.5, d * 0.5), drop * CFrame.new(w[1], wheelY, w[2]), accent, Enum.Material.Metal, "Cylinder")
		local _ = hub
		if w[2] >= rearZ then
			local sparks = Instance.new("ParticleEmitter")
			sparks.Name = "DriftSparks"
			sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparks.Size = NumberSequence.new(0.5, 0)
			sparks.Lifetime = NumberRange.new(0.15, 0.3)
			sparks.Speed = NumberRange.new(8, 14)
			sparks.SpreadAngle = Vector2.new(40, 40)
			sparks.EmissionDirection = Enum.NormalId.Back
			sparks.Rate = 60
			sparks.LightEmission = 1
			sparks.Enabled = false
			sparks.Parent = wheel
		end
	end

	local seatPos = body.seat
	local seat = Instance.new("Seat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.CFrame = root.CFrame * drop * CFrame.new(seatPos[1], seatPos[2], seatPos[3])
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Massless = true
	seat.Parent = model
	weld(root, seat)

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.new(0, 120, 0, 24)
	tag.StudsOffset = Vector3.new(0, 5, 0)
	tag.MaxDistance = 150
	tag.Adornee = root
	tag.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = driverName
	label.Parent = tag

	model:SetAttribute("KartId", def.id)
	model:SetAttribute("Body", body.id)
	model.Parent = parent
	return model
end

export type Sensed = { grounded: boolean, normal: Vector3, position: Vector3 }

-- Raycasts for the road under the kart. `ignore` should hold every kart.
function KartRig.sense(model: Model, params: RaycastParams): Sensed
	local root = model.PrimaryPart :: BasePart
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -(KartRig.BallRadius + 1.5), 0), params)
	return {
		grounded = hit ~= nil,
		normal = if hit then hit.Normal else Vector3.yAxis,
		position = root.Position,
	}
end

-- If something (a wall, another kart) is holding the kart back, let the
-- simulated speed drop to what the kart is really doing.
function KartRig.sync(model: Model, s: KartPhysics.State)
	local root = model.PrimaryPart :: BasePart
	local fx, fz = KartPhysics.forward(s.yaw)
	local actual = root.AssemblyLinearVelocity.X * fx + root.AssemblyLinearVelocity.Z * fz
	if s.speed > 20 and actual < s.speed * 0.6 then
		s.speed += (math.max(actual, 0) - s.speed) * 0.25
	end
end

function KartRig.apply(model: Model, s: KartPhysics.State, sensed: Sensed)
	local root = model.PrimaryPart :: BasePart
	local drive = root:FindFirstChild("Drive") :: LinearVelocity
	local align = root:FindFirstChild("Align") :: AlignOrientation

	local fx, fz = KartPhysics.forward(s.yaw)
	local force = root.AssemblyMass * (if sensed.grounded then 400 else 60)
	drive.MaxAxesForce = Vector3.new(force, 0, force)
	drive.VectorVelocity = Vector3.new(fx * s.speed, 0, fz * s.speed)

	local vyaw = KartPhysics.visualYaw(s)
	local look = Vector3.new(-math.sin(vyaw), 0, -math.cos(vyaw))
	local up = sensed.normal
	local right = look:Cross(up).Unit
	align.CFrame = CFrame.fromMatrix(Vector3.zero, right, up)
end

-- Effects every viewer sees: drift sparks by mini-turbo level, exhaust flame on boost.
local SPARK_COLORS = {
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(255, 150, 40),
	Color3.fromRGB(200, 90, 255),
}
function KartRig.setEffects(model: Model, driftLevel: number, boosting: boolean)
	for _, name in { "WheelRL", "WheelRR" } do
		local wheel = model:FindFirstChild(name)
		local sparks = wheel and wheel:FindFirstChild("DriftSparks") :: ParticleEmitter?
		if sparks then
			sparks.Enabled = driftLevel > 0
			if driftLevel > 0 then
				sparks.Color = ColorSequence.new(SPARK_COLORS[driftLevel])
			end
		end
	end
	local exhaust = model:FindFirstChild("Exhaust") :: BasePart?
	if exhaust then
		exhaust.Transparency = if boosting then 0.1 else 1
	end
end

-- Puts a kart back on the road (after falling off, or on the grid).
function KartRig.place(model: Model, cf: CFrame)
	local root = model.PrimaryPart :: BasePart
	model:PivotTo(cf + Vector3.new(0, KartRig.BallRadius + 0.2, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local align = root:FindFirstChild("Align") :: AlignOrientation
	align.CFrame = cf.Rotation
	local drive = root:FindFirstChild("Drive") :: LinearVelocity
	drive.VectorVelocity = Vector3.zero
end

return KartRig
