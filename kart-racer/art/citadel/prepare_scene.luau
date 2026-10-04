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
 {name = "Bridge_Iron_1", position = Vector3.new(557.768539, 53.232569, -29.803772), size = Vector3.new(174.503571, 57.272015, 397.489288), material = "Iron"},
 {name = "Bridge_Timber_1", position = Vector3.new(557.833969, 58.753304, -40.762657), size = Vector3.new(175.761993, 47.703247, 375.412704), material = "Timber"},
 {name = "Bridge_CitadelStone_1", position = Vector3.new(586.270599, 36.934288, -41.444733), size = Vector3.new(135.444031, 109.868576, 385.902100), material = "CitadelStone"},
 {name = "Bridge_SandstoneTrim_1", position = Vector3.new(586.563080, 86.384666, -41.152214), size = Vector3.new(138.134949, 13.967819, 388.593033), material = "SandstoneTrim"},
 {name = "Enclosure_Basalt_1", position = Vector3.new(309.769928, 53.367676, -314.509621), size = Vector3.new(1176.794983, 274.621063, 741.834763), material = "Basalt"},
 {name = "Enclosure_Basalt_2", position = Vector3.new(305.268753, 51.915344, 307.228222), size = Vector3.new(1166.958710, 247.567108, 675.252052), material = "Basalt"},
 {name = "Enclosure_CitadelStone_1", position = Vector3.new(310.000000, 104.388798, -20.000015), size = Vector3.new(1060.000000, 42.882790, 1041.910004), material = "CitadelStone"},
 {name = "Enclosure_SandstoneTrim_1", position = Vector3.new(310.000000, 118.388798, -20.000015), size = Vector3.new(1064.000000, 16.882790, 1045.910004), material = "SandstoneTrim"},
 {name = "Volcano_Basalt_1", position = Vector3.new(320.000000, 94.000000, -74.586864), size = Vector3.new(278.174438, 198.000000, 272.973732), material = "Basalt"},
 {name = "Volcano_Lava_1", position = Vector3.new(321.082336, 91.300002, -45.632956), size = Vector3.new(249.072388, 184.000003, 190.192463), material = "Lava"},
 {name = "Galleries_Basalt_1", position = Vector3.new(136.686596, 42.846046, -44.483047), size = Vector3.new(356.197121, 61.949127, 996.577362), material = "Basalt"},
 {name = "Galleries_SandstoneTrim_1", position = Vector3.new(138.277157, 42.411592, -41.523041), size = Vector3.new(356.459114, 63.083294, 987.322571), material = "SandstoneTrim"},
 {name = "Galleries_Iron_1", position = Vector3.new(138.352898, 28.665200, -41.273163), size = Vector3.new(351.441971, 7.590513, 981.957336), material = "Iron"},
 {name = "Galleries_Flame_1", position = Vector3.new(138.352896, 32.165200, -41.273193), size = Vector3.new(352.241962, 4.590513, 982.757324), material = "Flame"},
 {name = "Props_Timber_1", position = Vector3.new(298.829758, 32.704016, -64.014404), size = Vector3.new(775.818878, 37.627048, 1080.628052), material = "Timber"},
 {name = "Props_Iron_1", position = Vector3.new(298.789650, 40.233263, -63.784271), size = Vector3.new(776.099045, 52.568540, 1080.671570), material = "Iron"},
 {name = "Props_Ash_1", position = Vector3.new(241.942608, 26.169356, -304.928121), size = Vector3.new(664.466225, 25.806276, 604.949544), material = "Ash"},
 {name = "Props_Ash_2", position = Vector3.new(353.281860, 28.686657, 9.975845), size = Vector3.new(649.036987, 31.013031, 919.630341), material = "Ash"},
 {name = "Props_Ash_3", position = Vector3.new(-6.395741, 15.372646, 130.659416), size = Vector3.new(177.497490, 3.361099, 71.494827), material = "Ash"},
 {name = "Props_Burgundy_1", position = Vector3.new(276.275528, 46.733263, -66.373550), size = Vector3.new(422.828766, 37.568539, 789.035065), material = "Burgundy"},
 {name = "Props_Gold_1", position = Vector3.new(275.746162, 46.733265, -66.035599), size = Vector3.new(421.504135, 31.568542, 788.165924), material = "Gold"},
 {name = "Props_CitadelStone_1", position = Vector3.new(293.492764, 29.233265, -71.317093), size = Vector3.new(426.614632, 30.568542, 793.486053), material = "CitadelStone"},
 {name = "Props_Flame_1", position = Vector3.new(293.492756, 33.733265, -71.317093), size = Vector3.new(424.418846, 29.568542, 791.486053), material = "Flame"},
 {name = "TempleDistrict_Basalt_1", position = Vector3.new(290.000000, 4.000000, -100.000000), size = Vector3.new(352.000000, 12.000000, 542.000000), material = "Basalt"},
 {name = "TempleDistrict_CitadelStone_1", position = Vector3.new(290.000000, 42.500000, -100.000000), size = Vector3.new(338.000000, 75.000000, 530.000000), material = "CitadelStone"},
 {name = "TempleDistrict_SandstoneTrim_1", position = Vector3.new(290.000000, 43.250000, -84.250000), size = Vector3.new(320.000000, 77.500000, 541.500000), material = "SandstoneTrim"},
 {name = "TempleDistrict_Iron_1", position = Vector3.new(290.000000, 22.000000, -82.500000), size = Vector3.new(311.000000, 12.000000, 481.000000), material = "Iron"},
 {name = "TempleDistrict_Flame_1", position = Vector3.new(290.000000, 21.000000, -81.800003), size = Vector3.new(308.000000, 7.000000, 480.399994), material = "Flame"},
 {name = "TempleDistrict_Timber_1", position = Vector3.new(290.484833, 10.000000, -127.000000), size = Vector3.new(347.969666, 10.000000, 488.678650), material = "Timber"},
 {name = "Gantries_Iron_1", position = Vector3.new(262.370026, 53.687122, -77.370117), size = Vector3.new(637.521545, 78.574242, 833.162964), material = "Iron"},
 {name = "Gantries_Flame_1", position = Vector3.new(265.392638, 69.537121, -75.349823), size = Vector3.new(582.824831, 22.274239, 790.657043), material = "Flame"},
 {name = "Jungle_Timber_1", position = Vector3.new(312.993790, 72.755860, -51.292755), size = Vector3.new(1023.925751, 136.370482, 1217.032532), material = "Timber"},
 {name = "Jungle_LeafTips_1", position = Vector3.new(304.225769, 45.722919, -64.916382), size = Vector3.new(896.353760, 65.686348, 1204.185303), material = "LeafTips"},
 {name = "Jungle_LeafTips_2", position = Vector3.new(312.693207, 77.755342, -20.289673), size = Vector3.new(1055.600403, 129.729702, 1186.321899), material = "LeafTips"},
 {name = "Jungle_JungleLeaf_1", position = Vector3.new(312.693192, 81.845516, -52.156555), size = Vector3.new(1045.642059, 121.549355, 1240.097290), material = "JungleLeaf"},
}
local parts = {}
for _, row in rows do
 local part = source:FindFirstChild(row.name, true)
 assert(part and part:IsA("MeshPart"), "Missing mesh: " .. row.name .. "; no changes applied")
 parts[row.name] = part
end
local materials = { CitadelStone = Enum.Material.Cobblestone, SandstoneTrim = Enum.Material.Sandstone, Basalt = Enum.Material.Basalt, Iron = Enum.Material.Metal, Gold = Enum.Material.Metal, Lava = Enum.Material.Neon, Flame = Enum.Material.Neon, Timber = Enum.Material.Wood, Burgundy = Enum.Material.Fabric, Ash = Enum.Material.Slate, JungleLeaf = Enum.Material.Grass, LeafTips = Enum.Material.Grass }
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
local oldLights = source:FindFirstChild("CaveLights")
if oldLights then oldLights:Destroy() end
local caveLights = Instance.new("Folder")
caveLights.Name = "CaveLights"
caveLights.Parent = source
for index, position in {
 Vector3.new(14.635191, 38.191949, -333.594273),
 Vector3.new(45.598891, 37.869133, -398.340554),
 Vector3.new(102.030603, 38.902666, -460.111672),
 Vector3.new(140.344838, 40.116343, -488.940966),
 Vector3.new(284.712160, 37.939711, 402.160497),
 Vector3.new(207.039344, 38.039998, 370.751387),
 Vector3.new(145.571115, 38.376551, 333.357941),
} do
 local node = Instance.new("Part")
 node.Name = "Lamp" .. index
 node.Size = Vector3.new(1, 1, 1)
 node.CFrame = CFrame.new(position)
 node.Transparency = 1
 node.Anchored = true
 node.CanCollide = false
 node.CanTouch = false
 node.CanQuery = false
 node.Parent = caveLights
 local light = Instance.new("PointLight")
 light.Color = Color3.fromRGB(255, 200, 130)
 light.Range = 45
 light.Brightness = 2
 light.Shadows = false
 light.Parent = node
end
print("Citadel meshes normalized to source stud coordinates. Check materials, terrain overlap and camera clearance in Play.")
