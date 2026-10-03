-- Command-bar helpers for shaping a track's land by hand in Roblox Studio.
-- Use them in Edit mode (not Play). Paste into the command bar (View → Command Bar):
--
--   local T = require(game.ServerScriptService.Server.StudioTools)
--   T.preview("ridgeline")  -- build the track and its land so you can see it
--   -- sculpt, paint and smooth with the Terrain Editor; import a heightmap;
--   -- run a terrain plugin; anything that edits Terrain works
--   T.check("ridgeline")    -- lists spots where the land comes too close to the road
--   T.save("ridgeline")     -- races use your land from now on (then File → Save)
--   T.forget("ridgeline")   -- go back to the generated land
--   T.clear()               -- remove the preview before publishing (smaller file)
--
-- "lobby" works the same way for the view outside the lobby window:
-- T.preview("lobby") … T.save("lobby").
--
-- Saved land lives in ServerStorage.KartTerrain.<id> as TerrainRegion tiles.
-- The road itself always comes from the track data, so keep the land under
-- it: T.check flags terrain within about 1 stud of the road surface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Landscape = require(Shared.Landscape)
local LobbyLayout = require(Shared.LobbyLayout)
local RoadGeometry = require(Shared.RoadGeometry)
local Track = require(Shared.Track)
local Tracks = require(Shared.Tracks)

local TerrainBuilder = require(script.Parent.TerrainBuilder)

local StudioTools = {}

StudioTools.TileCells = 256 -- each saved tile is 256 × 256 cells (1,024 studs) across

local function cells(studs: number): number
	return math.floor(studs / 4)
end

-- The block of terrain cells that belongs to a track (or the lobby view):
-- everything its land plan fills, from under the lakes to over the peaks.
function StudioTools.region(id: string): (Vector3int16, Vector3int16)
	if id == "lobby" then
		local o = LobbyLayout.Origin
		local back = o.z + LobbyLayout.HalfDepth
		return Vector3int16.new(cells(o.x - 1000), cells(-220), cells(o.z - 260)), Vector3int16.new(cells(o.x + 1000), cells(560), cells(back + 1500))
	end
	local track = Track.build(Tracks.get(id))
	local minY, maxY = math.huge, -math.huge
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in track.points do
		minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
		minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
		minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
	end
	local plan = Landscape.plan(track)
	local low, high = minY - 60, maxY + 300
	if plan then
		minX, maxX, minZ, maxZ = plan.minX, plan.maxX, plan.minZ, plan.maxZ
		low = plan.groundTop - 40
		for _, list in { plan.mountains, plan.caps, plan.hills } do
			for _, b in list do
				high = math.max(high, b.y + b.r + 30)
			end
		end
		for _, m in plan.mesas do
			high = math.max(high, m.top + 30)
		end
	else
		minX, maxX, minZ, maxZ = minX - 500, maxX + 500, minZ - 500, maxZ + 500
	end
	return Vector3int16.new(cells(minX), cells(low), cells(minZ)), Vector3int16.new(cells(maxX), cells(high), cells(maxZ))
end

-- Builds a track (or the lobby) and its land in the edit world.
function StudioTools.preview(id: string)
	TerrainBuilder.reset()
	if id == "lobby" then
		require(script.Parent.LobbyBuilder).build()
		print("[StudioTools] Built the lobby and its view. Shape the land behind the back window, then T.save(\"lobby\").")
		return
	end
	local def = Tracks.get(id)
	require(script.Parent.TrackBuilder).build(id)
	local source = if TerrainBuilder.saved(id) then "your saved land" else "generated land"
	print(`[StudioTools] Built {def.name} with {source}. Edit the terrain, then T.check("{id}") and T.save("{id}").`)
end

-- Saves the terrain in the track's region as tiles. Races then paste it
-- instead of generating land. Remember to save the place afterwards.
function StudioTools.save(id: string)
	local terrain = Workspace.Terrain
	local lo, hi = StudioTools.region(id)
	local root = ServerStorage:FindFirstChild(TerrainBuilder.SavedFolder)
	if not root then
		root = Instance.new("Folder")
		root.Name = TerrainBuilder.SavedFolder
		root.Parent = ServerStorage
	end
	local old = root:FindFirstChild(id)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = id
	local step = StudioTools.TileCells
	local count = 0
	for x = lo.X, hi.X, step do
		for z = lo.Z, hi.Z, step do
			local region = Region3int16.new(Vector3int16.new(x, lo.Y, z), Vector3int16.new(math.min(x + step - 1, hi.X), hi.Y, math.min(z + step - 1, hi.Z)))
			local tile = terrain:CopyRegion(region)
			tile.Name = `Tile_{x}_{z}`
			tile:SetAttribute("CellX", x)
			tile:SetAttribute("CellY", lo.Y)
			tile:SetAttribute("CellZ", z)
			tile.Parent = folder
			count += 1
			task.wait()
		end
	end
	folder.Parent = root
	print(`[StudioTools] Saved {count} land tiles for "{id}". Races use this land now. Save the place (File → Save) to keep it.`)
end

-- Removes a track's saved land; races go back to generating it.
function StudioTools.forget(id: string)
	local root = ServerStorage:FindFirstChild(TerrainBuilder.SavedFolder)
	local saved = root and root:FindFirstChild(id)
	if saved then
		saved:Destroy()
		print(`[StudioTools] Forgot the saved land for "{id}".`)
	else
		print(`[StudioTools] No saved land for "{id}".`)
	end
end

-- Lists places where terrain (or water) reaches within about 1 stud of the
-- road surface or its verge, where it could show through. Fix them with the
-- Terrain Editor's Flatten or Subtract tools, then check again.
function StudioTools.check(id: string): number
	local terrain = Workspace.Terrain
	local def = Tracks.get(id)
	local track = Track.build(def)
	local frames = RoadGeometry.frames(track)
	local half = def.width / 2
	local verge = half + Track.ShoulderWidth + 3
	local problems = 0
	for i = 1, #frames, 2 do
		local f = frames[i]
		for _, lateral in { -verge, -half, 0, half, verge } do
			local e = RoadGeometry.edge(f, lateral)
			local region = Region3.new(Vector3.new(e.x - 2, e.y - 6, e.z - 2), Vector3.new(e.x + 2, e.y + 4, e.z + 2)):ExpandToGrid(4)
			local materials, occupancy = terrain:ReadVoxels(region, 4)
			local size = occupancy.Size
			local bottom = region.CFrame.Position.Y - region.Size.Y / 2
			local worst = -math.huge
			for y = 1, size.Y do
				for x = 1, size.X do
					for z = 1, size.Z do
						local occ = occupancy[x][y][z]
						if occ > 0 and materials[x][y][z] ~= Enum.Material.Air then
							worst = math.max(worst, bottom + (y - 1) * 4 + occ * 4)
						end
					end
				end
			end
			if worst > e.y - 1 then
				problems += 1
				if problems <= 25 then
					print(string.format("[StudioTools] land %.1f studs from the road surface near (%d, %d, %d)", e.y - worst, math.floor(e.x), math.floor(e.y), math.floor(e.z)))
				end
			end
		end
	end
	if problems == 0 then
		print(`[StudioTools] {def.name}: the land stays clear of the road everywhere.`)
	else
		print(`[StudioTools] {def.name}: {problems} spots are too close to the road (first 25 listed).`)
	end
	return problems
end

-- Removes preview tracks, the lobby and all terrain from the edit world.
-- Saved land (ServerStorage.KartTerrain) is kept.
function StudioTools.clear()
	for _, name in { "Track", "PracticeTrack", "Lobby", "LobbyVista" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			f:Destroy()
		end
	end
	Workspace.Terrain:Clear()
	TerrainBuilder.reset()
	print("[StudioTools] Cleared the preview. Saved land is kept in ServerStorage.KartTerrain.")
end

return StudioTools
