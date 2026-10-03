-- Animated mini-map of a track, drawn from the same track data the race
-- uses: the road as a ribbon on a little plate in a ViewportFrame, slowly
-- turning, with a glowing kart dot running laps. Used on the vote cards and
-- the chamber's wall screen in place of uploaded track images.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Track = require(Shared:WaitForChild("Track"))
local Tracks = require(Shared:WaitForChild("Tracks"))

local TrackPreview = {}

local FIT = 40 -- the track is scaled to fit a plate this many studs across
local built: { [string]: any } = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

export type Preview = {
	frame: ViewportFrame,
	trackId: string,
	step: (self: Preview, t: number) -> (),
	destroy: (self: Preview) -> (),
}

-- Fills `parent` with a preview of `trackId`. Call :step(time) every frame.
function TrackPreview.new(parent: GuiObject, trackId: string): Preview
	local def = Tracks.get(trackId)
	local theme = Tracks.Themes[def.theme] or Tracks.Themes.hq
	local track = built[trackId]
	if not track then
		track = Track.build(def)
		built[trackId] = track
	end

	-- Fit the layout onto the plate.
	local minX, maxX, minZ, maxZ, minY = math.huge, -math.huge, math.huge, -math.huge, math.huge
	for _, p in track.points do
		minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
		minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
		minY = math.min(minY, p.y)
	end
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local s = FIT / math.max(maxX - minX, maxZ - minZ, 1)
	local function map(p: Track.Vec): Vector3
		-- Hills are exaggerated a little so they read at this size.
		return Vector3.new((p.x - cx) * s, (p.y - minY) * s * 1.6 + 0.4, (p.z - cz) * s)
	end

	local frame = Instance.new("ViewportFrame")
	frame.Name = "TrackPreview"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = rgb(theme.ground):Lerp(Color3.fromRGB(10, 14, 30), 0.55)
	frame.BorderSizePixel = 0
	frame.Ambient = Color3.fromRGB(170, 175, 195)
	frame.LightColor = Color3.fromRGB(255, 250, 240)
	frame.LightDirection = Vector3.new(-1, -2, -0.6)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local model = Instance.new("Model")
	model.Parent = frame
	local plate = part(model, Vector3.new(0.8, FIT + 10, FIT + 10), CFrame.new(0, -0.4, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(theme.ground))
	plate.Shape = Enum.PartType.Cylinder
	local rim = part(model, Vector3.new(0.6, FIT + 11, FIT + 11), CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(theme.accent), true)
	rim.Shape = Enum.PartType.Cylinder

	-- Road ribbon (about 90 pieces) with a thin edge colour underneath.
	local roadWidth = math.max(1.4, (def.width or 30) * s)
	local n = #track.points
	local stride = math.max(1, math.floor(n / 90))
	for i = 1, n, stride do
		local a = map(track.points[i])
		local b = map(track.points[(i + stride - 1) % n + 1])
		local length = (b - a).Magnitude
		if length > 0.01 then
			local cf = CFrame.lookAt((a + b) / 2, b)
			part(model, Vector3.new(roadWidth, 0.4, length + roadWidth * 0.35), cf, rgb(theme.road))
			part(model, Vector3.new(roadWidth + 0.6, 0.3, length + roadWidth * 0.35), cf * CFrame.new(0, -0.12, 0), rgb(theme.wall))
		end
	end
	-- Start line and the running kart.
	local p0, t0 = Track.at(track, 0)
	local start = map(p0)
	part(model, Vector3.new(roadWidth, 0.45, 0.5), CFrame.lookAt(start, start + Vector3.new(t0.x, 0, t0.z)) * CFrame.new(0, 0.05, 0), Color3.new(1, 1, 1))
	local dot = part(model, Vector3.one * math.max(1.4, roadWidth * 0.8), CFrame.new(start), rgb(theme.accent), true)
	dot.Shape = Enum.PartType.Ball

	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.Parent = frame
	frame.CurrentCamera = camera
	frame.Parent = parent

	local lapSeconds = 9
	local offset = math.random() * 10 -- previews side by side don't move in step
	local preview = {
		frame = frame,
		trackId = trackId,
	} :: any

	function preview.step(_self: Preview, t: number)
		local time = t + offset
		local d = (time / lapSeconds % 1) * track.length
		local p = Track.at(track, d)
		dot.CFrame = CFrame.new(map(p) + Vector3.new(0, 0.7, 0))
		local a = time * 0.18
		camera.CFrame = CFrame.lookAt(Vector3.new(math.sin(a) * 58, 46, math.cos(a) * 58), Vector3.new(0, -2, 0))
	end

	function preview.destroy(_self: Preview)
		frame:Destroy()
	end

	preview:step(0)
	return preview
end

return TrackPreview
