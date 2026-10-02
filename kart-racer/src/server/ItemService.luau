-- Item boxes, rolling items, and everything items do on the track: oil
-- slicks, bouncers, homing rockets and the leader bolt. All hits are decided
-- here on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Items)
local KartPhysics = require(Shared.KartPhysics)
local Track = require(Shared.Track)

local ItemService = {}

local PICKUP_RADIUS = 7
local HIT_RADIUS = 5
local NITRO_TIME = 1.3
local OVERDRIVE_TIME = 6
local BOUNCER_SPEED = 150
local ROCKET_SPEED = 185
local BOLT_SPEED = 260
local BOLT_SPLASH = 16

type Box = { part: Part, pos: Vector3, respawnAt: number? }
type Hazard = {
	kind: string,
	part: Part,
	owner: any, -- Racer
	born: number,
	life: number,
	-- bouncers
	pos: Vector3?,
	dir: Vector3?,
	-- rockets / bolt: travel along the lap
	score: number?,
	lateral: number?,
	target: any?,
}

local boxes: { Box } = {}
local hazards: { Hazard } = {}
local folder: Folder? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function v3(p: Track.Vec): Vector3
	return Vector3.new(p.x, p.y, p.z)
end

local function newPart(name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	if shape then
		p.Shape = shape
	end
	p.Parent = folder
	return p
end

function ItemService.clear()
	if folder then
		folder:Destroy()
	end
	folder = nil
	boxes = {}
	hazards = {}
end

function ItemService.setup(track: Track.Built)
	ItemService.clear()
	local f = Instance.new("Folder")
	f.Name = "Items"
	f.Parent = Workspace
	folder = f
	for _, spot in Track.itemBoxes(track) do
		local pos = v3(Track.spot(track, spot.distance, spot.lateral)) + Vector3.new(0, 3, 0)
		local part = newPart("ItemBox", Vector3.new(4, 4, 4), Color3.fromRGB(120, 200, 255))
		part.Material = Enum.Material.Glass
		part.Transparency = 0.25
		part.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(45), math.rad(45), 0)
		part:SetAttribute("ItemBox", true)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.new(0, 40, 0, 40)
		gui.AlwaysOnTop = false
		gui.Parent = part
		local q = Instance.new("TextLabel")
		q.Size = UDim2.fromScale(1, 1)
		q.BackgroundTransparency = 1
		q.Font = Enum.Font.GothamBlack
		q.TextScaled = true
		q.TextColor3 = Color3.new(1, 1, 1)
		q.TextStrokeTransparency = 0
		q.Text = "?"
		q.Parent = gui
		table.insert(boxes, { part = part, pos = pos })
	end
end

local function rootOf(racer: any): BasePart?
	return racer.model and racer.model.PrimaryPart
end

local function yawOf(racer: any): number
	if racer.state then
		return racer.state.yaw
	end
	local root = rootOf(racer)
	if not root then
		return 0
	end
	local look = root.CFrame.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function forwardOf(racer: any): Vector3
	local fx, fz = KartPhysics.forward(yawOf(racer))
	return Vector3.new(fx, 0, fz)
end

local function giveItem(racer: any, field: number, effects: any)
	local id = Items.roll(racer.place, field, math.random())
	racer.item = id
	racer.uses = Items.Defs[id].uses
	racer.itemReadyAt = now() + Items.RouletteTime
	racer.cpuUseAt = racer.itemReadyAt + 0.5 + math.random() * 3
	effects.itemChanged(racer)
end

local function racerAtPlace(racers: { any }, place: number): any?
	for _, r in racers do
		if r.place == place then
			return r
		end
	end
	return nil
end

local function hitNear(racers: { any }, pos: Vector3, radius: number, except: any?, effects: any): boolean
	local any = false
	for _, r in racers do
		local root = rootOf(r)
		if r ~= except and root and (root.Position - pos).Magnitude <= radius then
			if effects.hit(r) then
				any = true
			end
		end
	end
	return any
end

function ItemService.use(track: Track.Built, racers: { any }, racer: any, effects: any)
	local id = racer.item
	local root = rootOf(racer)
	if not id or not root or now() < racer.itemReadyAt or racer.finishTime then
		return
	end
	racer.uses -= 1
	if racer.uses <= 0 then
		racer.item = nil
	end
	effects.itemChanged(racer)

	local forward = forwardOf(racer)
	if id == "nitro" or id == "tripleNitro" then
		effects.boost(racer, NITRO_TIME)
	elseif id == "overdrive" then
		effects.overdrive(racer, OVERDRIVE_TIME)
	elseif id == "oil" then
		local part = newPart("Oil", Vector3.new(0.3, 7, 7), Color3.fromRGB(25, 20, 35), Enum.PartType.Cylinder)
		part.Material = Enum.Material.Glass
		part.CFrame = CFrame.new(root.Position - forward * 7 - Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
		table.insert(hazards, { kind = "oil", part = part, owner = racer, born = now(), life = 45 })
	elseif id == "bouncer" then
		local pos = root.Position + forward * 6
		local part = newPart("Bouncer", Vector3.new(2.5, 2.5, 2.5), Color3.fromRGB(60, 230, 90), Enum.PartType.Ball)
		part.Position = pos
		table.insert(hazards, { kind = "bouncer", part = part, owner = racer, born = now(), life = 7, pos = pos, dir = forward })
	elseif id == "homing" or id == "leaderBolt" then
		local target = if id == "homing" then racerAtPlace(racers, racer.place - 1) else racerAtPlace(racers, 1)
		local part = if id == "homing"
			then newPart("Rocket", Vector3.new(1.4, 1.4, 4), Color3.fromRGB(255, 60, 60))
			else newPart("Bolt", Vector3.new(3, 3, 3), Color3.fromRGB(255, 240, 80), Enum.PartType.Ball)
		part.Position = root.Position + forward * 6
		table.insert(hazards, {
			kind = id,
			part = part,
			owner = racer,
			born = now(),
			life = 12,
			score = racer.score + 6,
			lateral = 0,
			target = target,
		})
	end
end

local function stepHazard(h: Hazard, track: Track.Built, racers: { any }, dt: number, effects: any): boolean
	local t = now()
	if t - h.born > h.life then
		return false
	end
	local ownerSafe = t - h.born < 0.5

	if h.kind == "oil" then
		for _, r in racers do
			local root = rootOf(r)
			if root and not (ownerSafe and r == h.owner) and (root.Position - h.part.Position).Magnitude <= HIT_RADIUS then
				effects.hit(r)
				return false
			end
		end
		return true
	elseif h.kind == "bouncer" then
		local pos = (h.pos :: Vector3) + (h.dir :: Vector3) * BOUNCER_SPEED * dt
		local proj = Track.project(track, Track.v(pos.X, pos.Y, pos.Z))
		local limit = track.def.width / 2 + Track.ShoulderWidth - 1
		if math.abs(proj.lateral) > limit then
			-- Bounce off the wall: reflect across the wall's direction.
			local _, tan = Track.at(track, proj.distance)
			local right = Vector3.new(-tan.z, 0, tan.x).Unit * math.sign(proj.lateral)
			local dir = h.dir :: Vector3
			h.dir = (dir - right * 2 * dir:Dot(right)).Unit
			pos = h.pos :: Vector3
		end
		local ground = Track.spot(track, proj.distance, proj.lateral)
		h.pos = Vector3.new(pos.X, ground.y + 1.5, pos.Z)
		h.part.Position = h.pos :: Vector3
		for _, r in racers do
			local root = rootOf(r)
			if root and not (ownerSafe and r == h.owner) and (root.Position - (h.pos :: Vector3)).Magnitude <= HIT_RADIUS then
				effects.hit(r)
				return false
			end
		end
		return true
	else
		-- Rocket or bolt: follow the track toward the target.
		local target = h.target
		if not target or not rootOf(target) or target.finishTime then
			if h.kind == "homing" then
				return false
			end
			target = racerAtPlace(racers, 1)
			h.target = target
			if not target then
				return false
			end
		end
		local speed = if h.kind == "homing" then ROCKET_SPEED else BOLT_SPEED
		h.score = (h.score :: number) + speed * dt
		local targetRoot = rootOf(target) :: BasePart
		local targetProj = Track.project(track, Track.v(targetRoot.Position.X, targetRoot.Position.Y, targetRoot.Position.Z), target.progress.index)
		h.lateral = (h.lateral :: number) + (targetProj.lateral - (h.lateral :: number)) * math.min(1, dt * 4)
		local spot = Track.spot(track, (h.score :: number) % track.length, h.lateral :: number)
		local height = if h.kind == "leaderBolt" then 20 else 2
		h.part.Position = v3(spot) + Vector3.new(0, height, 0)
		if (h.score :: number) >= target.score - 4 then
			if h.kind == "leaderBolt" then
				hitNear(racers, targetRoot.Position, BOLT_SPLASH, nil, effects)
			else
				effects.hit(target)
			end
			return false
		end
		return true
	end
end

function ItemService.tick(track: Track.Built, racers: { any }, dt: number, effects: any)
	local t = now()
	local field = #racers

	for _, box in boxes do
		if box.respawnAt then
			if t >= box.respawnAt then
				box.respawnAt = nil
				box.part.Transparency = 0.25
			end
			continue
		end
		for _, r in racers do
			local root = rootOf(r)
			if root and not r.item and (root.Position - box.pos).Magnitude <= PICKUP_RADIUS then
				giveItem(r, field, effects)
				box.respawnAt = t + Items.BoxRespawn
				box.part.Transparency = 1
				break
			end
		end
	end

	for i = #hazards, 1, -1 do
		local h = hazards[i]
		if not stepHazard(h, track, racers, dt, effects) then
			h.part:Destroy()
			table.remove(hazards, i)
		end
	end

	-- CPU drivers use their items after a short, random delay.
	for _, r in racers do
		if r.state and r.item and t >= r.cpuUseAt then
			if r.item == "oil" or r.place > 1 or (r.item ~= "homing" and r.item ~= "leaderBolt") then
				ItemService.use(track, racers, r, effects)
				r.cpuUseAt = t + 0.6
			end
		end
	end
end

return ItemService
