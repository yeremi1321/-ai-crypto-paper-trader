-- Builds a drivable car from an owned-car record: a chassis, a painted body,
-- a VehicleSeat, motor-driven wheels and servo steering. Tuning values are
-- written as attributes; the driver's client (DriveController) reads them and
-- drives the constraints, since the driver owns the car's physics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CarCatalog = require(Shared.CarCatalog)
local Performance = require(Shared.Performance)
local PlayerProfile = require(Shared.PlayerProfile)

local VehicleFactory = {}

local WHEEL_RADIUS = 1.4
local WHEEL_WIDTH = 1.2
local TRACK_HALF = 3.9 -- wheel center distance from the car's centerline
local AXLE_Z = 4.4 -- wheel center distance from the car's middle (front is -Z)

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function attach(part: BasePart, name: string, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = part
	return a
end

local function newPart(model: Model, name: string, size: Vector3, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function buildWheel(model: Model, chassis: BasePart, name: string, offset: Vector3, steer: boolean, driven: boolean, grip: number)
	local origin = chassis.CFrame
	local wheel = newPart(model, name, Vector3.new(WHEEL_WIDTH, WHEEL_RADIUS * 2, WHEEL_RADIUS * 2), origin * CFrame.new(offset))
	wheel.Shape = Enum.PartType.Cylinder
	wheel.Color = Color3.fromRGB(28, 28, 30)
	wheel.CustomPhysicalProperties = PhysicalProperties.new(0.9, math.clamp(grip * 1.6, 0.4, 2), 0, 100, 1)

	local noCollide = Instance.new("NoCollisionConstraint")
	noCollide.Part0 = wheel
	noCollide.Part1 = chassis
	noCollide.Parent = wheel

	-- Wheels spin around their local X axis (the car's lateral axis).
	local hub: BasePart = chassis
	local hubOffset = CFrame.new(offset)

	if steer then
		-- Knuckle turns around the vertical axis; the wheel spins on the knuckle.
		local knuckle = newPart(model, `{name}Knuckle`, Vector3.new(0.4, 0.4, 0.4), origin * CFrame.new(offset))
		knuckle.Transparency = 1
		knuckle.CanCollide = false
		local up = CFrame.Angles(0, 0, math.rad(90)) -- attachment X axis -> world up
		local steerHinge = Instance.new("HingeConstraint")
		steerHinge.Name = "Steer"
		steerHinge.Attachment0 = attach(chassis, `{name}SteerA`, CFrame.new(offset) * up)
		steerHinge.Attachment1 = attach(knuckle, "SteerB", up)
		steerHinge.ActuatorType = Enum.ActuatorType.Servo
		steerHinge.ServoMaxTorque = 1e6
		steerHinge.AngularSpeed = 6
		steerHinge.LimitsEnabled = true
		steerHinge.LowerAngle = -45
		steerHinge.UpperAngle = 45
		steerHinge.Parent = knuckle
		hub = knuckle
		hubOffset = CFrame.new()
	end

	local axle = Instance.new("HingeConstraint")
	axle.Name = "Axle"
	axle.Attachment0 = attach(hub, `{name}AxleA`, hubOffset)
	axle.Attachment1 = attach(wheel, "AxleB", CFrame.new())
	-- Every wheel gets a motor so all four can brake; only driven wheels get drive torque.
	axle.ActuatorType = Enum.ActuatorType.Motor
	axle.MotorMaxTorque = 0
	axle.AngularVelocity = 0
	axle.Parent = wheel
	axle:SetAttribute("Driven", driven)
	axle:SetAttribute("Rear", offset.Z > 0)
	return wheel
end

-- Builds and parents the car. `cf` is where the car's center should sit on the road.
function VehicleFactory.build(owned: PlayerProfile.OwnedCar, ownerUserId: number, cf: CFrame, parent: Instance): Model
	local def = CarCatalog.getCar(owned.carId) or CarCatalog.getCar(CarCatalog.StarterCarId)
	local stats = CarCatalog.applyParts(def.stats, owned.parts)
	local rating = Performance.rating(stats)
	local paint = Color3.fromRGB(owned.paint[1], owned.paint[2], owned.paint[3])

	local model = Instance.new("Model")
	model.Name = `{def.name} ({ownerUserId})`

	-- Chassis rides above wheel center so the body never scrapes.
	local origin = cf + Vector3.new(0, WHEEL_RADIUS + 0.4, 0)
	local chassis = newPart(model, "Chassis", Vector3.new(TRACK_HALF * 2 - WHEEL_WIDTH - 0.4, 0.8, 12), origin)
	chassis.Transparency = 1
	chassis.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.3, 0, 1, 1)
	model.PrimaryPart = chassis

	local body = newPart(model, "Body", Vector3.new(7.2, 2.2, 12.6), origin * CFrame.new(0, 1.3, 0))
	body.Color = paint
	body.Material = Enum.Material.SmoothPlastic
	body.Massless = true
	body.CanCollide = false -- the chassis is the collision hull; the body overlaps the wheels
	weld(chassis, body)

	local cabin = newPart(model, "Cabin", Vector3.new(6, 1.8, 5.5), origin * CFrame.new(0, 3.2, 0.8))
	cabin.Color = Color3.fromRGB(20, 24, 30)
	cabin.Material = Enum.Material.Glass
	cabin.Transparency = 0.3
	cabin.Massless = true
	cabin.CanCollide = false
	weld(chassis, cabin)

	for _, side in { -1, 1 } do
		local head = newPart(model, "Headlight", Vector3.new(1.4, 0.5, 0.2), origin * CFrame.new(side * 2.6, 1.4, -6.35))
		head.Material = Enum.Material.Neon
		head.Color = Color3.fromRGB(255, 250, 225)
		head.Massless = true
		head.CanCollide = false
		weld(chassis, head)
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Range = 60
		beam.Angle = 50
		beam.Brightness = 3
		beam.Parent = head

		local tail = newPart(model, "Taillight", Vector3.new(1.6, 0.4, 0.2), origin * CFrame.new(side * 2.6, 1.6, 6.35))
		tail.Material = Enum.Material.Neon
		tail.Color = Color3.fromRGB(220, 30, 40)
		tail.Massless = true
		tail.CanCollide = false
		weld(chassis, tail)
	end

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = origin * CFrame.new(-1.2, 1.9, 1)
	seat.Transparency = 1
	seat.MaxSpeed = 0 -- the drive controller handles propulsion
	seat.Torque = 0
	seat.HeadsUpDisplay = false
	seat.Massless = true
	seat.CanCollide = false
	seat.Parent = model
	weld(chassis, seat)

	local drivePrompt = Instance.new("ProximityPrompt")
	drivePrompt.Name = "DrivePrompt"
	drivePrompt.ActionText = "Drive"
	drivePrompt.ObjectText = def.name
	drivePrompt.KeyboardKeyCode = Enum.KeyCode.F
	drivePrompt.MaxActivationDistance = 14
	drivePrompt.RequiresLineOfSight = false
	drivePrompt.Parent = seat

	local frontDriven = stats.drivetrain ~= "RWD"
	local rearDriven = stats.drivetrain ~= "FWD"
	local wheelY = -0.4
	buildWheel(model, chassis, "FL", Vector3.new(-TRACK_HALF, wheelY, -AXLE_Z), true, frontDriven, stats.grip)
	buildWheel(model, chassis, "FR", Vector3.new(TRACK_HALF, wheelY, -AXLE_Z), true, frontDriven, stats.grip)
	buildWheel(model, chassis, "RL", Vector3.new(-TRACK_HALF, wheelY, AXLE_Z), false, rearDriven, stats.grip)
	buildWheel(model, chassis, "RR", Vector3.new(TRACK_HALF, wheelY, AXLE_Z), false, rearDriven, stats.grip)

	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("CarId", def.id)
	model:SetAttribute("CarName", def.name)
	model:SetAttribute("EngineSound", def.engineSound)
	model:SetAttribute("HasTurbo", table.find(owned.parts, "turbo") ~= nil)
	model:SetAttribute("TopSpeed", stats.topSpeed)
	model:SetAttribute("PowerToWeight", stats.power / stats.weight)
	model:SetAttribute("Handling", stats.handling)
	model:SetAttribute("Drivetrain", stats.drivetrain)
	model:SetAttribute("WheelRadius", WHEEL_RADIUS)
	model:SetAttribute("Rating", rating)
	model:SetAttribute("Class", Performance.classOf(rating))

	model.Parent = parent
	return model
end

return VehicleFactory
