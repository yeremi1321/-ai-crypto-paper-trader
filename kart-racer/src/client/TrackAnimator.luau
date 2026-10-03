-- Animates the current track on this client: crossers (toy robot, toy train,
-- beetles) walk across the road, sprinklers spray while their wet zone is
-- on, and wet patches only show while they are slippery. Everything is
-- computed from the shared server clock (Track.crosserAt / Track.zoneActive),
-- so what you see matches what the server uses for hits.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Track = require(Shared:WaitForChild("Track"))
local Tracks = require(Shared:WaitForChild("Tracks"))

local TrackAnimator = {}

local current: { folder: Instance, track: Track.Built, sprinklers: { { emitter: ParticleEmitter, zone: any } }, patches: { { part: BasePart, zone: any } } }? = nil

local function setup(folder: Instance)
	local id = folder:GetAttribute("TrackId")
	if type(id) ~= "string" then
		return nil
	end
	local ok, def = pcall(Tracks.get, id)
	if not ok then
		return nil
	end
	local track = Track.build(def)

	-- Pair each sprinkler with the nearest slippery zone.
	local zones = {}
	for _, z in def.zones or {} do
		if z.kind == "slippery" then
			local p = Track.spot(track, z.t * track.length, 0)
			table.insert(zones, { zone = z, pos = Vector3.new(p.x, p.y, p.z) })
		end
	end
	local sprinklers = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Name == "Water" and d.Parent and d.Parent:IsA("BasePart") then
			local best, bestDist = nil, math.huge
			for _, z in zones do
				local dist = ((d.Parent :: BasePart).Position - z.pos).Magnitude
				if dist < bestDist then
					best, bestDist = z.zone, dist
				end
			end
			if best then
				table.insert(sprinklers, { emitter = d, zone = best })
			end
		end
	end
	local patches = {}
	for _, d in folder:GetDescendants() do
		local zi = d:GetAttribute("ZoneIndex")
		if zi and d:IsA("BasePart") then
			local zone = (def.zones :: any)[zi]
			if zone and zone.period then
				table.insert(patches, { part = d, zone = zone })
			end
		end
	end
	return { folder = folder, track = track, sprinklers = sprinklers, patches = patches }
end

function TrackAnimator.step()
	local folder = Workspace:FindFirstChild("Track")
	if not folder then
		current = nil
		return
	end
	if not current or current.folder ~= folder then
		current = setup(folder)
		if not current then
			return
		end
	end
	local c = current :: any
	local t = Workspace:GetServerTimeNow()
	local def = c.track.def

	local crossers = folder:FindFirstChild("Crossers")
	if crossers then
		for _, model in crossers:GetChildren() do
			local index = model:GetAttribute("CrosserIndex")
			local cr = index and (def.crossers :: any)[index]
			if cr and model:IsA("Model") then
				local d, lat = Track.crosserAt(c.track, cr, t)
				local _, latAhead = Track.crosserAt(c.track, cr, t + 0.1)
				local p = Track.spot(c.track, d, lat)
				local _, tan = Track.at(c.track, d)
				-- Face the way it is walking (across the road).
				local right = Vector3.new(-tan.z, 0, tan.x).Unit
				local facing = if latAhead >= lat then right else -right
				local bob = math.abs(math.sin(t * 8)) * (if cr.kind == "beetle" then 0.6 else 0.3)
				local pos = Vector3.new(p.x, p.y + bob, p.z)
				model:PivotTo(CFrame.lookAt(pos, pos + facing))
			end
		end
	end

	for _, s in c.sprinklers do
		s.emitter.Enabled = Track.zoneActive(s.zone, t)
	end
	for _, p in c.patches do
		p.part.Transparency = if Track.zoneActive(p.zone, t) then 0.25 else 0.85
	end
end

return TrackAnimator
