# Emberstone Citadel — original 3D map

The Blender scene follows the existing Emberstone lap exported from the game's
Track/RoadGeometry modules. It includes a continuous preview road, four curved
stone gates, eight battlement towers, lava canals, a central lava basin,
volcanic cliffs and an elevated suspension bridge following the road's bends.
The enclosed jungle revision adds a continuous volcanic cliff amphitheatre,
a central 190-stud volcano with a lava crater and falls,
two roofed cave galleries, temple islands, cliff lookouts, palms, broadleaf trees,
ferns, hanging vines, overhead lantern gantries, banners, braziers, crates,
barrels and rubble. The galleries cover two sections; the rest is an open-roof
jungle valley enclosed by cliffs. This is an original tropical-volcano design.
Original 512px tileable stone, basalt and lava colour textures are included.
No external models, textures, names or franchise assets are used.

## Rebuild

From `kart-racer/`:

```powershell
lune run art/citadel/export_track
blender --background --python art/citadel/build_map.py
blender --background --python art/citadel/verify_map.py
# Rerender selected camera views without rebuilding geometry:
blender --background --python art/citadel/render_previews.py -- starting_gate
```

`EmberstoneCitadel.blend` contains packed textures and the entire scene geometry, including the
preview road. `exports/` contains only scenery: the game keeps its existing
code-generated road collision, checkpoints, items, boosts and ramps. Each
exported scenery mesh is capped at 9,000 triangles. `manifest.json` lists
names, triangle counts, dimensions and expected Roblox-space positions.
The four previews are actual 1920×1080 Blender renders of the scene geometry.

## Review before importing

Review `previews/starting_gate.jpg`, `overview.jpg` `bridge.jpg` and `jungle_gallery.jpg` first.
Then, in Studio Edit mode:

1. Import only FBXs listed in `manifest.json`. Keep the adjacent textures
   directory available. Inspect material/texture transfer in Import 3D;
   Blender bump and emission shaders do not automatically become Roblox PBR
   or lighting. The original colour textures can be uploaded and assigned
   to MeshPart SurfaceAppearance ColorMap slots if needed.
2. Put all scenery MeshParts in a Model named `emberfort` under
   `ReplicatedStorage.KartAssets.Tracks`. Keep the generated mesh names.
3. Run the generated `prepare_scene.luau` through the Edit-mode command bar.
   It validates all expected mesh names before modifying anything, sets
   exact source positions/sizes in studs and cosmetic collision properties,
   and applies sensible Roblox materials. It assumes the FBX axes are
   correctly imported (Y up, front -Z); verify that before running.
4. Press Play and vote for Emberstone. The imported scenery replaces the
   old procedural Citadel decoration. The existing road and race mechanics
   remain active; without an imported Model the old decoration still works.
5. Check that the generated Roblox Terrain does not overlap the imported
   landscape. This integration keeps existing terrain, scenery props, road
   barriers and atmospheric lighting, so the final Studio appearance differs
   from the Blender preview until those are tuned. Sculpt/save terrain with
   StudioTools if needed. Avoid manually moving the mesh-only road shown in
   Blender into the game: that would add duplicate road geometry.
6. Check arches, camera clearance, bridge rails and driving; test at least
   two players and mobile performance. Save imported Models into source
   `.rbxm` files under `kart-racer/assets/` and map them in the Rojo project,
   or save a separate Studio place. A new Rojo build contains empty asset
   folders and will not embed your uploaded meshes automatically.

## Validation limits

Blender export reimport checks validate triangle counts and coordinate bounds.
Lune tests cover the optional imported-scenery path, preserving the native
road and source Model. No Roblox Studio instance was accessible here, so
actual import axes, texture loading, terrain overlap, lighting, collisions,
networking and performance remain unverified. The previews show the Blender
scene, not a screenshot of Roblox gameplay.
