-- Studio-made assets the game picks up by name, so the world can be upgraded
-- in Studio without touching code. Everything is optional: with nothing set
-- up, the game uses its built-in shapes, materials and silence.
--
--   ReplicatedStorage
--     KartAssets
--       Trees, Pines, Rocks, Bushes, FarTrees
--           Models (e.g. low-poly meshes brought in with Import 3D). Any
--           number per folder; each prop picks one, scaled, turned and
--           leaned a little so forests don't repeat. Optional attribute
--           `Scale` on a model sets its base size.
--       Sounds
--           Sound objects named Wind, Water, Birds, Engine, LobbyAmbience.
--       Sky
--           A Sky object (a custom skybox) used on every track.
--   MaterialService
--       MaterialVariants named in Assets.Variants (KartAsphalt, KartGrass, …)
--       replace the built-in look of roads, verges, barriers and props. Each
--       must use the base material listed beside its name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = {}

Assets.FolderName = "KartAssets"

-- Scenery prop kind → asset folder.
Assets.PropFolders = {
	tree = "Trees",
	pine = "Pines",
	rock = "Rocks",
	bush = "Bushes",
	farTree = "FarTrees", -- keep these very low-poly: hundreds are placed
}

-- Surface → MaterialVariant name (and the base material it must use).
Assets.Variants = {
	asphalt = { name = "KartAsphalt", base = "Asphalt" },
	concrete = { name = "KartConcrete", base = "Concrete" },
	grass = { name = "KartGrass", base = "Grass" },
	sand = { name = "KartSand", base = "Sand" },
	gravel = { name = "KartGravel", base = "Pebble" },
	ground = { name = "KartDirt", base = "Ground" },
	slate = { name = "KartStone", base = "Slate" },
}

local function folder(name: string): Instance?
	local root = ReplicatedStorage:FindFirstChild(Assets.FolderName)
	return root and root:FindFirstChild(name)
end

-- The models available for a prop kind (empty when none were added).
function Assets.models(kind: string): { Model }
	local out = {}
	local name = Assets.PropFolders[kind]
	local f = name and folder(name)
	if f then
		for _, m in f:GetChildren() do
			if m:IsA("Model") then
				table.insert(out, m)
			end
		end
	end
	return out
end

-- The MaterialVariant name to use for a part made of `material`, if one was
-- set up in MaterialService with the matching base material.
function Assets.variantFor(material: Enum.Material): string?
	local ok, service = pcall(function()
		return game:GetService("MaterialService")
	end)
	if not ok or not service then
		return nil
	end
	for _, v in Assets.Variants do
		if v.base == material.Name then
			local variant = service:FindFirstChild(v.name)
			if variant and variant:IsA("MaterialVariant") and variant.BaseMaterial == material then
				return v.name
			end
		end
	end
	return nil
end

-- A copy of a sound from KartAssets.Sounds, or nil.
function Assets.sound(name: string): Sound?
	local f = folder("Sounds")
	local s = f and f:FindFirstChild(name)
	if s and s:IsA("Sound") then
		return s:Clone()
	end
	return nil
end

-- A copy of the custom Sky, or nil.
function Assets.sky(): Sky?
	local root = ReplicatedStorage:FindFirstChild(Assets.FolderName)
	local s = root and root:FindFirstChild("Sky")
	if s and s:IsA("Sky") then
		return s:Clone()
	end
	return nil
end

-- Places a copy of one of this kind's models standing on (x, y, z), scaled
-- by prop.size, turned by prop.yaw and leaned slightly. Returns nil when the
-- kind has no models. Works part by part (no PivotTo), so the smoke test can
-- run it too.
function Assets.placeProp(prop: any, parent: Instance, shadows: boolean): Model?
	local list = Assets.models(prop.kind)
	if #list == 0 then
		return nil
	end
	local seed = math.abs(math.floor(prop.x * 13 + prop.z * 7))
	local source = list[seed % #list + 1]
	local model = source:Clone()
	local parts: { BasePart } = {}
	local minY, minX, maxX, minZ, maxZ = math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			local p, s = d.CFrame.Position, d.Size
			minY = math.min(minY, p.Y - s.Y / 2)
			minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
			minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
		end
	end
	if #parts == 0 then
		model:Destroy()
		return nil
	end
	local scale = prop.size * (source:GetAttribute("Scale") or 1)
	-- The model's own bottom-centre goes to the prop's spot.
	local origin = CFrame.new((minX + maxX) / 2, minY, (minZ + maxZ) / 2)
	local lean = CFrame.Angles(((seed % 7) - 3) * 0.012, 0, ((seed % 5) - 2) * 0.015)
	local target = CFrame.new(prop.x, prop.y, prop.z) * CFrame.Angles(0, prop.yaw, 0) * lean
	-- A small brightness shift per copy, so a forest isn't one colour.
	local shade = 1 + ((seed % 9) - 4) * 0.025
	for _, part in parts do
		local rel = origin:ToObjectSpace(part.CFrame)
		part.CFrame = target * CFrame.new(rel.Position * scale) * (rel - rel.Position)
		part.Size = part.Size * scale
		part.Anchored = true
		-- Clutter rule: scenery never collides with or snags a kart.
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = shadows
		if not part:FindFirstChildOfClass("SurfaceAppearance") then
			local c = part.Color
			part.Color = Color3.new(math.clamp(c.R * shade, 0, 1), math.clamp(c.G * shade, 0, 1), math.clamp(c.B * shade, 0, 1))
		end
		local mesh = part:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			mesh.Offset = mesh.Offset * scale
			if mesh.MeshType == Enum.MeshType.FileMesh then
				mesh.Scale = mesh.Scale * scale
			end
		end
	end
	model.Parent = parent
	return model
end

return Assets
