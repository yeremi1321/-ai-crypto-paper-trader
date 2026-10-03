-- Shared road edges form a continuous ribbon rather than overlapping slabs.
-- Two wedges per triangle provide native, upload-free geometry and collision.
local RoadRibbon = {}
local function triangle(parent, a, b, c, color, material)
 local ab, ac, bc = b - a, c - a, c - b
 local lengths = { ab:Dot(ab), ac:Dot(ac), bc:Dot(bc) }
 if lengths[1] > lengths[2] and lengths[1] > lengths[3] then
  a, c = c, a
 elseif lengths[2] > lengths[3] then
  a, b = b, a
 end
 ab, ac, bc = b - a, c - a, c - b
 local cross = ac:Cross(ab)
 if cross.Magnitude < 0.001 then return end
 local right = cross.Unit
 local back = bc.Unit
 local up = back:Cross(right).Unit
 local height = math.abs(ab:Dot(up))
 for _, spec in {
  { center = (a + b) / 2, right = right, back = back, length = math.abs(ab:Dot(back)) },
  { center = (a + c) / 2, right = -right, back = -back, length = math.abs(ac:Dot(back)) },
 } do
  if spec.length < 0.001 then continue end
  local wedge = Instance.new("WedgePart")
  wedge.Name = "RoadRibbon"
  wedge.Anchored = true
  wedge.Size = Vector3.new(0.16, height, spec.length)
  wedge.CFrame = CFrame.fromMatrix(spec.center, spec.right, up, spec.back)
  wedge.Color = color
  wedge.Material = material
  wedge.TopSurface = Enum.SurfaceType.Smooth
  wedge.BottomSurface = Enum.SurfaceType.Smooth
  wedge:SetAttribute("Surface", "road")
  wedge.Parent = parent
 end
end
function RoadRibbon.build(track, parent, color, material)
 local points = track.points
 local left, right = {}, {}
 local half = track.def.width / 2
 for i, p in points do
  local prev, nextPoint = points[(i - 2) % #points + 1], points[i % #points + 1]
  local tangent = Vector3.new(nextPoint.x - prev.x, 0, nextPoint.z - prev.z).Unit
  local side = Vector3.new(-tangent.Z, 0, tangent.X)
  local center = Vector3.new(p.x, p.y - 0.12, p.z)
  left[i], right[i] = center - side * half, center + side * half
 end
 for i = 1, #points do
  local j = i % #points + 1
  triangle(parent, left[i], right[i], left[j], color, material)
  triangle(parent, right[i], right[j], left[j], color, material)
 end
end
return RoadRibbon
