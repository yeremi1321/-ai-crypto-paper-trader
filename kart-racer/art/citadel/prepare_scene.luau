-- EDIT mode after importing all reviewed map FBXs into KartAssets.Tracks.emberfort.
-- Generated from manifest.json. Correct axes must be verified before running.
local source = game:GetService("ReplicatedStorage"):WaitForChild("KartAssets"):WaitForChild("Tracks"):WaitForChild("emberfort")
local rows = {
 {name = "Landscape_Basalt_1", position = Vector3.new(300.000000, 29.612503, -51.530426), size = Vector3.new(1500.000000, 375.980347, 1453.060852), material = "Basalt"},
 {name = "Landscape_Basalt_2", position = Vector3.new(-149.489037, 32.188393, -53.996307), size = Vector3.new(511.813065, 362.894089, 1314.909241), material = "Basalt"},
 {name = "Landscape_Basalt_3", position = Vector3.new(451.952847, 35.401199, 382.440460), size = Vector3.new(1097.965767, 372.316437, 722.402893), material = "Basalt"},
 {name = "Landscape_Basalt_4", position = Vector3.new(433.393707, 17.243073, -293.095966), size = Vector3.new(1169.155334, 236.613251, 760.821129), material = "Basalt"},
 {name = "Landscape_Basalt_5", position = Vector3.new(297.238922, 3.877666, 270.095047), size = Vector3.new(905.895447, 75.151176, 549.894623), material = "Basalt"},
 {name = "Landscape_Lava_1", position = Vector3.new(301.133163, 18.198694, -65.899582), size = Vector3.new(747.612701, 38.397388, 1073.927277), material = "Lava"},
 {name = "Sector1_CitadelStone_1", position = Vector3.new(-4.988686, 43.650002, -154.111939), size = Vector3.new(118.337479, 72.500000, 333.541563), material = "CitadelStone"},
 {name = "Sector1_SandstoneTrim_1", position = Vector3.new(-4.988686, 46.368690, -154.148478), size = Vector3.new(119.937485, 56.062624, 334.220744), material = "SandstoneTrim"},
 {name = "Sector1_Iron_1", position = Vector3.new(-4.533743, 40.900001, -121.341512), size = Vector3.new(92.937374, 43.000002, 243.761403), material = "Iron"},
 {name = "Sector1_Flame_1", position = Vector3.new(-2.267252, 25.425401, -121.315407), size = Vector3.new(85.914562, 3.654100, 244.391036), material = "Flame"},
 {name = "Sector1_Gold_1", position = Vector3.new(-4.778717, 70.400002, -125.872414), size = Vector3.new(8.051094, 9.000000, 2.264740), material = "Gold"},
 {name = "Sector2_CitadelStone_1", position = Vector3.new(103.718819, 20.248246, -434.870972), size = Vector3.new(274.198227, 12.660773, 273.498779), material = "CitadelStone"},
 {name = "Sector2_SandstoneTrim_1", position = Vector3.new(103.704945, 20.798246, -434.889114), size = Vector3.new(275.018333, 5.810772, 274.317474), material = "SandstoneTrim"},
 {name = "Sector3_CitadelStone_1", position = Vector3.new(378.055023, 53.730095, -486.667480), size = Vector3.new(325.867004, 72.500000, 202.891846), material = "CitadelStone"},
 {name = "Sector3_SandstoneTrim_1", position = Vector3.new(378.101151, 54.147587, -486.881668), size = Vector3.new(326.693939, 60.665016, 204.217499), material = "SandstoneTrim"},
 {name = "Sector3_Iron_1", position = Vector3.new(319.556763, 54.480095, -534.790207), size = Vector3.new(26.743652, 36.000000, 89.177887), material = "Iron"},
 {name = "Sector3_Gold_1", position = Vector3.new(326.225418, 80.480095, -532.662079), size = Vector3.new(4.215790, 9.000000, 8.107727), material = "Gold"},
 {name = "Sector4_CitadelStone_1", position = Vector3.new(539.379166, 43.917845, -323.512680), size = Vector3.new(136.005951, 14.879841, 222.333160), material = "CitadelStone"},
 {name = "Sector4_SandstoneTrim_1", position = Vector3.new(539.354919, 44.467846, -323.547577), size = Vector3.new(136.867065, 8.029839, 223.139526), material = "SandstoneTrim"},
 {name = "Sector5_CitadelStone_1", position = Vector3.new(538.570831, 47.820633, 288.940491), size = Vector3.new(228.698425, 72.500000, 281.750793), material = "CitadelStone"},
 {name = "Sector5_SandstoneTrim_1", position = Vector3.new(538.374619, 56.070633, 289.193993), size = Vector3.new(229.906036, 45.000000, 282.997635), material = "SandstoneTrim"},
 {name = "Sector5_Iron_1", position = Vector3.new(470.588776, 48.570633, 369.944901), size = Vector3.new(42.480652, 36.000000, 82.869781), material = "Iron"},
 {name = "Sector5_Gold_1", position = Vector3.new(464.290588, 74.570633, 372.999893), size = Vector3.new(5.116272, 9.000000, 7.896210), material = "Gold"},
 {name = "Sector6_CitadelStone_1", position = Vector3.new(513.386154, 27.225559, 304.461494), size = Vector3.new(267.493195, 21.534882, 273.898056), material = "CitadelStone"},
 {name = "Sector6_SandstoneTrim_1", position = Vector3.new(513.409882, 27.775558, 304.471672), size = Vector3.new(268.297668, 14.684883, 274.706436), material = "SandstoneTrim"},
 {name = "Sector6_Iron_1", position = Vector3.new(503.904648, 29.292425, 332.332603), size = Vector3.new(223.977692, 15.668613, 207.918411), material = "Iron"},
 {name = "Sector6_Flame_1", position = Vector3.new(503.908127, 32.778055, 332.298386), size = Vector3.new(224.708527, 14.106960, 208.635406), material = "Flame"},
 {name = "Sector7_CitadelStone_1", position = Vector3.new(198.794037, 43.650002, 327.781685), size = Vector3.new(402.973694, 72.500000, 247.083054), material = "CitadelStone"},
 {name = "Sector7_SandstoneTrim_1", position = Vector3.new(198.572172, 46.122474, 327.531395), size = Vector3.new(404.129887, 56.555056, 248.336380), material = "SandstoneTrim"},
 {name = "Sector7_Iron_1", position = Vector3.new(53.575750, 44.400001, 258.168823), size = Vector3.new(69.437824, 36.000002, 61.980896), material = "Iron"},
 {name = "Sector7_Gold_1", position = Vector3.new(48.998386, 70.400002, 252.872810), size = Vector3.new(7.098854, 9.000000, 6.482895), material = "Gold"},
 {name = "Sector8_CitadelStone_1", position = Vector3.new(36.521721, 18.249999, 169.770872), size = Vector3.new(177.054276, 7.699999, 321.286015), material = "CitadelStone"},
 {name = "Sector8_SandstoneTrim_1", position = Vector3.new(36.565138, 18.799999, 169.843793), size = Vector3.new(177.879780, 0.849998, 322.062109), material = "SandstoneTrim"},
 {name = "Bridge_Iron_1", position = Vector3.new(557.833984, 53.600748, -29.803772), size = Vector3.new(175.761963, 58.008373, 397.489288), material = "Iron"},
 {name = "Bridge_CitadelStone_1", position = Vector3.new(586.270599, 36.934288, -41.444733), size = Vector3.new(135.444031, 109.868576, 385.902100), material = "CitadelStone"},
 {name = "Bridge_SandstoneTrim_1", position = Vector3.new(586.563080, 86.384666, -41.152214), size = Vector3.new(138.134949, 13.967819, 388.593033), material = "SandstoneTrim"},
}
local parts = {}
for _, row in rows do
 local part = source:FindFirstChild(row.name, true)
 assert(part and part:IsA("MeshPart"), "Missing mesh: " .. row.name .. "; no changes applied")
 parts[row.name] = part
end
local materials = { CitadelStone = Enum.Material.Cobblestone, SandstoneTrim = Enum.Material.Sandstone, Basalt = Enum.Material.Basalt, Iron = Enum.Material.Metal, Gold = Enum.Material.Metal, Lava = Enum.Material.Neon, Flame = Enum.Material.Neon }
for _, row in rows do
 local part = parts[row.name]
 part.CFrame = CFrame.new(row.position)
 part.Size = row.size
 part.Anchored = true
 part.CanCollide = false
 part.CanTouch = false
 part.CanQuery = false
 part.Material = materials[row.material] or Enum.Material.Slate
 if row.material == "Lava" then part.Color = Color3.fromRGB(205, 72, 18) end
 if row.material == "Flame" then
  part.Color = Color3.fromRGB(255, 152, 55)
  if not part:FindFirstChild("CitadelGlow") then
   local light = Instance.new("PointLight")
   light.Name = "CitadelGlow"
   light.Color = part.Color
   light.Brightness = 0.6
   light.Range = 24
   light.Shadows = false
   light.Parent = part
  end
 end
end
print("Citadel meshes normalized to source stud coordinates. Check materials, terrain overlap and camera clearance in Play.")
