-- Item boxes, rolling items and everything the six items do on the track.
-- All hits are decided here on the server, and every attack is readable:
--   Wind-up Rocket  rolls along the road, pops on the first kart it meets
--                   (racers ahead get a warning)
--   Popcorn Bomb    lobbed ahead (or dropped behind), blinks, then pops
--   Jelly Puddle    a sticky trap that slows whoever drives in
--   Bubble Shield   blocks one attack
--   Turbo Soda      a speed boost
--   Spring Mine     a trap that boings karts into the air
-- Traps expire, each racer has a trap limit, and the track has a cap on
-- active hazards so things never pile up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Items)
local KartPhysics = require(Shared.KartPhysics)
local Track = require(Shared.Track)
local Shapes = require(ReplicatedStorage.Common.Shapes)

local ItemService = {}

local PICKUP_RADIUS = 7
local HIT_RADIUS = 5
local WARN_RANGE = 110

-- Optional sound ids (rbxassetid://...). Empty = silent. See README "Assets to replace".
ItemService.Sounds = { pop = "", boing = "", splat = "", fizz = "", whoosh = "" }

type Hazard = {
	kind: string,
	model: Model,
	owner: any, -- Racer
	born: number,
	life: number,
	pos: Vector3,
	-- rocket: travels along the lap
	score: number?,
	direction: number?,
	lateral: number?,
	-- bomb: lands, then pops after a fuse
	from: Vector3?,
	landAt: number?,
	popAt: number?,
	hitsLeft: number?,
}

type Box = { part: BasePart, pos: Vector3, respawnAt: number? }

local boxes: { Box } = {}
local hazards: { Hazard } = {}
local folder: Folder? = nil

-- The clock is swappable so the smoke test can run items outside Roblox.
ItemService.clock = function(): number
	return Workspace:GetServerTimeNow()
end

local function now(): number
	return ItemService.clock()
end

local function cleanupLater(inst: Instance, seconds: number)
	task.delay(seconds, function()
		if inst.Parent then
			inst:Destroy()
		end
	end)
end

local function v3(p: Track.Vec): Vector3
	return Vector3.new(p.x, p.y, p.z)
end

local function rootOf(racer: any): BasePart?
	return racer.model and racer.model.PrimaryPart
end

local function forwardOf(racer: any): Vector3
	local yaw
	if racer.state then
		yaw = racer.state.yaw
	else
		local root = rootOf(racer)
		local look = if root then root.CFrame.LookVector else Vector3.new(0, 0, -1)
		yaw = math.atan2(-look.X, -look.Z)
	end
	local fx, fz = KartPhysics.forward(yaw)
	return Vector3.new(fx, 0, fz)
end

local function sound(parent: Instance, key: string)
	local id = ItemService.Sounds[key]
	if id and id ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = 0.8
		s.Parent = parent
		s:Play()
		cleanupLater(s, 3)
	end
end

-- A cartoon pop: a flash ball, sparks, a puff of smoke and a "POP!" word.
function ItemService.explode(pos: Vector3, word: string?, color: Color3?)
	local f = folder
	if not f then
		return
	end
	local flash = Shapes.ball(f, 6, CFrame.new(pos), { color = color or Color3.fromRGB(255, 220, 90), material = Enum.Material.Neon, transparency = 0.2 })
	flash.Name = "Pop"
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 120, 60))
	sparks.Size = NumberSequence.new(1.2, 0)
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Speed = NumberRange.new(25, 45)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 400
	sparks.LightEmission = 1
	sparks.Parent = flash
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	smoke.Size = NumberSequence.new(3, 7)
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Lifetime = NumberRange.new(0.6, 0.9)
	smoke.Speed = NumberRange.new(4, 9)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 60
	smoke.Parent = flash
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.new(0, 120, 0, 50)
	tag.StudsOffset = Vector3.new(0, 6, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 220
	tag.Parent = flash
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 230, 80)
	label.TextStrokeTransparency = 0
	label.Text = word or "POP!"
	label.Parent = tag
	sound(flash, "pop")
	task.delay(0.25, function()
		sparks.Enabled = false
		smoke.Enabled = false
		flash.Transparency = 1
	end)
	cleanupLater(flash, 1.4)
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
		local pos = v3(Track.spot(track, spot.distance, spot.lateral)) + Vector3.new(0, 3.5, 0)
		local part = Shapes.box(f, Vector3.new(4.5, 4.5, 4.5), CFrame.new(pos) * CFrame.Angles(math.rad(45), math.rad(45), 0), {
			color = Color3.fromRGB(150, 210, 255),
			material = Enum.Material.Glass,
			transparency = 0.2,
			name = "ItemBox",
		})
		part:SetAttribute("ItemBox", true)
		local core = Shapes.ball(f, 2.4, CFrame.new(pos), { color = Color3.fromRGB(255, 230, 120), material = Enum.Material.Neon, name = "ItemCore" })
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.new(0, 44, 0, 44)
		gui.MaxDistance = 260
		gui.Parent = part
		local q = Instance.new("TextLabel")
		q.Size = UDim2.fromScale(1, 1)
		q.BackgroundTransparency = 1
		q.Font = Enum.Font.FredokaOne
		q.TextScaled = true
		q.TextColor3 = Color3.new(1, 1, 1)
		q.TextStrokeTransparency = 0
		q.Text = "?"
		q.Parent = gui
		part:SetAttribute("CoreName", core.Name)
		table.insert(boxes, { part = part, pos = pos, core = core } :: any)
	end
end

local function racerAtPlace(racers: { any }, place: number): any?
	for _, r in racers do
		if r.place == place then
			return r
		end
	end
	return nil
end

local function giveItem(racer: any, field: number, effects: any)
	local id = Items.roll(racer.place, field, math.random())
	racer.item = id
	racer.uses = Items.Defs[id].uses
	racer.itemReadyAt = now() + Items.RouletteTime
	racer.cpuUseAt = racer.itemReadyAt + 0.5 + math.random() * 3
	effects.itemChanged(racer)
end

-- Removes the oldest hazards when there are too many (per racer and overall).
local function makeRoom(owner: any, isTrap: boolean)
	if isTrap then
		local mine = {}
		for i, h in hazards do
			if h.owner == owner and (h.kind == "jellyPuddle" or h.kind == "springMine") then
				table.insert(mine, i)
			end
		end
		if #mine >= Items.MaxTrapsPerRacer then
			local h = table.remove(hazards, mine[1]) :: Hazard
			h.model:Destroy()
		end
	end
	while #hazards >= Items.MaxActiveHazards do
		local h = table.remove(hazards, 1) :: Hazard
		h.model:Destroy()
	end
end

local function newModel(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = folder
	return m
end

local function place(model: Model, cf: CFrame)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local offset = d:GetAttribute("Offset") :: CFrame?
			d.CFrame = cf * (offset or CFrame.new())
		end
	end
end

-- Builds a hazard model whose parts keep their offset from the hazard's centre.
local function part(model: Model, kind: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, transparency: number?): BasePart
	local p: BasePart
	if kind == "ball" then
		p = Shapes.ball(model, size.X, offset, { color = color, material = material, transparency = transparency })
	elseif kind == "ellipsoid" then
		p = Shapes.ellipsoid(model, size, offset, { color = color, material = material, transparency = transparency })
	elseif kind == "disc" then
		p = Shapes.disc(model, size.X, size.Y, offset, { color = color, material = material, transparency = transparency })
	else
		p = Shapes.box(model, size, offset, { color = color, material = material, transparency = transparency })
	end
	p:SetAttribute("Offset", p.CFrame)
	return p
end

-- Tells racers a rocket is coming up behind them (at most every 1.5s).
local function warnAhead(racers: { any }, h: Hazard, effects: any)
	for _, r in racers do
		if r ~= h.owner then
			local gap = (r.score - (h.score :: number)) * (h.direction :: number)
			if gap > 0 and gap < WARN_RANGE and now() - (r.lastRocketWarn or 0) > 1.5 then
				r.lastRocketWarn = now()
				effects.warn(r, "🚀 Rocket incoming!")
			end
		end
	end
end

function ItemService.use(track: Track.Built, racers: { any }, racer: any, effects: any, aimBack: boolean?)
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
	local ground = root.CFrame.Position - Vector3.new(0, 2, 0)

	if id == "turboSoda" then
		effects.boost(racer, Items.SodaBoost)
		sound(root, "fizz")
	elseif id == "bubbleShield" then
		effects.shield(racer, Items.ShieldTime)
	elseif id == "windupRocket" then
		makeRoom(racer, false)
		local m = newModel("Rocket")
		part(m, "ellipsoid", Vector3.new(2.6, 2.6, 6), CFrame.new(), Color3.fromRGB(240, 70, 70))
		part(m, "ellipsoid", Vector3.new(2, 2, 2.4), CFrame.new(0, 0, -2.8), Color3.fromRGB(255, 255, 255))
		part(m, "box", Vector3.new(4, 0.3, 1.4), CFrame.new(0, 0, 2.2), Color3.fromRGB(255, 210, 60))
		part(m, "disc", Vector3.new(1.4, 0.6, 1.4), CFrame.new(0, 1.6, 1) , Color3.fromRGB(255, 210, 60))
		local flame = part(m, "ball", Vector3.new(1.6, 1.6, 1.6), CFrame.new(0, 0, 3.4), Color3.fromRGB(255, 160, 40), Enum.Material.Neon)
		flame.Name = "Flame"
		place(m, CFrame.lookAt(root.CFrame.Position, root.CFrame.Position + forward))
		local proj = Track.project(track, Track.v(root.CFrame.Position.X, root.CFrame.Position.Y, root.CFrame.Position.Z), racer.progress.index)
		local direction = if aimBack then -1 else 1
		local h: Hazard = {
			kind = id,
			model = m,
			owner = racer,
			born = now(),
			life = Items.RocketLife,
			pos = root.CFrame.Position,
			score = racer.score + 7 * direction,
			direction = direction,
			lateral = proj.lateral,
		}
		table.insert(hazards, h)
		sound(flame, "whoosh")
	elseif id == "popcornBomb" then
		makeRoom(racer, false)
		local m = newModel("PopcornBomb")
		part(m, "ball", Vector3.new(4, 4, 4), CFrame.new(), Color3.fromRGB(255, 80, 80))
		part(m, "ball", Vector3.new(4.1, 4.1, 4.1), CFrame.new(0, 0.3, 0), Color3.fromRGB(255, 255, 255), nil, 0.6)
		for i = 1, 6 do
			local a = i * 1.05
			part(m, "ball", Vector3.new(1.4, 1.4, 1.4), CFrame.new(math.cos(a) * 1.2, 2.2, math.sin(a) * 1.2), Color3.fromRGB(255, 245, 210))
		end
		local fuse = part(m, "ball", Vector3.new(1, 1, 1), CFrame.new(0, 3.2, 0), Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
		fuse.Name = "Fuse"
		place(m, CFrame.new(root.CFrame.Position + Vector3.new(0, 2, 0)))
		local target = if aimBack then ground - forward * 8 else ground + forward * Items.BombThrow + Vector3.new(0, 0, 0)
		local h: Hazard = {
			kind = id,
			model = m,
			owner = racer,
			born = now(),
			life = 6,
			pos = target,
			from = root.CFrame.Position + Vector3.new(0, 2, 0),
			landAt = now() + (if aimBack then 0.15 else 0.55),
			popAt = now() + (if aimBack then 0.15 else 0.55) + Items.BombFuse,
		}
		table.insert(hazards, h)
	elseif id == "jellyPuddle" or id == "springMine" then
		makeRoom(racer, true)
		local spot = ground - forward * 8
		local m: Model
		if id == "jellyPuddle" then
			m = newModel("JellyPuddle")
			part(m, "ellipsoid", Vector3.new(10, 1.6, 10), CFrame.new(0, 0.6, 0), Color3.fromRGB(255, 120, 190), Enum.Material.Glass, 0.25)
			part(m, "ellipsoid", Vector3.new(5, 2.2, 5), CFrame.new(1.2, 1.2, -0.8), Color3.fromRGB(255, 160, 210), Enum.Material.Glass, 0.2)
		else
			m = newModel("SpringMine")
			part(m, "disc", Vector3.new(6, 0.8, 6), CFrame.new(0, 0.4, 0), Color3.fromRGB(60, 60, 70))
			for k = 0, 3 do
				part(m, "disc", Vector3.new(4.2, 0.5, 4.2), CFrame.new(0, 1 + k * 0.7, 0), if k % 2 == 0 then Color3.fromRGB(255, 210, 60) else Color3.fromRGB(240, 70, 70))
			end
			part(m, "disc", Vector3.new(5, 0.6, 5), CFrame.new(0, 3.9, 0), Color3.fromRGB(240, 70, 70), Enum.Material.Neon)
		end
		place(m, CFrame.new(spot))
		table.insert(hazards, {
			kind = id,
			model = m,
			owner = racer,
			born = now(),
			life = if id == "jellyPuddle" then Items.JellyLife else Items.MineLife,
			pos = spot,
			hitsLeft = if id == "jellyPuddle" then Items.JellyHits else 1,
		})
		sound(m:FindFirstChildWhichIsA("BasePart") :: BasePart, if id == "jellyPuddle" then "splat" else "boing")
	end
end

local function touching(racer: any, pos: Vector3, radius: number): boolean
	local root = rootOf(racer)
	return root ~= nil and (root.CFrame.Position - pos).Magnitude <= radius
end

-- Returns false when the hazard is finished and should be removed.
local function stepHazard(h: Hazard, track: Track.Built, racers: { any }, dt: number, effects: any): boolean
	local t = now()
	if t - h.born > h.life then
		return false
	end
	local ownerSafe = t - h.born < 0.6

	if h.kind == "windupRocket" then
		h.score = (h.score :: number) + Items.RocketSpeed * dt * (h.direction :: number)
		local d = (h.score :: number) % track.length
		local spot = Track.spot(track, d, h.lateral :: number)
		local _, tan = Track.at(track, d)
		h.pos = v3(spot) + Vector3.new(0, 2, 0)
		local dir = Vector3.new(tan.x, 0, tan.z) * (h.direction :: number)
		local wobble = CFrame.Angles(0, 0, math.sin(t * 20) * 0.2)
		place(h.model, CFrame.lookAt(h.pos, h.pos + dir) * wobble)
		warnAhead(racers, h, effects)
		for _, r in racers do
			if not (ownerSafe and r == h.owner) and touching(r, h.pos, HIT_RADIUS) then
				effects.hit(r, "spin")
				ItemService.explode(h.pos, "POP!")
				return false
			end
		end
		return true
	elseif h.kind == "popcornBomb" then
		local landAt, popAt = h.landAt :: number, h.popAt :: number
		if t < landAt then
			-- Lobbed in an arc.
			local u = 1 - (landAt - t) / math.max(landAt - h.born, 0.01)
			local from = h.from :: Vector3
			local p = from:Lerp(h.pos, u) + Vector3.new(0, math.sin(u * math.pi) * 12, 0)
			place(h.model, CFrame.new(p + Vector3.new(0, 2, 0)))
			return true
		end
		place(h.model, CFrame.new(h.pos + Vector3.new(0, 2, 0)))
		-- Blink faster as the fuse runs down.
		local fuse = h.model:FindFirstChild("Fuse") :: BasePart?
		if fuse then
			local left = popAt - t
			local rate = if left < 0.6 then 14 else 5
			fuse.Transparency = if math.floor(t * rate) % 2 == 0 then 0 else 0.8
		end
		if t >= popAt then
			ItemService.explode(h.pos + Vector3.new(0, 2, 0), "POP!", Color3.fromRGB(255, 240, 200))
			for _, r in racers do
				if touching(r, h.pos + Vector3.new(0, 2, 0), Items.BombRadius) then
					effects.hit(r, "spin")
				end
			end
			return false
		end
		-- Warn anyone driving into the blast zone.
		for _, r in racers do
			if touching(r, h.pos, Items.BombRadius + 25) and t - (r.lastBombWarn or 0) > 1.2 then
				r.lastBombWarn = t
				effects.warn(r, "🍿 Bomb ahead!")
			end
		end
		return true
	elseif h.kind == "jellyPuddle" or h.kind == "springMine" then
		-- Jelly wobbles; mines bounce a little so they're easy to spot.
		local bob = if h.kind == "springMine" then math.abs(math.sin(t * 4)) * 0.6 else 0
		local squish = if h.kind == "jellyPuddle" then CFrame.Angles(0, t * 0.5, 0) else CFrame.new()
		place(h.model, CFrame.new(h.pos + Vector3.new(0, bob, 0)) * squish)
		for _, r in racers do
			if not (ownerSafe and r == h.owner) and touching(r, h.pos + Vector3.new(0, 2, 0), HIT_RADIUS + 1) then
				local kind = if h.kind == "jellyPuddle" then "slow" else "launch"
				if effects.hit(r, kind) then
					ItemService.explode(h.pos + Vector3.new(0, 2, 0), if kind == "slow" then "SPLAT!" else "BOING!", if kind == "slow" then Color3.fromRGB(255, 140, 200) else Color3.fromRGB(255, 220, 90))
					h.hitsLeft = (h.hitsLeft :: number) - 1
					if (h.hitsLeft :: number) <= 0 then
						return false
					end
				end
			end
		end
		return true
	end
	return false
end

function ItemService.tick(track: Track.Built, racers: { any }, dt: number, effects: any)
	local t = now()
	local field = #racers

	for _, box in boxes do
		local core = (box :: any).core :: BasePart
		if box.respawnAt then
			if t >= box.respawnAt then
				box.respawnAt = nil
				box.part.Transparency = 0.2
				core.Transparency = 0
			end
			continue
		end
		for _, r in racers do
			local root = rootOf(r)
			if root and not r.item and not r.finishTime and (root.CFrame.Position - box.pos).Magnitude <= PICKUP_RADIUS then
				giveItem(r, field, effects)
				box.respawnAt = t + Items.BoxRespawn
				box.part.Transparency = 1
				core.Transparency = 1
				break
			end
		end
	end

	for i = #hazards, 1, -1 do
		local h = hazards[i]
		local ok, keep = pcall(stepHazard, h, track, racers, dt, effects)
		if not ok or not keep then
			if not ok then
				warn("[ItemService] hazard failed:", keep)
			end
			h.model:Destroy()
			table.remove(hazards, i)
		end
	end

	-- CPU drivers use their items after a short, random delay. Traps and
	-- shields are used straight away; attacks wait for someone nearby.
	for _, r in racers do
		if r.state and r.item and t >= r.cpuUseAt then
			local id = r.item
			local ahead = racerAtPlace(racers, r.place - 1)
			local attackReady = id ~= "windupRocket" or (ahead ~= nil and ahead.score - r.score < 160)
			if attackReady then
				ItemService.use(track, racers, r, effects, false)
			end
			r.cpuUseAt = t + 0.8
		end
	end
end

return ItemService
