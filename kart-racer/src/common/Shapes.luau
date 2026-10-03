-- Rounded building blocks for a smooth cartoon look without imported meshes:
-- ellipsoids (stretched spheres), discs, capsules and rounded boxes. Every
-- shape is one or a few anchored parts with smooth plastic.
--
-- Ellipsoids use a SpecialMesh sphere, which stretches to the part's size.
-- These are stand-ins: custom MeshParts made in Blender look better and can
-- replace any of them later.

local Shapes = {}

export type Style = {
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	collide: boolean?,
	anchored: boolean?,
	name: string?,
}

local function apply(p: BasePart, style: Style, parent: Instance?)
	p.Name = style.name or p.Name
	p.Anchored = if style.anchored == nil then true else style.anchored
	p.CanCollide = style.collide == true
	p.CanQuery = style.collide == true
	p.CanTouch = false
	p.Color = style.color
	p.Material = style.material or Enum.Material.SmoothPlastic
	p.Transparency = style.transparency or 0
	p.Reflectance = style.reflectance or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if parent then
		p.Parent = parent
	end
end

function Shapes.box(parent: Instance?, size: Vector3, cf: CFrame, style: Style): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	apply(p, style, parent)
	return p
end

function Shapes.ball(parent: Instance?, diameter: number, cf: CFrame, style: Style): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * diameter
	p.CFrame = cf
	apply(p, style, parent)
	return p
end

-- A stretched sphere filling `size`.
function Shapes.ellipsoid(parent: Instance?, size: Vector3, cf: CFrame, style: Style): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	apply(p, style, parent)
	return p
end

-- A cylinder standing upright (height along y).
function Shapes.pillar(parent: Instance?, diameter: number, height: number, cf: CFrame, style: Style): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, diameter, diameter)
	p.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	apply(p, style, parent)
	return p
end

-- A flat round disc lying on the ground (thickness along y).
function Shapes.disc(parent: Instance?, diameter: number, thickness: number, cf: CFrame, style: Style): Part
	return Shapes.pillar(parent, diameter, thickness, cf, style)
end

-- A cylinder lying along local x (wheels, pipes, logs).
function Shapes.tube(parent: Instance?, diameter: number, length: number, cf: CFrame, style: Style): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, diameter, diameter)
	p.CFrame = cf
	apply(p, style, parent)
	return p
end

-- Upright capsule: a pillar with ball ends.
function Shapes.capsule(parent: Instance?, diameter: number, height: number, cf: CFrame, style: Style): { Part }
	local body = math.max(height - diameter, 0.05)
	return {
		Shapes.pillar(parent, diameter, body, cf, style),
		Shapes.ball(parent, diameter, cf * CFrame.new(0, body / 2, 0), style),
		Shapes.ball(parent, diameter, cf * CFrame.new(0, -body / 2, 0), style),
	}
end

-- A box with rounded vertical edges (four corner cylinders and two inner
-- boxes). Good for buildings, signs and counters.
function Shapes.roundedBox(parent: Instance?, size: Vector3, radius: number, cf: CFrame, style: Style): { Part }
	local r = math.min(radius, size.X / 2, size.Z / 2)
	local parts = {
		Shapes.box(parent, Vector3.new(size.X - r * 2, size.Y, size.Z), cf, style),
		Shapes.box(parent, Vector3.new(size.X, size.Y, size.Z - r * 2), cf, style),
	}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(parts, Shapes.pillar(parent, r * 2, size.Y, cf * CFrame.new(sx * (size.X / 2 - r), 0, sz * (size.Z / 2 - r)), style))
		end
	end
	return parts
end

-- A semicircular arch made of short segments (tunnels, doors, gates).
function Shapes.arch(parent: Instance?, span: number, thickness: number, depth: number, cf: CFrame, style: Style, segments: number?): { Part }
	local n = segments or 12
	local radius = span / 2
	local parts = {}
	for i = 0, n - 1 do
		local a0 = math.pi * i / n
		local a1 = math.pi * (i + 1) / n
		local mid = (a0 + a1) / 2
		local len = 2 * radius * math.sin((a1 - a0) / 2) + thickness * 0.3
		local pos = CFrame.new(math.cos(mid) * radius, math.sin(mid) * radius, 0)
		table.insert(parts, Shapes.box(parent, Vector3.new(len, thickness, depth), cf * pos * CFrame.Angles(0, 0, mid - math.pi / 2), style))
	end
	return parts
end

return Shapes
