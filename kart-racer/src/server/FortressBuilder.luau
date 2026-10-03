-- Original fortress course dressing. Masonry and lava stay outside the
-- drivable ribbon; arches leave a wide, camera-friendly clearance.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Track = require(ReplicatedStorage.Shared.Track)
local Shapes = require(ReplicatedStorage.Common.Shapes)
local FortressBuilder = {}
local stone = Color3.fromRGB(86, 79, 76)
local trim = Color3.fromRGB(145, 127, 105)
local dark = Color3.fromRGB(39, 34, 38)
local ember = Color3.fromRGB(245, 121, 39)
local function box(parent, size, cf, color, name, material)
 return Shapes.box(parent, size, cf, { color = color, material = material or Enum.Material.Cobblestone, name = name, collide = false })
end
function FortressBuilder.build(track, parent)
 local folder = Instance.new("Folder")
 folder.Name = "Citadel"
 folder.Parent = parent
 local half = track.def.width / 2
 for i = 0, 39 do
  local d = track.length * i / 40
  local p, tan = Track.at(track, d)
  local cf = CFrame.lookAt(Vector3.new(p.x, p.y, p.z), Vector3.new(p.x + tan.x, p.y, p.z + tan.z))
  for _, side in { -1, 1 } do
   -- Raised parapets and shallow lava canals outside the guard wall.
   box(folder, Vector3.new(8, 5, 24), cf * CFrame.new(side * (half + 12), 1, 0), stone, "Parapet")
   box(folder, Vector3.new(22, 0.5, 40), cf * CFrame.new(side * (half + 28), -3, 0), ember, "LavaCanal", Enum.Material.Neon)
   for k = -1, 1 do
    box(folder, Vector3.new(1.2, 0.12, 30), cf * CFrame.new(side * (half + 28) + k * 6, -2.65, 0), Color3.fromRGB(255, 177, 67), "LavaVein", Enum.Material.Neon)
   end
   if i % 4 == 0 then
    local torchCf = cf * CFrame.new(side * (half + 13), 6, 0)
    local torch = box(folder, Vector3.new(1, 4, 1), torchCf, dark, "Torch", Enum.Material.Metal)
    Shapes.ellipsoid(folder, Vector3.new(1.4, 2.6, 1.4), torchCf * CFrame.new(0, 3, 0), { color = ember, material = Enum.Material.Neon, name = "Flame" })
    local light = Instance.new("PointLight")
    light.Color = ember
    light.Range = 32
    light.Brightness = 0.8
    light.Parent = torch
   end
  end
 end
 for index, fraction in { 0.055, 0.29, 0.58, 0.89 } do
  local p, tan = Track.at(track, fraction * track.length)
  local cf = CFrame.lookAt(Vector3.new(p.x, p.y, p.z), Vector3.new(p.x + tan.x, p.y, p.z + tan.z))
  for _, side in { -1, 1 } do
   local towerCf = cf * CFrame.new(side * (half + 20), 0, 0)
   Shapes.pillar(folder, 22, 52, towerCf * CFrame.new(0, 26, 0), { color = stone, material = Enum.Material.Cobblestone, name = "GateTower" })
   Shapes.pillar(folder, 25, 3, towerCf * CFrame.new(0, 48, 0), { color = trim, material = Enum.Material.Slate })
   for k = 0, 7 do
    local angle = k * math.pi / 4
    box(folder, Vector3.new(4, 5, 4), towerCf * CFrame.new(math.cos(angle) * 10, 53, math.sin(angle) * 10), stone, "Battlement")
   end
   for y = 10, 40, 10 do
    box(folder, Vector3.new(2, 4, 0.3), towerCf * CFrame.new(0, y, -11.1), dark, "ArrowSlit", Enum.Material.Slate)
   end
  end
  Shapes.arch(folder, track.def.width + 16, 4, 8, cf * CFrame.new(0, 17, 0), { color = trim, material = Enum.Material.Cobblestone, name = "StoneArch" }, 20)
  box(folder, Vector3.new(track.def.width + 26, 7, 10), cf * CFrame.new(0, 51, 0), stone, "GateLintel")
  -- Clear road below; hanging crest is high above drivers and camera.
  Shapes.ellipsoid(folder, Vector3.new(9, 11, 2), cf * CFrame.new(0, 48, -6), { color = trim, material = Enum.Material.Metal, name = "CitadelCrest" })
 end
 -- Continuous outer curtain wall connects the gates into a fortress instead
 -- of leaving towers as isolated props. The inner lane stays open to lava.
 for i = 0, 63 do
  local a = Track.spot(track, i / 64 * track.length, -(half + 70))
  local b = Track.spot(track, ((i + 1) % 64) / 64 * track.length, -(half + 70))
  local av, bv = Vector3.new(a.x, a.y, a.z), Vector3.new(b.x, b.y, b.z)
  local cf = CFrame.lookAt((av + bv) / 2, bv)
  local length = (bv - av).Magnitude
  box(folder, Vector3.new(5, 24, length + 0.5), cf * CFrame.new(0, 12, 0), stone, "CurtainWall")
  box(folder, Vector3.new(6, 1.5, length + 0.5), cf * CFrame.new(0, 24, 0), trim, "WallCap", Enum.Material.Slate)
  for k = -1, 1 do
   box(folder, Vector3.new(5, 3, 4), cf * CFrame.new(0, 26, k * length / 3), stone, "WallCrenel")
  end
 end
 -- Distant basalt spires give depth without filling the road with obstacles.
 for i = 0, 23 do
  local p, tan = Track.at(track, i / 24 * track.length)
  local side = if i % 2 == 0 then 1 else -1
  local spot = Track.spot(track, i / 24 * track.length, side * (half + 150))
  local cf = CFrame.new(spot.x, p.y + 35, spot.z) * CFrame.Angles(0.06, i, -0.08)
  Shapes.ellipsoid(folder, Vector3.new(45, 95 + i % 4 * 15, 40), cf, { color = dark, material = Enum.Material.Basalt, name = "BasaltSpire" })
 end
end
return FortressBuilder
