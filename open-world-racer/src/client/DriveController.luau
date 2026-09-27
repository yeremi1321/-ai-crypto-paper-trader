-- Drives the local player's car. The server gives the driver network
-- ownership, so motor and servo changes made here are what move the car.
--
-- Controls: W/S or triggers throttle and brake, A/D steer, Left Shift (or
-- gamepad B) handbrake, R resets a stuck car (or pulls a fresh one out at the
-- garage). Space (jump) gets out of the car, as usual on Roblox.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local DriveController = {}

-- Hinge motors spin wheels around the car's lateral (+X) axis; with the car
-- facing -Z, rolling forward is a negative angular velocity.
local FORWARD_SIGN = -1
local BRAKE_DECEL = 70 -- studs/s^2
local ENGINE_BRAKE_DECEL = 6
local REVERSE_FRACTION = 0.3

local player = Players.LocalPlayer
local handbrake = false

type Wheel = { axle: HingeConstraint, driven: boolean, rear: boolean, steer: HingeConstraint? }
local cachedCar: Model? = nil
local wheels: { Wheel } = {}

function DriveController.currentCar(): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and seat:IsA("VehicleSeat") and seat.Name == "DriveSeat" and seat.Parent then
		return seat.Parent :: Model
	end
	return nil
end

local function collectWheels(car: Model)
	wheels = {}
	for _, name in { "FL", "FR", "RL", "RR" } do
		local wheel = car:FindFirstChild(name)
		local axle = wheel and wheel:FindFirstChild("Axle") :: HingeConstraint?
		if axle then
			local knuckle = car:FindFirstChild(`{name}Knuckle`)
			table.insert(wheels, {
				axle = axle,
				driven = axle:GetAttribute("Driven") == true,
				rear = axle:GetAttribute("Rear") == true,
				steer = knuckle and knuckle:FindFirstChild("Steer") :: HingeConstraint?,
			})
		end
	end
	cachedCar = car
end

local function drive(car: Model, seat: VehicleSeat)
	if cachedCar ~= car then
		collectWheels(car)
	end
	local chassis = car.PrimaryPart
	if not chassis or chassis.Anchored then
		return
	end

	local topSpeed = car:GetAttribute("TopSpeed") or 150
	local ptw = car:GetAttribute("PowerToWeight") or 0.1
	local handling = car:GetAttribute("Handling") or 0.6
	local radius = car:GetAttribute("WheelRadius") or 1.4

	local throttle = seat.ThrottleFloat
	local steer = seat.SteerFloat
	local forwardSpeed = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
	local mass = chassis.AssemblyMass

	local drivenCount = 0
	for _, w in wheels do
		if w.driven then
			drivenCount += 1
		end
	end
	drivenCount = math.max(drivenCount, 1)

	local accel = 20 + 80 * math.clamp(ptw / 0.45, 0, 1.4)
	local driveTorque = mass * accel * radius / drivenCount
	local brakeTorque = mass * BRAKE_DECEL * radius / #wheels
	local coastTorque = mass * ENGINE_BRAKE_DECEL * radius / #wheels

	local braking = throttle ~= 0 and math.abs(forwardSpeed) > 3 and math.sign(throttle) ~= math.sign(forwardSpeed)
	local targetSpeed = if throttle >= 0 then topSpeed * throttle else topSpeed * REVERSE_FRACTION * throttle

	for _, w in wheels do
		if handbrake and w.rear then
			w.axle.AngularVelocity = 0
			w.axle.MotorMaxTorque = brakeTorque * 2
		elseif braking then
			w.axle.AngularVelocity = 0
			w.axle.MotorMaxTorque = brakeTorque
		elseif throttle ~= 0 and w.driven then
			w.axle.AngularVelocity = FORWARD_SIGN * targetSpeed / radius
			w.axle.MotorMaxTorque = driveTorque
		else
			-- Coasting: let the wheel roll, with a little engine braking.
			w.axle.AngularVelocity = FORWARD_SIGN * forwardSpeed / radius * 0.98
			w.axle.MotorMaxTorque = coastTorque
		end

		if w.steer then
			-- Less lock at speed keeps the car stable on the highway.
			local maxAngle = 28 + 12 * handling
			local angle = maxAngle / (1 + math.abs(forwardSpeed) / 70)
			w.steer.TargetAngle = -steer * angle
		end
	end
end

function DriveController.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonB then
			handbrake = true
		elseif input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonY then
			Remotes.RespawnCar:FireServer()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonB then
			handbrake = false
		end
	end)

	RunService.Heartbeat:Connect(function()
		local car = DriveController.currentCar()
		if car then
			drive(car, car:FindFirstChild("DriveSeat") :: VehicleSeat)
		else
			cachedCar = nil
		end
	end)
end

function DriveController.setHandbrake(on: boolean)
	handbrake = on
end

return DriveController
