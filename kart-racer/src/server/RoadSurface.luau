-- Builds the road and everything alongside it from one set of frames
-- (shared/RoadGeometry), so every piece meets the next exactly:
--   * road: a solid 2-stud slab built from triangles (two wedges each), so
--     curves and hills have no gaps, steps or overlapping, flickering slabs
--   * verges: the same triangle strips either side, out past the barrier,
--     grass (or the theme's material), gravel run-off on the outside of
--     corners, and a concrete deck on bridges
--   * curbs on corners, painted edge lines on straights, a dashed centre line
--   * barriers: one piece per segment, end to end, with gaps for shortcuts
--
-- Realistic themes get asphalt, concrete jersey barriers and red-and-white
-- concrete curbs; the toy-world themes keep their own colours.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoadGeometry = require(ReplicatedStorage.Shared.RoadGeometry)
local Track = require(ReplicatedStorage.Shared.Track)

local RoadSurface = {}

-- The road is a 4-stud slab and the verge strips are as thick. Terrain is
-- planned at least 3 studs under the road (Landscape), so it stays hidden
-- inside these slabs even where its 4-stud voxels round upward.
RoadSurface.Thickness = 4
RoadSurface.VergeExtra = 3 -- the verge runs this far past the barrier line
local SHOULDER_DROP = 0.12 -- shoulders sit just under the road so edges read

export type Style = { color: Color3, material: Enum.Material, collide: boolean, surface: string? }

local function v3(p: any): Vector3
	return Vector3.new(p.x, p.y, p.z)
end

-- One solid triangle: two wedges filling a, b, c, with the slab hanging
-- `thickness` studs below the surface (so the top face is exactly abc).
local function triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, thickness: number, style: Style, name: string)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-4 or bc.Magnitude < 1e-4 then
		return
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local down = if right.Y > 0 then -right else right
	local sink = down * (thickness / 2)
	for _, spec in {
		{ center = (a + b) / 2, right = right, back = back, length = math.abs(ab:Dot(back)) },
		{ center = (a + c) / 2, right = -right, back = -back, length = math.abs(ac:Dot(back)) },
	} do
		if spec.length > 1e-3 and height > 1e-3 then
			local wedge = Instance.new("WedgePart")
			wedge.Name = name
			wedge.Anchored = true
			wedge.Size = Vector3.new(thickness, height, spec.length)
			wedge.CFrame = CFrame.fromMatrix(spec.center + sink, spec.right, up, spec.back)
			wedge.Color = style.color
			wedge.Material = style.material
			wedge.CanCollide = style.collide
			wedge.CanQuery = style.collide
			wedge.CanTouch = false
			wedge.TopSurface = Enum.SurfaceType.Smooth
			wedge.BottomSurface = Enum.SurfaceType.Smooth
			if style.surface then
				wedge:SetAttribute("Surface", style.surface)
			end
			wedge.Parent = parent
		end
	end
end
RoadSurface.triangle = triangle

-- A box laid along the chord from a to b (lines, curbs, barriers).
local function chordBox(parent: Instance, a: Vector3, b: Vector3, width: number, height: number, lift: number, extend: number, style: Style, name: string): Part?
	local along = b - a
	if along.Magnitude < 0.05 then
		return nil
	end
	local mid = (a + b) / 2 + Vector3.new(0, lift + height / 2, 0)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(width, height, along.Magnitude + extend)
	p.CFrame = CFrame.lookAt(mid, mid + along)
	p.Color = style.color
	p.Material = style.material
	p.CanCollide = style.collide
	p.CanQuery = style.collide
	p.CanTouch = false
	p.CastShadow = style.collide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

export type Options = {
	theme: any,
	walled: boolean,
	plan: any?, -- Landscape plan (terrain verges where plan.bankAt[i])
	wallOpen: (side: number, distance: number, length: number) -> boolean,
}

function RoadSurface.build(track: any, frames: { any }, parent: Instance, opts: Options)
	local theme = opts.theme
	local def = track.def
	local half = def.width / 2
	local sw = Track.ShoulderWidth
	local n = #frames
	local realistic = theme.realistic == true
	local function rgb(c: { number }): Color3
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	local neon = def.theme == "neon"

	local surface = Instance.new("Folder")
	surface.Name = "RoadSurface"
	surface.Parent = parent
	local verge = Instance.new("Folder")
	verge.Name = "Shoulders"
	verge.Parent = parent
	local markings = parent:FindFirstChild("Markings") or Instance.new("Folder")
	markings.Name = "Markings"
	markings.Parent = parent
	local barriers = Instance.new("Folder")
	barriers.Name = "Barriers"
	barriers.Parent = parent

	local roadMaterial = theme.roadMaterial and Enum.Material[theme.roadMaterial] or (if realistic then Enum.Material.Asphalt else Enum.Material.SmoothPlastic)
	local road: Style = { color = rgb(theme.road), material = roadMaterial, collide = true, surface = "road" }
	local shoulder: Style = {
		color = rgb(theme.shoulder),
		material = theme.shoulderMaterial and Enum.Material[theme.shoulderMaterial] or (if realistic then Enum.Material.Ground else Enum.Material.SmoothPlastic),
		collide = true,
		surface = "offroad",
	}
	-- Bridge decks (raised road with nothing under it) are concrete in realistic themes.
	local deck: Style = { color = Color3.fromRGB(150, 148, 142), material = Enum.Material.Concrete, collide = true, surface = "offroad" }
	-- Gravel run-off on the outside of corners: lighter than grass, reads as "slow".
	local gravel: Style = { color = Color3.fromRGB(150, 140, 120), material = Enum.Material.Pebble, collide = true, surface = "offroad" }
	local paint = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local curbStyles: { Style } = {
		{ color = rgb(theme.curb[1]), material = if realistic then Enum.Material.Concrete else paint, collide = false },
		{ color = rgb(theme.curb[2]), material = if realistic then Enum.Material.Concrete else paint, collide = false },
	}
	local line: Style = { color = rgb(theme.line), material = paint, collide = false }

	local th = RoadSurface.Thickness
	for i = 1, n do
		local j = i % n + 1
		local a, b = frames[i], frames[j]
		local aL, aR = v3(RoadGeometry.edge(a, -half)), v3(RoadGeometry.edge(a, half))
		local bL, bR = v3(RoadGeometry.edge(b, -half)), v3(RoadGeometry.edge(b, half))
		triangle(surface, aL, aR, bL, th, road, "Road")
		triangle(surface, aR, bR, bL, th, road, "Road")

		-- Verges on both sides, out past the barrier, covering the terrain.
		local plan = opts.plan
		local onBridge = plan and not (plan.bankAt[i] and plan.bankAt[j])
		if opts.walled then
			local outer = half + sw + RoadSurface.VergeExtra
			-- Turning right (turn > 0) puts the outside of the bend on the left.
			local outside = if a.turn > 0 then -1 else 1
			local corner = RoadGeometry.isCorner(a) and RoadGeometry.isCorner(b)
			for _, side in { -1, 1 } do
				local style = shoulder
				if realistic and onBridge then
					style = deck
				elseif realistic and corner and side == outside then
					style = gravel
				end
				local ai = v3(RoadGeometry.edge(a, side * half, -SHOULDER_DROP))
				local ao = v3(RoadGeometry.edge(a, side * outer, -SHOULDER_DROP))
				local bi = v3(RoadGeometry.edge(b, side * half, -SHOULDER_DROP))
				local bo = v3(RoadGeometry.edge(b, side * outer, -SHOULDER_DROP))
				triangle(verge, ai, ao, bi, th, style, "Shoulder")
				triangle(verge, ao, bo, bi, th, style, "Shoulder")
			end
		end

		-- Curbs on corners (both sides), edge lines on straights.
		local corner = RoadGeometry.isCorner(a) and RoadGeometry.isCorner(b)
		for _, side in { -1, 1 } do
			if corner and opts.walled then
				local p0 = v3(RoadGeometry.edge(a, side * (half - 1.5)))
				local p1 = v3(RoadGeometry.edge(b, side * (half - 1.5)))
				chordBox(markings, p0, p1, 3, 0.14, 0, 0, curbStyles[i % 2 + 1], "Curb")
			else
				local p0 = v3(RoadGeometry.edge(a, side * (half - 1.4)))
				local p1 = v3(RoadGeometry.edge(b, side * (half - 1.4)))
				chordBox(markings, p0, p1, 0.8, 0.06, 0, 0, line, "EdgeLine")
			end
		end
		if i % 4 < 2 then
			chordBox(markings, v3(RoadGeometry.edge(a, 0)), v3(RoadGeometry.edge(b, 0)), 0.6, 0.06, 0, 0, line, "CentreLine")
		end
	end

	-- Barriers, one piece per segment, skipping shortcut gaps and the rare
	-- inside-of-a-hairpin segment that would run backwards.
	if opts.walled then
		local wallAt = half + sw + 0.9
		local folded = {}
		for _, side in { -1, 1 } do
			folded[side] = {}
			for _, i in RoadGeometry.folds(frames, side * wallAt) do
				folded[side][i] = true
			end
		end
		local wallColor = rgb(theme.wall)
		local wallMaterial = theme.wallMaterial and Enum.Material[theme.wallMaterial] or (if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic)
		for i = 1, n do
			local j = i % n + 1
			local a, b = frames[i], frames[j]
			local segLen = (v3(b) - v3(a)).Magnitude
			local distance = track.cum[i] + segLen / 2
			for _, side in { -1, 1 } do
				if not folded[side][i] and not opts.wallOpen(side, distance, segLen) then
					local p0 = v3(RoadGeometry.edge(a, side * wallAt))
					local p1 = v3(RoadGeometry.edge(b, side * wallAt))
					if realistic then
						-- Concrete jersey barrier: wide foot, narrow top, a painted band.
						chordBox(barriers, p0, p1, 2, 1.2, -0.2, 0.5, { color = wallColor, material = Enum.Material.Concrete, collide = true }, "Wall")
						chordBox(barriers, p0, p1, 1.1, 2.4, 1, 0.5, { color = wallColor, material = Enum.Material.Concrete, collide = true }, "Wall")
						if i % 2 == 0 then
							-- Red band on alternate pieces; the bare concrete between reads as white.
							chordBox(barriers, p0, p1, 1.16, 0.35, 2.6, 0.5, { color = rgb(theme.curb[1]), material = Enum.Material.SmoothPlastic, collide = false }, "WallBand")
						end
					else
						chordBox(barriers, p0, p1, 1, 4, -0.5, 0.5, { color = wallColor, material = wallMaterial, collide = true }, "Wall")
					end
				end
			end
		end
	end
	return surface
end

return RoadSurface
