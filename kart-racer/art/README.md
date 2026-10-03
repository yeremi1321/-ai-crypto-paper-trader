# Original Blender asset pack

These are original scripted models made for Kart Racer. No external meshes,
textures, real brands or copied car designs are included. Materials are plain
colours; there are no texture downloads or licensing dependencies.

## Rebuild

From `kart-racer/`, run (Blender 4.0 or newer):

```powershell
blender --background --python art/build_assets.py
```

If Blender is not on PATH, use the full path to `blender.exe`. The script
writes each source to `art/blend/`, FBX to `art/fbx/`, and a Cycles render to
`art/previews/`. `manifest.json` reports actual triangles after beveling,
bounds and engine object names; assertions enforce all requested budgets.
Run `blender --background --python art/verify_exports.py` to reimport every
FBX and check triangle counts, bottom placement, wheel names, paint names and
engine properties. `python art/make_review.py` creates labelled review sheets
(Pillow required).

Geometry uses Blender Z up, +Y nose; FBX exports Y up, -Z forward. One model
unit is intended as one stud, but Studio import scaling must be checked.

## Review, then import in Studio

1. Review each render and its triangle count in `manifest.json` first.
2. Open the rebuilt place in Studio, in Edit mode. The project now includes
   `ReplicatedStorage.KartAssets` with Trees, Pines, Rocks, Bushes, FarTrees,
   Sounds and Bodies. Bushes and Sounds are empty intentionally.
3. Import ONE reviewed FBX through Import 3D. Disable combining all meshes
   into one for cars; retain exactly four MeshParts named WheelFL, WheelFR,
   WheelRL, WheelRR. Each wheel includes its tyre, rims and spokes as one mesh.
4. Put the imported Model in the manifest's folder, named exactly as the file
   stem. Tree and rock mesh origins are at bottom centre. Car wheel origins
   are also at the source origin; the game uses each imported MeshPart centre
   for wheel joints. Verify imported geometry bounds, scale, and wheel centres.
5. Preserve Paint... and Accent... names for colour changes. Run
   `prepare_imports.luau` in the Edit-mode command bar to set engine attributes
   explicitly (FBX custom properties may not become Roblox attributes).
6. If needed set numeric Scale or Yaw on the imported Model. Existing car IDs
   retain their built-in price and seating layout. Check driver clearance in
   Play mode; source renders do not verify Roblox avatars or animation.
7. Save the imported assets separately using Rojo-compatible `.rbxm` files
   under a new `kart-racer/assets/` directory and add their paths to the project,
   or save a separate Studio place. Do not rely on imports surviving a fresh
   `rojo build`: the build currently contains empty folders, not uploaded mesh
   IDs. Folder `$ignoreUnknownInstances` preserves manual children during live
   Rojo sync, but does not write them back into source control.

## Studio tests still required

Boot/Output, ready→vote→race→results, grass clearance, Ridgeline load timing,
road seams and overpass headroom, driver seating, wheel spin/steer, recolouring,
engine movement, multiplayer and mobile performance. No Studio instance was
available in the cloud session that generated this pack. No meshes or sounds
have been imported or uploaded, and the game has not been published.

## Creator Store review shortlist (not installed)

Roblox documents Creator Store audio as free to use within experiences:
https://create.roblox.com/docs/audio/assets
Listen and verify access in your experience before deciding which to add.
None of the following has been auditioned in this session.

| Slot | Candidate | Review link |
| --- | --- | --- |
| Wind | Leaves Rustle Wind Blowing Through Trees 1, ProSoundEffects (75.8s) | https://create.roblox.com/store/asset/9116258071 |
| Water | Water Fountain 1, ProSoundEffects (31.5s; fountain, not a river) | https://create.roblox.com/store/asset/9120557412 |
| Birds | Morning Forest Birds 6, ProSoundEffects (75.2s) | https://create.roblox.com/store/asset/9116970949 |
| Engine | Engine Sound Loop 7 (listing describes a seamless 1.927s loop) | https://create.roblox.com/store/asset/6667206432 |
| LobbyAmbience | Server room noise (possible mechanical hum; duration/rights not independently verified) | https://create.roblox.com/store/asset/144130913 |

Optional nature alternative: Stylised Low-Poly Nature Pack:
https://create.roblox.com/store/asset/6503281311
Its listing says free to use with no credit required. Contents, triangle
counts and scripts still need inspection in Studio before adding anything.
The original models in this directory are the primary proposed nature kit.

## Detailed model revision

1080×1080 source previews replace the first rough kit. Cars use sculpted
longitudinal body sections, tyre sidewalls and tread, inset lamp lenses and
housings, open rim centres, brake rotors/calipers, curved wheel arches,
grilles, cooling vents, mirrors, gauges, seat stitching, towing eyes, fuel
caps, rear diffusers and engine pulleys, belts, hoses and headers. V12 and
dragster have rear motors and aero wings; the hauler has a braced cage/light
bar; the rod has a narrower front, larger rear tyres and a chrome hoop.
These are visual details, not new driving or damage mechanics.

Pines now have radial branches, needle clusters and root flares. Leafy trees
have forked branches, irregular smoother foliage and three canopy shapes.
Rocks have different proportions, rounded weathering and mineral/moss material
patches. Distant trees retain the 300-triangle cap. There are no textures to
download; colours and material slots define these surfaces. Roblox import
may need material/SurfaceAppearance setup to preserve the appearance of
multi-material meshes such as wheels; that is not verified by Blender export.

To rebuild only selected models, append their names after `--`, for example:
`blender --background --python art/build_assets.py -- v12 dragster`.
The manifest preserves the other entries and is written after each model.

Static car details are batched by material to reduce the imported MeshPart
count. Four wheels and the animated engine components remain separate. The
manifest includes `mesh_objects`; all refined cars have fewer than 30 mesh
objects. Blender metallic/roughness settings still need checking after Studio
import; they are not a substitute for Roblox SurfaceAppearance setup.
