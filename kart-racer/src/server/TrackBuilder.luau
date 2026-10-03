-- Builds a track's parts from its centerline: road, curbs and lane lines,
-- grass shoulders, walls, bridge pillars, boost pads, the start line, the
-- ground and scenery (see Scenery.luau / Props.luau). Lighting is applied on
-- each client (common/Atmos), so lobby players keep the lobby's look.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Scenery = require(Shared.Scenery)
local Track = require(Shared.Track)
local Tracks = require(Shared.Tracks)

local Landmarks = require(script.Parent.Landmarks)
local Props = require(script.Parent.Props)
local Shapes = require(ReplicatedStorage.Common.Shapes)

local BANK_MAX = math.rad(6) -- corners tilt inward a little

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

-- Markings sit just above the road; raycasts and collisions ignore them.
local function decal(parent: Instance, size: Vector3, cf: CFrame, color: Color3, glow: boolean): Part
	local p = part(parent, "Marking", size, cf, color, if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function flatAngle(a: Vector3, b: Vector3): number
	return math.atan2(b.X - a.X, b.Z - a.Z)
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
	local roadColor, shoulderColor, wallColor = rgb(theme.road), rgb(theme.shoulder), rgb(theme.wall)
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
	local neon = def.theme == "neon"
	local curbColors = { rgb(theme.curb[1]), rgb(theme.curb[2]) }
	local lineColor = rgb(theme.line)

	-- Banking: smoothed signed turn per segment (positive = turning left).
	local signedTurn = {}
	for i = 1, n do
		local a, b, c = v3(pts[i]), v3(pts[i % n + 1]), v3(pts[(i + 1) % n + 1])
		signedTurn[i] = ((flatAngle(b, c) - flatAngle(a, b)) + math.pi) % (2 * math.pi) - math.pi
	end
	local function bank(i: number): number
		local sum = 0
		for k = -3, 3 do
			sum += signedTurn[(i - 1 + k) % n + 1]
		end
		return math.clamp(sum / 7 * 4, -BANK_MAX, BANK_MAX)
	end

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

	for i = 1, n do
		local a, b, c = v3(pts[i]), v3(pts[i % n + 1]), v3(pts[(i + 1) % n + 1])
		local length = (b - a).Magnitude
		-- Lengthen segments on the outside of bends so the edges have no gaps.
		local turn = math.abs(signedTurn[i])
		local extra = 1 + (half + sw + 1) * turn
		local roll = 0 -- ribbon and checkpoint road height share the same surface
		local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, 0, roll)
		local segLen = length + extra
		local segDistance = track.cum[i] + length / 2

		local road = part(folder, "Road", Vector3.new(def.width, 1, segLen), cf * CFrame.new(0, -0.5, 0), roadColor, if def.theme == "fortress" then Enum.Material.Slate else Enum.Material.SmoothPlastic)
		road:SetAttribute("Surface", "road")
		-- Retain segment metadata but use the continuous ribbon for collision.
		road.Transparency = 1
		road.CanCollide = false
		road.CanQuery = false
		road.CanTouch = false
		for _, side in (if walled then { -1, 1 } else {}) :: { number } do
			local shoulder = part(folder, "Shoulder", Vector3.new(sw, 1, segLen), cf * CFrame.new(side * (half + sw / 2), -0.52, 0), shoulderColor, Enum.Material.SmoothPlastic)
			shoulder:SetAttribute("Surface", "offroad")
			if not wallOpen(side, segDistance, segLen) then
				part(folder, "Wall", Vector3.new(1, 4, segLen), cf * CFrame.new(side * (half + sw + 0.5), 1.5, 0), wallColor, if def.theme == "neon" then Enum.Material.Neon elseif def.theme == "fortress" then Enum.Material.Cobblestone else Enum.Material.SmoothPlastic)
			end
		end

		-- Red-and-white curbs through corners, lane lines on the straights.
		if turn > 0.02 and walled then
			for _, side in { -1, 1 } do
				decal(markings, Vector3.new(3, 0.1, length + 0.6), cf * CFrame.new(side * (half - 1.5), 0.05, 0), curbColors[i % 2 + 1], neon)
			end
		else
			for _, side in { -1, 1 } do
				decal(markings, Vector3.new(0.8, 0.06, length + 0.4), cf * CFrame.new(side * (half - 1.2), 0.03, 0), lineColor, neon)
			end
		end
		if i % 3 ~= 0 then
			decal(markings, Vector3.new(0.7, 0.06, length * 0.7), cf * CFrame.new(0, 0.03, 0), lineColor, neon)
		end

		minY = math.min(minY, a.Y)
		minX, maxX = math.min(minX, a.X), math.max(maxX, a.X)
		minZ, maxZ = math.min(minZ, a.Z), math.max(maxZ, a.Z)
	end

	local ribbon = Instance.new("Folder")
	ribbon.Name = "RoadSurface"
	ribbon.Parent = folder
	require(script.Parent.RoadRibbon).build(track, ribbon, roadColor,
		if def.theme == "fortress" then Enum.Material.Slate else Enum.Material.Asphalt)

	-- Pillars under raised road, skipped where they would land on the road below.
	for i = 1, n, 6 do
		local p = pts[i]
		if p.y - minY > 8 then
			local blocked = false
			for j, q in pts do
				local apart = math.min(math.abs(i - j), n - math.abs(i - j))
				if apart > 20 and math.abs(q.x - p.x) < half + sw + 6 and math.abs(q.z - p.z) < half + sw + 6 and q.y < p.y - 8 then
					blocked = true
					break
				end
			end
			if not blocked then
				local h = p.y - minY
				part(folder, "Pillar", Vector3.new(6, h, 6), CFrame.new(p.x, minY + h / 2 - 1, p.z), wallColor, Enum.Material.SmoothPlastic)
			end
		end
	end

	-- Ground under everything.
	if opts.ground ~= false then
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
	for _, sc in def.shortcuts or {} do
		local sa, sb = Track.shortcutEnds(track, sc)
		local pa, pb = v3(sa), v3(sb)
		local length = (pb - pa).Magnitude + sc.width
		local scCf = CFrame.lookAt((pa + pb) / 2, pb)
		local road = part(folder, "ShortcutRoad", Vector3.new(sc.width, 1, length), scCf * CFrame.new(0, -0.5, 0), roadColor:Lerp(rgb(theme.accent), 0.25), Enum.Material.SmoothPlastic)
		road:SetAttribute("Surface", sc.surface or "road")
		-- Connect each end to the road edge across the grass shoulder.
		for _, endpoint in { { at = sc.from, p = pa }, { at = sc.to, p = pb } } do
			local edge = v3(Track.spot(track, endpoint.at * track.length, sc.side * half))
			local link = (endpoint.p - edge)
			part(folder, "ShortcutLink", Vector3.new(sc.width, 1, link.Magnitude + sc.width), CFrame.lookAt((edge + endpoint.p) / 2, endpoint.p) * CFrame.new(0, -0.49, 0), roadColor:Lerp(rgb(theme.accent), 0.25), Enum.Material.SmoothPlastic)
		end
		-- Little arrows hint the way in.
		for _, side in { -1, 1 } do
			Shapes.box(folder, Vector3.new(0.8, 6, 0.8), scCf * CFrame.new(side * (sc.width / 2 + 1), 3, -length / 2 + 2), { color = rgb(theme.accent), material = Enum.Material.Neon })
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
			Props.build(prop, theme, scenery)
		end
	end

	if def.theme == "fortress" then
		require(script.Parent.FortressBuilder).build(track, folder)
	end

	folder.Parent = Workspace
	return folder, track
end

return TrackBuilder
