-- Builds a kart and connects KartPhysics to Roblox physics. Shared by the
-- server (CPU karts) and the client (your own kart, which you own physics for).
--
-- How it looks alive: the body hangs off the ball on a Motor6D ("BodyJoint")
-- and each wheel has its own Motor6D, so clients (client/KartVisuals) can
-- lean the body into turns, bounce the suspension, flip it for tricks, steer
-- the front wheels and spin all of them, without touching the physics.
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
local Assets = require(child(child(ReplicatedStorage, "Common"), "Assets"))
local KartPhysics = require(child(Shared, "KartPhysics"))
local Cosmetics = require(child(Shared, "Cosmetics"))
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

local function visual(model: Model, root: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: string?, weldTo: BasePart?): BasePart
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	elseif shape == "Ellipsoid" then
		local part = Instance.new("Part")
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		p = part
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
	weld(weldTo or root, p)
	return p
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = CFrame.new()
	m.Parent = part0
	return m
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Colour, material, transparency and default reflectance for each body
-- part role. Realistic bodies get a clear-coat gloss on the paint, polished
-- chrome and darker, matte trim; cartoon bodies stay smooth and flat.
local function roleStyle(role: string, main: Color3, accent: Color3, realistic: boolean?): (Color3, Enum.Material, number, number)
	if role == "main" then
		return main, Enum.Material.SmoothPlastic, 0, if realistic then 0.12 else 0
	elseif role == "accent" then
		return accent, Enum.Material.SmoothPlastic, 0, if realistic then 0.1 else 0
	elseif role == "glass" then
		return if realistic then Color3.fromRGB(70, 90, 105) else Color3.fromRGB(150, 210, 255), Enum.Material.Glass, if realistic then 0.35 else 0.45, if realistic then 0.2 else 0
	elseif role == "chrome" then
		return Color3.fromRGB(205, 210, 220), Enum.Material.Metal, 0, if realistic then 0.35 else 0
	elseif role == "light" then
		return Color3.fromRGB(255, 250, 220), Enum.Material.Neon, 0, 0
	end
	return if realistic then Color3.fromRGB(28, 28, 32) else Color3.fromRGB(35, 35, 40), if realistic then Enum.Material.Plastic else Enum.Material.SmoothPlastic, 0, 0
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
	-- Everything that leans and bounces hangs off this invisible part.
	local bodyRoot = Instance.new("Part")
	bodyRoot.Name = "BodyRoot"
	bodyRoot.Size = Vector3.one
	bodyRoot.CFrame = root.CFrame * drop
	bodyRoot.Transparency = 1
	bodyRoot.CanCollide = false
	bodyRoot.CanQuery = false
	bodyRoot.CanTouch = false
	bodyRoot.Massless = true
	bodyRoot.Parent = model
	motor("BodyJoint", root, bodyRoot, drop)

	for i, part in body.parts do
		local color, material, transparency, reflectance = roleStyle(part.role, main, accent, body.realistic)
		if part.color then
			color = Color3.fromRGB(part.color[1], part.color[2], part.color[3])
		end
		if part.material then
			material = (Enum.Material :: any)[part.material] or material
		end
		transparency = part.transparency or transparency
		local rot = part.rotation or { 0, 0, 0 }
		local localCf = CFrame.new(part.offset[1], part.offset[2], part.offset[3])
			* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
		local p = visual(model, root, `Body{i}`, Vector3.new(part.size[1], part.size[2], part.size[3]), drop * localCf, color, material, part.shape, bodyRoot)
		p.Transparency = transparency
		p.Reflectance = part.reflectance or reflectance

		if part.anim then
			-- Swap the weld for a Motor6D so the client can animate this part.
			local w = p:FindFirstChildOfClass("WeldConstraint")
			if w then
				w:Destroy()
			end
			local m = Instance.new("Motor6D")
			m.Name = "Anim"
			m.Part0 = bodyRoot
			m.Part1 = p
			if part.anim == "orbit" then
				-- Pivot on the kart's centre line so it circles the kart.
				m.C0 = CFrame.new(0, part.offset[2], 0)
				m.C1 = CFrame.new(-part.offset[1], 0, -part.offset[3])
			else
				m.C0 = localCf
				m.C1 = CFrame.new()
			end
			m:SetAttribute("AnimKind", part.anim)
			m:SetAttribute("Side", if part.offset[1] < 0 then -1 else 1)
			m.Parent = bodyRoot
		end

		if part.text then
			for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
				local gui = Instance.new("SurfaceGui")
				gui.Face = face
				gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				gui.PixelsPerStud = 30
				gui.Parent = p
				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.PermanentMarker
				label.TextScaled = true
				label.TextColor3 = Color3.fromRGB(40, 40, 70)
				label.Rotation = -6
				label.Text = part.text
				label.Parent = gui
			end
		end

		if part.bubbles then
			local bubbles = Instance.new("ParticleEmitter")
			bubbles.Name = "Bubbles"
			bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			bubbles.Color = ColorSequence.new(Color3.fromRGB(210, 240, 255), Color3.fromRGB(255, 210, 245))
			bubbles.Size = NumberSequence.new(0.4, 1.1)
			bubbles.Transparency = NumberSequence.new(0.2, 1)
			bubbles.Lifetime = NumberRange.new(0.6, 1.2)
			bubbles.Speed = NumberRange.new(4, 8)
			bubbles.SpreadAngle = Vector2.new(30, 30)
			bubbles.Acceleration = Vector3.new(0, 6, 0)
			bubbles.EmissionDirection = Enum.NormalId.Back
			bubbles.Rate = 14
			bubbles.Parent = p
		end
	end
	local ex = body.exhaust
	local exhaust = visual(model, root, "Exhaust", Vector3.new(1.2, 0.6, 0.4), drop * CFrame.new(ex[1], ex[2], ex[3]), Color3.fromRGB(255, 140, 40), Enum.Material.Neon, nil, bodyRoot)
	exhaust.Transparency = 1
	local puff = Instance.new("ParticleEmitter")
	puff.Name = "ExhaustPuff"
	puff.Texture = "rbxasset://textures/particles/smoke_main.dds"
	puff.Color = ColorSequence.new(Color3.fromRGB(235, 235, 245))
	puff.Size = NumberSequence.new(0.5, 1.6)
	puff.Transparency = NumberSequence.new(0.5, 1)
	puff.Lifetime = NumberRange.new(0.4, 0.7)
	puff.Speed = NumberRange.new(3, 6)
	puff.EmissionDirection = Enum.NormalId.Back
	puff.Rate = 6
	puff.Parent = exhaust

	-- Wheels sit on the road: the body's center rides BODY_DROP below the ball's center.
	local groundToBody = KartRig.BallRadius - BODY_DROP
	-- Wheel style (cosmetic): scales the body's own wheels.
	local wheelStyle = Cosmetics.find("wheels", (chosen :: any).wheels) or Cosmetics.Wheels[1]
	local wheelRadius = body.wheelRadius * wheelStyle.radius
	local tyreColor = Color3.fromRGB(wheelStyle.color[1], wheelStyle.color[2], wheelStyle.color[3])
	local rearZ = -math.huge
	for _, w in body.wheels do
		rearZ = math.max(rearZ, w[2])
	end
	for i, w in body.wheels do
		local rear = w[2] >= rearZ
		-- Rear wheels can be bigger (hot rods, dragsters); each sits on the road.
		local radius = (if rear then body.rearWheelRadius or body.wheelRadius else body.wheelRadius) * wheelStyle.radius
		local width = (if rear then body.rearWheelWidth or body.wheelWidth else body.wheelWidth) * wheelStyle.width
		local name = if rear then (if w[1] < 0 then "WheelRL" else "WheelRR") else `Wheel{i}`
		local d = radius * 2
		local wheelCf = drop * CFrame.new(w[1], radius - groundToBody, w[2])
		local wheel = Instance.new("Part")
		wheel.Name = name
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(width, d, d)
		wheel.CFrame = root.CFrame * wheelCf
		wheel.Color = tyreColor
		wheel.Material = Enum.Material.Rubber
		wheel.CanCollide = false
		wheel.CanQuery = false
		wheel.CanTouch = false
		wheel.Massless = true
		wheel.Parent = model
		-- Wheels turn on their own joint: front ones steer, all of them spin.
		local joint = motor("WheelJoint", root, wheel, wheelCf)
		joint:SetAttribute("Front", not rear)
		-- Bigger wheels turn slower for the same road speed.
		joint:SetAttribute("SpinScale", wheelRadius / radius)
		if body.realistic and not wheelStyle.glow then
			-- Polished rim with six spokes and a dark centre cap.
			visual(model, root, `{name}Hub`, Vector3.new(width + 0.04, d * 0.62, d * 0.62), wheelCf, Color3.fromRGB(200, 204, 212), Enum.Material.Metal, "Cylinder", wheel).Reflectance = 0.3
			for k = 0, 2 do
				visual(model, root, `{name}Spoke`, Vector3.new(width + 0.08, d * 0.56, d * 0.09), wheelCf * CFrame.Angles(math.rad(k * 60), 0, 0), Color3.fromRGB(150, 154, 162), Enum.Material.Metal, nil, wheel)
			end
			visual(model, root, `{name}Cap`, Vector3.new(width + 0.12, d * 0.16, d * 0.16), wheelCf, Color3.fromRGB(35, 35, 40), Enum.Material.Metal, "Cylinder", wheel)
		else
			visual(model, root, `{name}Hub`, Vector3.new(width + 0.06, d * 0.55, d * 0.55), wheelCf, accent, if wheelStyle.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic, "Cylinder", wheel)
			-- A spoke so you can see the wheel turning.
			visual(model, root, `{name}Spoke`, Vector3.new(width + 0.08, d * 0.5, d * 0.14), wheelCf, Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic, nil, wheel)
		end
		if rear then
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

	-- Stickers on both sides.
	local sticker = Cosmetics.find("sticker", (chosen :: any).sticker)
	if sticker and sticker.id ~= "none" then
		for _, side in { -1, 1 } do
			local panel = visual(model, root, "Sticker", Vector3.new(0.05, 1.8, 1.8), drop * CFrame.new(side * 2.45, 0.9, 0.2), Color3.new(1, 1, 1), nil, nil, bodyRoot)
			panel.Transparency = 1
			local gui = Instance.new("SurfaceGui")
			gui.Face = if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.LightInfluence = 0.5
			gui.Parent = panel
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Text = sticker.icon
			label.Parent = gui
		end
	end

	-- Licence plate on the back.
	local plateText = (chosen :: any).plate
	if type(plateText) == "string" and plateText ~= "" then
		local plate = visual(model, root, "Plate", Vector3.new(1.8, 0.6, 0.08), drop * CFrame.new(0, 0.2, 3.65), Color3.fromRGB(250, 250, 240), nil, nil, bodyRoot)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 60
		gui.Parent = plate
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(40, 40, 60)
		label.Text = plateText
		label.Parent = gui
	end

	-- Trail streaming from the back.
	local trailStyle = Cosmetics.find("trail", (chosen :: any).trail)
	if trailStyle and #trailStyle.colors > 0 then
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailTop"
		a0.Position = Vector3.new(0, 0.9, 3.4)
		a0.Parent = bodyRoot
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailBottom"
		a1.Position = Vector3.new(0, -0.3, 3.4)
		a1.Parent = bodyRoot
		local keys = {}
		for i, c in trailStyle.colors do
			local t = if #trailStyle.colors == 1 then 0 else (i - 1) / (#trailStyle.colors - 1)
			table.insert(keys, ColorSequenceKeypoint.new(t, Color3.fromRGB(c[1], c[2], c[3])))
		end
		if #keys == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, keys[1].Value))
		end
		local trail = Instance.new("Trail")
		trail.Name = "KartTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(keys)
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Lifetime = 0.45
		trail.MinLength = 0.2
		trail.LightEmission = if trailStyle.id == "smoke" then 0 else 0.6
		trail.FaceCamera = true
		trail.Parent = bodyRoot
	end

	-- Engine sound, if one was added (KartAssets.Sounds.Engine); clients
	-- raise its pitch with speed (KartVisuals).
	local engine = Assets.sound("Engine")
	if engine then
		engine.Name = "EngineSound"
		engine.Looped = true
		engine.Volume = math.min(engine.Volume, 0.45)
		engine.RollOffMaxDistance = 140
		engine.Playing = true
		engine.Parent = root
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
	weld(bodyRoot, seat)

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
	model:SetAttribute("WheelRadius", wheelRadius)
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
	-- Lets clients animate boost-only details (like the toaster's toast).
	if model:GetAttribute("Boosting") ~= boosting then
		model:SetAttribute("Boosting", boosting)
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
