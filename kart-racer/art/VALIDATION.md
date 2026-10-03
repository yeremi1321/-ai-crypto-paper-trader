# Asset pack validation

Checked in the cloud Linux workspace with Lune 0.10.5, Rojo 7.7.1 and
headless Blender 4.0.2 (Ubuntu package; blender.org download was denied).
Starting branch commit: `8eb64bd`.

- `lune run tests/run`: 93 passed, 0 failed.
- `lune run tests/syntax`: all project Luau files compiled.
- `lune run tests/smoke`: all checks passed, including mock imported scenery,
  materials/sounds, saved/generated land and imported car hooks.
- `rojo build . -o KartRacer.rbxlx`: succeeded with KartAssets folders.
- `build_assets.py`: generated and rendered 18 original models. Assertions
  verified triangle budgets, four wheel names and car dimensions.
- `verify_exports.py`: reimported all 18 FBXs in Blender. Triangle counts
  matched; nature origins, wheel names, paint/accent names and custom engine
  properties survived export.
- Inspected both labelled contact sheets, Thunder and leafy-tree renders.
  Geometry is deliberately low-poly with simple materials.

Not checked: Studio import scale/orientation, Roblox rendering, Output
errors, terrain grass clearance/load times, physics, avatar fit, real wheel
animation, paint changes, multiplayer, mobile performance or audio playback.
Lune uses doubles and cannot verify those Roblox behaviours.
No Windows PC or Roblox Studio connection was available. No third-party
assets were imported and no game publication or account settings changed.

## Detailed revision

The game checks were repeated successfully after the art revision. Previews
are 1080×1080; car budgets are 8,348–9,012 triangles, pine budgets 1,412,
leafy tree budgets 1,256 and rock budgets 320. Distant trees stay below 300.
The export verifier also checks imported car dimensions and triangle caps.
The same Studio limitations above still apply. No new gameplay mechanics
are implied by the added visual instruments, lights, brakes or engine details.
