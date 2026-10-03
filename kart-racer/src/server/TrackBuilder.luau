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

local Props = require(script.Parent.Props)

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

	for i = 1, n do
		local a, b, c = v3(pts[i]), v3(pts[i % n + 1]), v3(pts[(i + 1) % n + 1])
		local length = (b - a).Magnitude
		-- Lengthen segments on the outside of bends so the edges have no gaps.
		local turn = math.abs(((flatAngle(b, c) - flatAngle(a, b)) + math.pi) % (2 * math.pi) - math.pi)
		local extra = 1 + (half + sw + 1) * turn
		local cf = CFrame.lookAt((a + b) / 2, b)
		local segLen = length + extra

		local road = part(folder, "Road", Vector3.new(def.width, 1, segLen), cf * CFrame.new(0, -0.5, 0), roadColor, Enum.Material.SmoothPlastic)
		road:SetAttribute("Surface", "road")
		for _, side in (if walled then { -1, 1 } else {}) :: { number } do
			local shoulder = part(folder, "Shoulder", Vector3.new(sw, 1, segLen), cf * CFrame.new(side * (half + sw / 2), -0.52, 0), shoulderColor, Enum.Material.SmoothPlastic)
			shoulder:SetAttribute("Surface", "offroad")
			part(folder, "Wall", Vector3.new(1, 4, segLen), cf * CFrame.new(side * (half + sw + 0.5), 1.5, 0), wallColor, if def.theme == "neon" then Enum.Material.Neon else Enum.Material.SmoothPlastic)
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
			local stripe = part(folder, "RampStripe", Vector3.new(1.2, 0.2, 18.6), cf * CFrame.new(k * (ramp.width / 2 - 1.5), 2.6, 0) * CFrame.Angles(math.atan2(5, 18), 0, 0), Color3.new(1, 1, 1), Enum.Material.Neon)
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

	folder.Parent = Workspace
	return folder, track
end

return TrackBuilder
