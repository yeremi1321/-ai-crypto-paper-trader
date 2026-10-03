-- Builds a track from its centerline: the road and everything along it
-- (RoadSurface), the land (Landscape + TerrainBuilder for realistic themes, a
-- flat floor otherwise), bridge pillars, boost pads, the start line, zones,
-- shortcuts, landmarks and scenery (see Scenery.luau / Props.luau). Lighting is applied on
-- each client (common/Atmos), so lobby players keep the lobby's look.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Landscape = require(Shared.Landscape)
local RoadGeometry = require(Shared.RoadGeometry)
local Scenery = require(Shared.Scenery)
local Track = require(Shared.Track)
local Tracks = require(Shared.Tracks)

local Assets = require(ReplicatedStorage.Common.Assets)
local Landmarks = require(script.Parent.Landmarks)
local Props = require(script.Parent.Props)
local RoadSurface = require(script.Parent.RoadSurface)
local TerrainBuilder = require(script.Parent.TerrainBuilder)
local Shapes = require(ReplicatedStorage.Common.Shapes)

local TrackBuilder = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function v3(p: Track.Vec): Vector3
	return Vector3.new(p.x, p.y, p.z)
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

export type Options = {
	folderName: string?, -- default "Track"; the lobby practice loop uses its own folder
	ground: boolean?, -- build ground under the track (default true)
	scenery: boolean?, -- place scenery props (default true)
}

function TrackBuilder.build(trackId: string, options: Options?): (Folder, Track.Built)
	local opts = options or {}
	local def = Tracks.get(trackId)
	local track = Track.build(def)
	local theme = Tracks.Themes[def.theme]
	local roadColor, wallColor = rgb(theme.road), rgb(theme.wall)
	local walled = def.walls ~= false

	local folderName = opts.folderName or "Track"
	local old = Workspace:FindFirstChild(folderName)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder:SetAttribute("TrackId", trackId)

	local half = def.width / 2
	local sw = Track.ShoulderWidth
	local pts = track.points
	local n = #pts
	local minY, minX, maxX, minZ, maxZ = math.huge, math.huge, -math.huge, math.huge, -math.huge
	local markings = Instance.new("Folder")
	markings.Name = "Markings"
	markings.Parent = folder

	-- Wall openings where shortcuts leave and rejoin the road.
	local openings = {}
	for _, sc in def.shortcuts or {} do
		table.insert(openings, { side = sc.side, at = sc.from * track.length, half = sc.width / 2 + 6 })
		table.insert(openings, { side = sc.side, at = sc.to * track.length, half = sc.width / 2 + 6 })
	end
	local function wallOpen(side: number, distance: number, segLen: number): boolean
		for _, o in openings do
			local d = (distance - o.at + track.length / 2) % track.length - track.length / 2
			if o.side == side and math.abs(d) < o.half + segLen / 2 then
				return true
			end
		end
		return false
	end

	for _, p in pts do
		minY = math.min(minY, p.y)
		minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
		minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
	end

	-- Land: realistic themes get Terrain (hills, lakes, mountains, banks under
	-- raised road); the toy-world themes keep a flat part floor.
	local plan = if opts.ground ~= false then Landscape.plan(track) else nil
	-- Land hand-sculpted in Studio and saved (StudioTools) wins over the plan.
	local handMade = opts.ground ~= false and TerrainBuilder.saved(trackId) ~= nil
	if plan or handMade then
		TerrainBuilder.ensure(trackId, plan)
	end

	-- Road, curbs, lines, shoulders and barriers from one set of frames.
	local frames = RoadGeometry.frames(track)
	RoadSurface.build(track, frames, folder, { theme = theme, walled = walled, plan = plan, wallOpen = wallOpen })

	-- Pillars under raised road that has no earth bank, skipped where they
	-- would land on the road below.
	local overpass = RoadGeometry.overpasses(track, half + sw + 6, 8)
	local pillarColor = if theme.realistic then Color3.fromRGB(150, 148, 142) else wallColor
	local pillarMaterial = if theme.realistic then Enum.Material.Concrete else Enum.Material.SmoothPlastic
	for i = 1, n, 6 do
		local p = pts[i]
		local banked = plan and plan.bankAt[i]
		if p.y - minY > 8 and not banked and not overpass[i] then
			local h = p.y - minY + 4
			part(folder, "Pillar", Vector3.new(6, h, 6), CFrame.new(p.x, p.y - 1 - h / 2, p.z), pillarColor, pillarMaterial)
		end
	end

	-- Flat floor under everything (themes without terrain).
	if opts.ground ~= false and not plan and not handMade then
		local margin = 300
		local sizeX, sizeZ = maxX - minX + margin * 2, maxZ - minZ + margin * 2
		local tile = 1000
		for x = minX - margin, minX - margin + sizeX, tile do
			for z = minZ - margin, minZ - margin + sizeZ, tile do
				local g = part(folder, "Ground", Vector3.new(tile, 2, tile), CFrame.new(x + tile / 2, minY - 1.6, z + tile / 2), rgb(theme.ground), Enum.Material.SmoothPlastic)
				g:SetAttribute("Surface", "offroad")
			end
		end
	end

	-- Boost pads (visual; the surface is worked out from Track.surfaceAt).
	for _, pad in Track.pads(track) do
		local pos = v3(Track.spot(track, pad.distance, pad.lateral))
		local _, tan = Track.at(track, pad.distance)
		local cf = CFrame.lookAt(pos, pos + v3(tan))
		local p = part(folder, "BoostPad", Vector3.new(Track.PadWidth, 0.2, Track.PadLength), cf * CFrame.new(0, 0.05, 0), rgb(theme.accent), Enum.Material.Neon)
		p.CanCollide = false
		p.CanQuery = false
		for k = -1, 1 do
			local arrow = part(folder, "Arrow", Vector3.new(6, 0.25, 2), cf * CFrame.new(0, 0.12, k * 7) * CFrame.Angles(0, math.rad(45), 0), Color3.new(1, 1, 1), Enum.Material.Neon)
			arrow.CanCollide = false
			arrow.CanQuery = false
		end
	end

	-- Checkered start/finish line.
	local start, tan = Track.at(track, 0)
	local lineCf = CFrame.lookAt(v3(start), v3(start) + v3(tan))
	local squares = 8
	for k = 0, squares - 1 do
		for row = 0, 1 do
			local sq = part(folder, "Finish", Vector3.new(def.width / squares, 0.2, 3), lineCf * CFrame.new(-half + (k + 0.5) * def.width / squares, 0.06, (row - 0.5) * 3), if (k + row) % 2 == 0 then Color3.new(1, 1, 1) else Color3.new(0.05, 0.05, 0.05), Enum.Material.SmoothPlastic)
			sq.CanCollide = false
			sq.CanQuery = false
		end
	end
	-- Banner over the line.
	for _, side in { -1, 1 } do
		part(folder, "BannerPost", Vector3.new(1.5, 18, 1.5), lineCf * CFrame.new(side * (half + 4), 9, 0), wallColor, Enum.Material.SmoothPlastic)
	end
	part(folder, "Banner", Vector3.new(def.width + 10, 3, 1), lineCf * CFrame.new(0, 17, 0), rgb(theme.accent), Enum.Material.Neon)

	-- Surface patches: syrup, water, conveyor belts, launch pads.
	local zoneStyle = {
		sticky = { color = Color3.fromRGB(150, 85, 30), material = Enum.Material.Glass, transparency = 0.1 },
		slippery = { color = Color3.fromRGB(120, 190, 255), material = Enum.Material.Glass, transparency = 0.35 },
		conveyor = { color = Color3.fromRGB(70, 72, 82), material = Enum.Material.SmoothPlastic, transparency = 0 },
		launch = { color = Color3.fromRGB(255, 80, 80), material = Enum.Material.Neon, transparency = 0 },
	}
	for zi, zone in def.zones or {} do
		local style = zoneStyle[zone.kind]
		if style then
			local width = zone.width or def.width
			local offset = (zone.offset or 0) * (half - width / 2)
			local from = zone.t * track.length - zone.length / 2
			local steps = math.max(1, math.ceil(zone.length / 10))
			for k = 0, steps - 1 do
				local d = from + (k + 0.5) * zone.length / steps
				local p = v3(Track.spot(track, d, offset))
				local _, tan = Track.at(track, d)
				local zcf = CFrame.lookAt(p, p + v3(tan))
				local patch = part(markings, "Zone", Vector3.new(width, 0.12, zone.length / steps + 0.4), zcf * CFrame.new(0, 0.07, 0), style.color, style.material)
				patch.Transparency = style.transparency
				patch.CanCollide = false
				patch.CanQuery = false
				patch:SetAttribute("ZoneIndex", zi)
				if zone.kind == "conveyor" and k % 2 == 0 then
					local arrow = part(markings, "ConveyorArrow", Vector3.new(width * 0.5, 0.15, 2), zcf * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, math.rad(45), 0), Color3.fromRGB(255, 210, 60), Enum.Material.Neon)
					arrow.CanCollide = false
					arrow.CanQuery = false
				end
			end
		end
	end

	-- Shortcut paths: a narrow road through the gap in the wall.
	local shortcutMaterial = if theme.realistic then Enum.Material.Asphalt else Enum.Material.SmoothPlastic
	for _, sc in def.shortcuts or {} do
		local sa, sb = Track.shortcutEnds(track, sc)
		local pa, pb = v3(sa), v3(sb)
		local length = (pb - pa).Magnitude + sc.width
		local scCf = CFrame.lookAt((pa + pb) / 2, pb)
		-- As thick as the main road, so terrain under it stays hidden.
		local road = part(folder, "ShortcutRoad", Vector3.new(sc.width, 4, length), scCf * CFrame.new(0, -2, 0), roadColor:Lerp(rgb(theme.accent), 0.25), shortcutMaterial)
		road:SetAttribute("Surface", sc.surface or "road")
		-- Connect each end to the road edge across the grass shoulder.
		for _, endpoint in { { at = sc.from, p = pa }, { at = sc.to, p = pb } } do
			local edge = v3(Track.spot(track, endpoint.at * track.length, sc.side * half))
			local link = (endpoint.p - edge)
			part(folder, "ShortcutLink", Vector3.new(sc.width, 4, link.Magnitude + sc.width), CFrame.lookAt((edge + endpoint.p) / 2, endpoint.p) * CFrame.new(0, -1.99, 0), roadColor:Lerp(rgb(theme.accent), 0.25), shortcutMaterial)
		end
		-- Posts either side of the entry hint the way in (shortcut blue on
		-- realistic tracks, the theme's glow elsewhere).
		local postColor = if theme.realistic then Color3.fromRGB(60, 150, 255) else rgb(theme.accent)
		local postMaterial = if theme.realistic then Enum.Material.SmoothPlastic else Enum.Material.Neon
		for _, side in { -1, 1 } do
			Shapes.box(folder, Vector3.new(0.8, 6, 0.8), scCf * CFrame.new(side * (sc.width / 2 + 1), 3, -length / 2 + 2), { color = postColor, material = postMaterial })
		end
		if def.theme == "backyard" then
			-- The shortcut runs through a hollow log.
			local logLen = math.min(length * 0.5, 60)
			for z = -logLen / 2, logLen / 2, 4 do
				Shapes.arch(folder, sc.width + 6, 3, 4.5, scCf * CFrame.new(0, -2, z), { color = Color3.fromRGB(130, 90, 55), collide = true }, 14)
			end
		end
	end

	-- Tunnels, landmarks and moving crossers.
	local landmarks = Instance.new("Folder")
	landmarks.Name = "Landmarks"
	landmarks.Parent = folder
	for _, tn in def.tunnels or {} do
		Landmarks.tunnel(track, tn.style, tn.from, tn.to, theme, landmarks)
	end
	for _, spot in Scenery.setPieceSpots(track) do
		Landmarks.setPiece(spot.kind, CFrame.new(spot.x, spot.y, spot.z) * CFrame.Angles(0, spot.yaw, 0), theme, landmarks)
	end
	local crossersFolder = Instance.new("Folder")
	crossersFolder.Name = "Crossers"
	crossersFolder.Parent = folder
	for ci, cr in def.crossers or {} do
		local p = Track.spot(track, cr.t * track.length, -(half + sw))
		Landmarks.crosser(cr.kind, ci, crossersFolder, CFrame.new(p.x, p.y, p.z))
	end
	if theme.room then
		Landmarks.room(theme, minX, maxX, minZ, maxZ, minY, landmarks)
	end

	-- Jump ramps. The low edge faces oncoming karts; the tall back edge launches them.
	for _, ramp in def.ramps or {} do
		local d = ramp.t * track.length
		local pos = v3(Track.spot(track, d, ramp.offset * (half - ramp.width / 2)))
		local _, rampTan = Track.at(track, d)
		local cf = CFrame.lookAt(pos, pos - v3(rampTan))
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Ramp"
		wedge.Anchored = true
		wedge.Size = Vector3.new(ramp.width, 5, 18)
		wedge.CFrame = cf * CFrame.new(0, 2.5, 0)
		wedge.Color = rgb(theme.accent)
		wedge.Material = Enum.Material.SmoothPlastic
		wedge.TopSurface = Enum.SurfaceType.Smooth
		wedge:SetAttribute("Surface", "ramp")
		wedge.Parent = folder
		for k = -1, 1, 2 do
			local stripe = part(folder, "RampStripe", Vector3.new(1.2, 0.2, 18.6), cf * CFrame.new(k * (ramp.width / 2 - 1.5), 2.6, 0) * CFrame.Angles(-math.atan2(5, 18), 0, 0), Color3.new(1, 1, 1), Enum.Material.Neon)
			stripe.CanCollide = false
			stripe.CanQuery = false
		end
	end

	-- Scenery around the track.
	if opts.scenery ~= false then
		local scenery = Instance.new("Folder")
		scenery.Name = "Scenery"
		scenery.Parent = folder
		for _, prop in Scenery.place(track) do
			if handMade then
				-- Stand props on the sculpted surface; skip water.
				local y = TrackBuilder.landHeight(prop.x, prop.z)
				if y then
					prop.y = y
					Props.build(prop, theme, scenery)
				end
			elseif plan then
				-- Stand props on the land; skip any that would be in a lake.
				local y = Landscape.groundAt(plan, prop.x, prop.z)
				if y then
					prop.y = y
					Props.build(prop, theme, scenery)
				end
			else
				Props.build(prop, theme, scenery)
			end
		end
	end

	if def.theme == "fortress" then
		require(script.Parent.FortressBuilder).build(track, folder)
	end

	TrackBuilder.ambience(folder, track, plan, minX, maxX, minZ, maxZ)

	folder.Parent = Workspace
	return folder, track
end

-- Height of the terrain surface at (x, z), or nil over water or nothing.
function TrackBuilder.landHeight(x: number, z: number): number?
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return nil
	end
	local ok, hit = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { terrain }
		return Workspace:Raycast(Vector3.new(x, 3000, z), Vector3.new(0, -6000, 0), params)
	end)
	if not ok or not hit or hit.Material == Enum.Material.Water then
		return nil
	end
	return hit.Position.Y
end

-- Ambient sound, only if it was added in Studio (KartAssets.Sounds): wind
-- over the whole map, water at lakes and rivers, birds in the trees. Each
-- is a looped sound on an invisible part, fading out with distance, so
-- players in the lobby (far away) hear none of it.
function TrackBuilder.ambience(folder: Instance, track: Track.Built, plan: any?, minX: number, maxX: number, minZ: number, maxZ: number)
	local sounds = Instance.new("Folder")
	sounds.Name = "Ambience"
	sounds.Parent = folder
	local function emitter(name: string, at: Vector3, reach: number, volume: number): boolean
		local sound = Assets.sound(name)
		if not sound then
			return false
		end
		local holder = Instance.new("Part")
		holder.Name = name
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.CFrame = CFrame.new(at)
		holder.Parent = sounds
		sound.Looped = true
		sound.Volume = math.min(sound.Volume, volume)
		sound.RollOffMode = Enum.RollOffMode.Linear
		sound.RollOffMinDistance = reach * 0.3
		sound.RollOffMaxDistance = reach
		sound.Playing = true
		sound.Parent = holder
		return true
	end
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local extent = math.max(maxX - minX, maxZ - minZ) / 2
	local y = track.points[1].y + 20
	emitter("Wind", Vector3.new(cx, y, cz), extent + 400, 0.3)
	if plan then
		-- Water: every lake, and every third pool along a river (at most 10).
		local placed = 0
		for i, lake in plan.lakes do
			if placed < 10 and (not lake.bridged or i % 3 == 0) then
				if emitter("Water", Vector3.new(lake.x, lake.surface + 1, lake.z), lake.r + 90, 0.5) then
					placed += 1
				end
			end
		end
	end
	-- Birds: a few spots spread round the lap, beside the road.
	for k = 0, 5 do
		local spot = Track.spot(track, track.length * (k + 0.5) / 6, if k % 2 == 0 then 70 else -70)
		emitter("Birds", Vector3.new(spot.x, spot.y + 25, spot.z), 140, 0.25)
	end
end

return TrackBuilder
