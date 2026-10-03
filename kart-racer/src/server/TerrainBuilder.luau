-- Turns a Landscape plan into Roblox Terrain: grass or sand ground, earth
-- banks under raised road, hills, lakes of real water with sandy shores,
-- mesas and snow-capped mountains. Terrain is smooth, textured and lit by
-- Future lighting, which is what makes the outdoor tracks look realistic.
--
-- Only one track's land exists at a time. `ensure` builds it once (the round
-- calls it as soon as the winning track is announced, so the land is usually
-- ready before the race loads); calling it again for the same track is free.
-- Anything registered with `onCleared` (the lobby's view) is rebuilt after.

local Workspace = game:GetService("Workspace")

local TerrainBuilder = {}

local current: string? = nil
local building: string? = nil
local keepers: { () -> () } = {}

local function material(name: string?): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name or "Grass"]
	end)
	return if ok and value then value else Enum.Material.Grass
end

local function terrainOf(): Terrain?
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	-- Lune's test DOM has no Terrain methods; skip building there.
	if not terrain or typeof((terrain :: any).FillBlock) ~= "function" then
		return nil
	end
	return terrain
end

-- Things that must survive a track change (the lobby's window view).
function TerrainBuilder.onCleared(rebuild: () -> ())
	table.insert(keepers, rebuild)
	rebuild()
end

-- Counts fills by kind; the smoke test checks these without real Terrain.
TerrainBuilder.lastCounts = {} :: { [string]: number }

-- `additive` adds to the land already there (the lobby's view) instead of
-- replacing it.
function TerrainBuilder.apply(plan: any, additive: boolean?)
	local counts = { slab = 0, bank = 0, hill = 0, mountain = 0, cap = 0, mesa = 0, lake = 0 }
	if not additive then
		TerrainBuilder.lastCounts = counts
	end
	local terrain = terrainOf()
	local spec = plan.spec
	-- Big fills take time; yield now and then so the server keeps ticking
	-- (the lobby, countdowns and other players) while the land is shaped.
	local fills = 0
	local function breathe()
		fills += 1
		if terrain and fills % 6 == 0 then
			task.wait()
		end
	end
	local ground = material(spec.ground)
	local bankMaterial = material(spec.bank or spec.ground)
	local function fillBlock(cf: CFrame, size: Vector3, m: Enum.Material, kind: string)
		counts[kind] += 1
		if terrain then
			terrain:FillBlock(cf, size, m)
			breathe()
		end
	end
	local function fillBall(b: any, kind: string)
		counts[kind] += 1
		if terrain then
			terrain:FillBall(Vector3.new(b.x, b.y, b.z), b.r, material(b.material))
			breathe()
		end
	end
	local function fillCylinder(cf: CFrame, height: number, radius: number, m: Enum.Material)
		if terrain then
			terrain:FillCylinder(cf, height, radius, m)
			breathe()
		end
	end

	if terrain then
		-- Animated grass blades stand 1-2 studs tall and poke through road
		-- and floors laid just above the ground, so they stay off.
		pcall(function()
			(terrain :: any).Decoration = false
		end)
	end
	if terrain and not additive then
		terrain:Clear()
		for name, c in spec.colors or {} do
			pcall(function()
				terrain:SetMaterialColor(material(name), Color3.fromRGB(c[1], c[2], c[3]))
			end)
		end
		local water = spec.water
		if water then
			terrain.WaterColor = Color3.fromRGB(water.color[1], water.color[2], water.color[3])
			terrain.WaterTransparency = water.transparency or 0.4
			terrain.WaterReflectance = water.reflectance or 0.5
			terrain.WaterWaveSize = water.waveSize or 0.12
			terrain.WaterWaveSpeed = water.waveSpeed or 8
		end
	end

	-- Ground: a slab whose top is just under the lowest road.
	local top = plan.groundTop
	local sx, sz = plan.maxX - plan.minX, plan.maxZ - plan.minZ
	fillBlock(CFrame.new((plan.minX + plan.maxX) / 2, top - 8, (plan.minZ + plan.maxZ) / 2), Vector3.new(sx, 16, sz), ground, "slab")

	-- Banks follow the road's slope (the block is pitched along the segment).
	for _, bank in plan.banks do
		local a = Vector3.new(bank.ax, bank.ay, bank.az)
		local b = Vector3.new(bank.bx, bank.by, bank.bz)
		local length = (b - a).Magnitude
		if length > 0.1 then
			local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, -bank.depth / 2, 0)
			fillBlock(cf, Vector3.new(bank.width, bank.depth, length + 4), bankMaterial, "bank")
		end
	end

	for _, hill in plan.hills do
		fillBall(hill, "hill")
	end
	for _, m in plan.mesas do
		counts.mesa += 1
		local height = m.top - m.bottom
		fillCylinder(CFrame.new(m.x, m.bottom + height / 2, m.z), height, m.r, material(m.material))
		if m.band then
			-- A darker rock band two thirds of the way up, slightly proud.
			fillCylinder(CFrame.new(m.x, m.bottom + height * 0.66, m.z), height * 0.12, m.r + 1.5, material(m.band))
		end
		-- A softer skirt of fallen sand round the foot.
		fillCylinder(CFrame.new(m.x, top - 1, m.z), 6, m.r * 1.25, ground)
	end
	for _, mountain in plan.mountains do
		fillBall(mountain, "mountain")
	end
	for _, cap in plan.caps do
		fillBall(cap, "cap")
	end

	-- Lakes: a sandy shore, the basin dug out, then water and a muddy bed.
	for _, lake in plan.lakes do
		counts.lake += 1
		local shore = material(lake.shore)
		fillCylinder(CFrame.new(lake.x, top - 2, lake.z), 4.2, lake.r + 12, shore)
		fillCylinder(CFrame.new(lake.x, top + 4, lake.z), 24, lake.r, Enum.Material.Air)
		fillCylinder(CFrame.new(lake.x, top - 11, lake.z), 2, lake.r + 2, Enum.Material.Mud)
		local depth = 9
		fillCylinder(CFrame.new(lake.x, lake.surface - depth / 2, lake.z), depth, lake.r, material(lake.liquid))
	end

	if not additive then
		for _, rebuild in keepers do
			local ok, err = pcall(rebuild)
			if not ok then
				warn("[TerrainBuilder] keeper failed:", err)
			end
		end
	end
end

-- Builds the land for a track once; safe to call from several threads.
function TerrainBuilder.ensure(trackId: string, plan: any?)
	if current == trackId then
		return
	end
	while building do
		task.wait(0.1)
		if current == trackId then
			return
		end
	end
	building = trackId
	local ok, err = pcall(function()
		local p = plan
		if not p then
			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local Landscape = require(ReplicatedStorage.Shared.Landscape)
			local Track = require(ReplicatedStorage.Shared.Track)
			local Tracks = require(ReplicatedStorage.Shared.Tracks)
			p = Landscape.plan(Track.build(Tracks.get(trackId)))
		end
		if p then
			TerrainBuilder.apply(p)
		end
	end)
	building = nil
	if ok then
		current = trackId
	else
		warn("[TerrainBuilder]", err)
	end
end

return TerrainBuilder
