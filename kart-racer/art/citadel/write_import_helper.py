"""Regenerate the Studio normalization helper from the current mesh manifest."""
import json,pathlib
root=pathlib.Path(__file__).resolve().parent
manifest=json.loads((root/'manifest.json').read_text())
header='-- EDIT mode after importing all reviewed map FBXs into KartAssets.Tracks.emberfort.\n-- Generated from manifest.json. Correct axes must be verified before running.\nlocal source = game:GetService("ReplicatedStorage"):WaitForChild("KartAssets"):WaitForChild("Tracks"):WaitForChild("emberfort")\n'
tail='local parts = {}\nfor _, row in rows do\n local part = source:FindFirstChild(row.name, true)\n assert(part and part:IsA("MeshPart"), "Missing mesh: " .. row.name .. "; no changes applied")\n parts[row.name] = part\nend\nlocal materials = { CitadelStone = Enum.Material.Cobblestone, SandstoneTrim = Enum.Material.Sandstone, Basalt = Enum.Material.Basalt, Iron = Enum.Material.Metal, Gold = Enum.Material.Metal, Lava = Enum.Material.Neon, Flame = Enum.Material.Neon }\nfor _, row in rows do\n local part = parts[row.name]\n part.CFrame = CFrame.new(row.position)\n part.Size = row.size\n part.Anchored = true\n part.CanCollide = false\n part.CanTouch = false\n part.CanQuery = false\n part.Material = materials[row.material] or Enum.Material.Slate\n if row.material == "Lava" then part.Color = Color3.fromRGB(205, 72, 18) end\n if row.material == "Flame" then\n  part.Color = Color3.fromRGB(255, 152, 55)\n  if not part:FindFirstChild("CitadelGlow") then\n   local light = Instance.new("PointLight")\n   light.Name = "CitadelGlow"\n   light.Color = part.Color\n   light.Brightness = 0.6\n   light.Range = 24\n   light.Shadows = false\n   light.Parent = part\n  end\n end\nend\nprint("Citadel meshes normalized to source stud coordinates. Check materials, terrain overlap and camera clearance in Play.")\n'
lines=[]
for row in manifest['meshes']:
    position=', '.join(f'{v:.6f}' for v in row['center_roblox'])
    size=', '.join(f'{v:.6f}' for v in row['size_roblox'])
    lines.append(' {name = "'+row['name']+'", position = Vector3.new('+position+'), size = Vector3.new('+size+'), material = "'+row['material']+'"},')
(root/'prepare_scene.luau').write_text(header+'local rows = {\n'+'\n'.join(lines)+'\n}\n'+tail)
