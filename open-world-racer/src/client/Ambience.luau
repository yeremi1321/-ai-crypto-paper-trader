-- Everything the player sees and hears around the car: engine notes that
-- follow RPM for every nearby car, tire squeal, rain, map markers for places
-- and events, and the next race checkpoint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EngineAudio = require(Shared:WaitForChild("EngineAudio"))
local WorldMap = require(Shared:WaitForChild("WorldMap"))

local Ambience = {}

-- Upload looping sounds and paste their ids here. Empty = silent.
local SOUNDS = {
	tireSqueal = "",
	rain = "",
}

local HEARING_RANGE = 300
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

---------------------------------------------------------------------------
-- Engine and tire sounds
---------------------------------------------------------------------------
type CarAudio = { engine: Sound?, squeal: Sound?, lastSpeed: number }
local carAudio: { [Model]: CarAudio } = {}

local function makeSound(id: string, parent: Instance): Sound?
	if id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.RollOffMaxDistance = HEARING_RANGE
	s.Volume = 0
	s.Parent = parent
	s:Play()
	return s
end

local function audioFor(car: Model): CarAudio?
	local existing = carAudio[car]
	if existing then
		return existing
	end
	local chassis = car.PrimaryPart
	local profile = EngineAudio.Profiles[car:GetAttribute("EngineSound") or "inline4"]
	if not chassis or not profile then
		return nil
	end
	local audio = {
		engine = makeSound(profile.soundId, chassis),
		squeal = makeSound(SOUNDS.tireSqueal, chassis),
		lastSpeed = 0,
	}
	carAudio[car] = audio
	return audio
end

local function stopAudio(car: Model)
	local audio = carAudio[car]
	if audio then
		if audio.engine then
			audio.engine:Destroy()
		end
		if audio.squeal then
			audio.squeal:Destroy()
		end
		carAudio[car] = nil
	end
end

-- Returns the local player's engine state for the speedometer.
function Ambience.updateCars(dt: number, myCar: Model?): EngineAudio.EngineState?
	local mine: EngineAudio.EngineState? = nil
	local carsFolder = Workspace:FindFirstChild("Cars")
	local camPos = camera.CFrame.Position

	for car, _ in carAudio do
		if not car.Parent or not car.PrimaryPart or (car.PrimaryPart.Position - camPos).Magnitude > HEARING_RANGE * 1.2 then
			stopAudio(car)
		end
	end
	if not carsFolder then
		return nil
	end

	for _, car in carsFolder:GetChildren() do
		local chassis = car:IsA("Model") and car.PrimaryPart
		if not chassis or ((chassis.Position - camPos).Magnitude > HEARING_RANGE and car ~= myCar) then
			continue
		end
		local audio = audioFor(car)
		local profile = EngineAudio.Profiles[car:GetAttribute("EngineSound") or "inline4"]
		if not audio or not profile then
			continue
		end
		local vel = chassis.AssemblyLinearVelocity
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local throttle
		if car == myCar then
			local seat = car:FindFirstChild("DriveSeat") :: VehicleSeat?
			throttle = if seat then seat.ThrottleFloat else 0
		else
			-- Other drivers: estimate throttle from how fast they are gaining speed.
			throttle = math.clamp((speed - audio.lastSpeed) / math.max(dt, 1e-3) / 30, 0, 1)
		end
		audio.lastSpeed = speed

		local state = EngineAudio.state(profile, speed, car:GetAttribute("TopSpeed") or 150, throttle, car:GetAttribute("HasTurbo"))
		if audio.engine then
			audio.engine.PlaybackSpeed = state.pitch
			audio.engine.Volume = state.volume * (if Workspace:GetAttribute("Raining") then 0.85 else 1)
		end
		if audio.squeal then
			local look = Vector3.new(chassis.CFrame.LookVector.X, 0, chassis.CFrame.LookVector.Z).Unit
			local slip = if speed > 25 then 1 - math.abs(look:Dot(vel.Unit)) else 0
			audio.squeal.Volume = math.clamp((slip - 0.08) * 4, 0, 0.8)
		end
		if car == myCar then
			mine = state
		end
	end
	return mine
end

---------------------------------------------------------------------------
-- Rain
---------------------------------------------------------------------------
local rainPart = Instance.new("Part")
rainPart.Name = "RainEmitter"
rainPart.Anchored = true
rainPart.CanCollide = false
rainPart.CanQuery = false
rainPart.Transparency = 1
rainPart.Size = Vector3.new(120, 1, 120)
local rain = Instance.new("ParticleEmitter")
rain.Texture = "rbxasset://textures/particles/sparkles_main.dds"
rain.Color = ColorSequence.new(Color3.fromRGB(180, 200, 230))
rain.Size = NumberSequence.new(0.12)
rain.Transparency = NumberSequence.new(0.35)
rain.Lifetime = NumberRange.new(1.2)
rain.Speed = NumberRange.new(80)
rain.EmissionDirection = Enum.NormalId.Bottom
rain.Rate = 0
rain.LightInfluence = 1
rain.Parent = rainPart
local rainSound = makeSound(SOUNDS.rain, rainPart)
rainPart.Parent = Workspace

function Ambience.updateWeather()
	local raining = Workspace:GetAttribute("Raining") == true
	rainPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
	rain.Rate = if raining then 900 else 0
	if rainSound then
		-- Rain sounds duller from inside the car.
		local inCar = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local seated = inCar and (inCar :: Humanoid).SeatPart ~= nil
		rainSound.Volume = if raining then (if seated then 0.25 else 0.6) else 0
	end
end

---------------------------------------------------------------------------
-- Map markers
---------------------------------------------------------------------------
local markerFolder = Instance.new("Folder")
markerFolder.Name = "Markers"
markerFolder.Parent = Workspace

local function marker(name: string, text: string, color: Color3, pos: Vector3, maxDistance: number?): BillboardGui
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = pos
	anchor.Parent = markerFolder

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 200, 0, 36)
	bb.AlwaysOnTop = true
	bb.MaxDistance = maxDistance or 2500
	bb.LightInfluence = 0
	bb.Parent = anchor
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.3
	l.Text = text
	l.Parent = bb
	return bb
end

local PLACE_COLORS = {
	garage = Color3.fromRGB(255, 170, 40),
	dealership = Color3.fromRGB(80, 170, 255),
	tuning = Color3.fromRGB(255, 70, 90),
	meet = Color3.fromRGB(170, 90, 255),
	photo = Color3.fromRGB(90, 230, 160),
}

local flashMarker: BillboardGui? = nil
local meetMarker: BillboardGui? = nil

local function buildStaticMarkers()
	for _, place in WorldMap.Places do
		marker(`Place_{place.id}`, place.name, PLACE_COLORS[place.kind] or Color3.new(1, 1, 1), Vector3.new(place.pos.x, 30, place.pos.z))
	end
	for _, ev in WorldMap.Events do
		marker(`Event_{ev.id}`, `{ev.name} ({ev.kind})`, Color3.fromRGB(255, 200, 40), Vector3.new(ev.start.x, 24, ev.start.z))
	end
	-- Discoveries only show up close, so they still feel like finds.
	for _, d in WorldMap.Discoveries do
		if d.kind == "speedTrap" or d.kind == "driftZone" then
			marker(`Disc_{d.id}`, d.name, Color3.fromRGB(80, 190, 255), Vector3.new(d.pos.x, 16, d.pos.z), 260)
		end
	end
end

local function moveMarker(existing: BillboardGui?, name: string, text: string, color: Color3, pos: any): BillboardGui?
	if not pos then
		if existing then
			(existing.Parent :: Instance):Destroy()
		end
		return nil
	end
	if existing then
		(existing.Parent :: BasePart).Position = Vector3.new(pos.x, 40, pos.z);
		(existing:FindFirstChildOfClass("TextLabel") :: TextLabel).Text = text
		return existing
	end
	return marker(name, text, color, Vector3.new(pos.x, 40, pos.z), 5000)
end

function Ambience.setWorld(state: any)
	flashMarker = moveMarker(flashMarker, "Flash", state.flash and `FLASH: {state.flash.event}` or "", Color3.fromRGB(255, 120, 40), state.flash and state.flash.pos)
	meetMarker = moveMarker(meetMarker, "Meet", "MIDNIGHT MEET", Color3.fromRGB(180, 110, 255), state.meet and state.meet.pos)
end

---------------------------------------------------------------------------
-- Race checkpoint
---------------------------------------------------------------------------
local function pillar(color: Color3, transparency: number): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(60, 18, 18)
	p.Parent = nil
	return p
end
local nextPillar = pillar(Color3.fromRGB(255, 200, 40), 0.35)
local afterPillar = pillar(Color3.fromRGB(255, 255, 255), 0.75)

function Ambience.setCheckpoint(nextPt: any, afterPt: any, isFinish: boolean)
	local up = CFrame.Angles(0, 0, math.rad(90))
	if nextPt then
		nextPillar.Color = if isFinish then Color3.fromRGB(80, 230, 120) else Color3.fromRGB(255, 200, 40)
		nextPillar.CFrame = CFrame.new(nextPt.x, 30, nextPt.z) * up
		nextPillar.Parent = Workspace
	else
		nextPillar.Parent = nil
	end
	if afterPt then
		afterPillar.CFrame = CFrame.new(afterPt.x, 30, afterPt.z) * up
		afterPillar.Parent = Workspace
	else
		afterPillar.Parent = nil
	end
end

function Ambience.start()
	buildStaticMarkers()
end

return Ambience
