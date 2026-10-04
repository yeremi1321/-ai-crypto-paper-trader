# Kart Racer (Roblox)

A colourful party kart racer: tiny racers in an oversized world. Original
characters, karts, items and tracks.

## Run it

**Easiest:** open `KartRacer.rbxlx` in Roblox Studio and press Play. It's a
snapshot built from `src/` (`rojo build . -o KartRacer.rbxlx`), so rebuild it
after changing code.

**For development:** install [Rojo](https://rojo.space) and its Studio plugin,
run `rojo serve` here, and connect from Studio.

To test saving in Studio, turn on *Game Settings → Security → Enable Studio
Access to API Services*. Without it the game runs, but progress isn't saved,
and you're told so.

## How a round works

**Lobby** → **ready up** (button or the READY arch) → **map voting** (20s, three
tracks plus Random, use pads or cards, change your vote any time, ties are random) →
**race** on the starting grid with a 3-2-1-GO countdown → **results** with coins
and awards → **back to the lobby**.

- Only players who ready up race and vote. Everyone else can explore, practise
  or watch.
- CPU drivers fill empty spots, so one player can race alone.
- Late joiners spawn in the lobby and can watch or ready up for the next race.
- Finished racers spectate the rest. Once the first player finishes, the others
  get 30 seconds, so one slow racer can't hold up the round.

## The indoor Kart HQ lobby

- Compact 136 × 156-stud voting chamber with a raised entrance, short stairs,
  side ramps, matte gray-blue finishes, and soft white lighting
- Giant wall screen: cycling animated track previews while waiting; three
  track columns plus Random with counts and voter headshots during voting;
  a full-screen winner reveal; live standings; and the results top three
- Overhead phase/countdown board and four numbered pad signs; stepping onto
  a pad readies you up, and pads/cards choose a track during voting
- Connected garage, trophy room, and party bays. Practice and viewing rooms
  have been removed; spectating remains available through the HUD.
- Proximity sliding doors; departure doors unlock only when the server lights
  them and pulse gold while lit
- Player kart displays, podium celebration, and six hidden golden tokens
- Realistic finish: concrete walls, a dark marble floor, brushed-metal trim,
  fabric banners and glowing light fixtures
- A panoramic window behind spawn looks out over a real terrain lake, pine
  trees, grassy hills and snow-capped mountains under volumetric clouds

`LobbyScreens` draws the six chamber SurfaceGuis in each player's PlayerGui and animates
local doors. Server round state drives all displays; clients do not choose
results or authorize departure. Random votes resolve to one of the three
tracks and count toward that track; the Random column also shows who used it.

Streaming is disabled so the distant lobby and race tracks remain available.
Avatar names are visible within 45 studs, health labels are hidden, and the
walking camera uses Invisicam with an 80-stud maximum zoom.

## Driving

- **Basics:** responsive steering and braking, plus drifting with blue → orange →
  purple mini-turbos.
- **Boosts:** a rocket start, boost pads, slipstreaming behind other karts, and
  ramp tricks (press drift in the air, land for a boost).
- **Feel:** karts lean into turns, dip under braking, bounce on the suspension,
  squash on landing, steer their front wheels and puff exhaust.
- **Recovery:** auto-respawn if you fall off, a reset button (R), and an
  auto-reset if you're stuck.

| Action | Keyboard | Gamepad | Touch |
| --- | --- | --- | --- |
| Gas / brake / steer | W S A D | R2 / L2 / stick | thumbstick (or auto-accelerate) |
| Drift / trick in the air | Space or Shift | R1 | DRIFT |
| Use item (hold S to aim back) | E | X | ITEM |
| Reset kart | R | Y | ↺ |
| Horn | H | D-pad up | |

## Tracks

| Track | Feature |
| --- | --- |
| 🍂 Ridgeline Grand Prix | The big one (5,800 studs, 2 laps): a figure-eight that crosses OVER its own start straight, autumn highlands, a river bridge, rocky tors, two ranges of peaks and three skill shortcuts (quarry cut, ridge gap, riverside dash) |
| 🏔️ Pinewater Pass | Mountain-lake circuit: a long bridge over the water, a climb through pine forest, snow-capped peaks all round |
| 🔥 Emberstone Citadel | Cobblestone gates, stone arches, battlement towers, lava canals, warm torches, basalt spires, raised bridge and ramp |
| 🧸 Midnight Toy Room | Ruler bridge, block ramps, a dash under the bed, toy robot and train crossings, corner shortcut |
| 🍳 Kitchen Chaos | Toaster launch onto a countertop shelf that bridges the start, conveyors, spatula ramps, syrup, cutting-board shortcut |
| 🐞 Backyard Bug Rally | Hose tunnel, flowerpot jumps, crossing beetles, sprinklers that turn the dirt slippery, hollow-log shortcut |
| 🌳 Sunny Loop | Fast countryside corners between grassy hills and two lakes, with snowy mountains on the horizon |
| 🏜️ Canyon Climb | Desert hills on earth banks, banded sandstone mesas, dunes and an oasis |
| 🌃 Neon Eight | Night-city figure-eight with a bridge |

### Realistic tracks

Ridgeline Grand Prix, Pinewater Pass, Sunny Loop, Canyon Climb, Backyard Bug
Rally and Emberstone Citadel are built on **Roblox Terrain**: textured grass, sand, rock and snow,
lakes of real water with sandy shores, hills, mesas and distant mountains.
Raised road sits on earth banks instead of floating, and trees and rocks
stand on the land. Sunny Loop and Canyon Climb are 25% bigger than before
and Pinewater Pass 19%; behind the first ring of mountains there's a second,
hazier range, and a cheap distant forest fills the middle distance. Terrain
always stays 3.5 studs under the 4-stud road and verge slabs, and grass
decoration is enabled; verify grass clearance in Studio and disable it if needed. Lighting adds soft shadows, sky reflections (PBR) and
volumetric clouds. The toy room, kitchen and neon city stay stylised on
purpose.

### Roads

Each road is one continuous cross-section built from the same frames:
- a solid asphalt slab made of triangles, so curves and hills have no gaps,
  steps or flickering overlaps;
- red-and-white curbs on corners, painted edge lines and a dashed centre line;
- grass (or sand) verges out past the barriers, gravel run-off on the outside
  of corners, and a concrete deck on bridges;
- concrete jersey barriers laid end to end, with gaps only for shortcuts.

Road, verge and barrier pieces each span two 12-stud segments and share the
same corner points, which roughly halves the part count without gaps.

Shortcuts are skill-based (narrow gaps in the wall) and can never skip a lap
checkpoint.

## Items

| Item | What it does |
| --- | --- |
| 🚀 Wind-up Rocket | Rolls along the road and pops on the first kart it meets. Racers ahead get a warning. |
| 🍿 Popcorn Bomb | Thrown ahead (or dropped behind). Blinks, then pops. |
| 🍮 Jelly Puddle | Sticky trap that slows whoever drives in |
| 🫧 Bubble Shield | Blocks one attack |
| 🥤 Turbo Soda | Speed boost |
| 🌀 Spring Mine | Trap that boings karts into the air |

Odds depend on your position: more defence at the front, more boosts and
attacks at the back.

Every hit gives a few seconds of protection. Traps expire, and there are limits
on traps per racer and on active hazards.

## Karts

Twenty-three bodies:
- **Big-motor cars** with exposed engines that rumble (harder on the
  throttle), glossy paint, chrome and rubber tyres on six-spoke rims:
  Blower Rod (supercharged hot rod, fat rear tyres), Thunder Muscle (wide
  convertible, blower through the hood, side pipes), Twin-Turbo Dragster
  (long nose, huge slicks, big wing), Dune Hauler (trophy truck with a roll
  cage and light bar) and Midnight V12 (mid-engine speedster, V12 under
  glass). CPU drivers race the realistic cars;
- Ember GT, Arrow Sprint, and Rally Comet: low open cockpits, wide wheels,
  spoilers, grille details, and twin chrome exhausts;
- Classic, Toaster Terror (toast pops up when boosting), Bubble Buggy (bubble
  exhaust), Frog Hopper (blinking headlight eyes), UFO Cruiser (orbiting
  lights), Dragon Hatchling (flapping wings), Sneaker Speeder (fluttering
  laces), Crab Cab (snipping claws), Jelly Racer (wobbles), Cardboard Champion
  (marker drawings) and Dumpster Rocket (rattling lid);
- plus the earlier Wedge Racer, Dune Buggy, Muscle and Formula.

Bodies are looks only. Three engine types (Zippy, Classic, Brute) set the stats,
and they're balanced against each other.

## Progression

- **Coins** for every race, plus **awards**: Best Comeback, Cleanest Driver,
  Shortcut Expert and High Flyer.
- **One-time challenges**, **mastery badges** for each track (bronze, silver,
  gold), **personal best laps**, and **golden tokens** in the lobby.
- **Garage** with a live 3D preview. Unlock and equip bodies, paint and trim,
  wheels, stickers, horns, trails, a licence plate and a kart name (both go
  through Roblox's text filter).
- **Settings:** auto-accelerate, fewer effects, camera further back.
- **Saved:** unlocks, equipped cosmetics, settings, records and progress.

## Code layout

```
src/shared/    pure game rules, tested outside Roblox with Lune
  KartPhysics  handling, drift, turbos, slipstream, tricks, surfaces
  Track        centreline, projection, laps, zones, crossers, shortcuts
  Tracks       every track and theme; Scenery = where props go
  RoadGeometry the road's cross-section frames (shared by builder and tests)
  Landscape    plans hills, lakes, mountains, mesas and road banks
  Items        item list and position-weighted odds
  Voting       options, tally, winner
  Rewards      coins, awards, challenges, mastery badges
  PlayerData   save data and every rule for changing it
  Cosmetics    wheels, stickers, horns, trails, text rules
  KartBodies   kart designs (data) and paint palette
  LobbyLayout  where everything in the lobby goes
src/common/    Roblox code shared by server and client
  KartRig      builds and drives a kart; Shapes = rounded parts; Atmos = lighting
  Assets       finds models, MaterialVariants, sounds and sky made in Studio
src/server/
  RoundService    lobby → vote → race → results loop, garage actions, tokens
  RaceService     one race: grid, laps, respawns, CPUs, crossers, results
  ItemService     item boxes and all six items
  DataService     saving with retries and safe failure
  TrackBuilder / RoadSurface / TerrainBuilder / FortressBuilder /
  Landmarks / Props / LobbyBuilder   world building
  StudioTools     command-bar helpers to sculpt and save a track's land
src/client/
  KartController  your kart, camera, input
  KartVisuals     lean, wheels, character animations
  TrackAnimator   crossers, sprinklers
  LobbyUI / LobbyScreens / GarageUI / Hud / UI / Spectate   screens
```

## Tests

```sh
lune run tests/run      # 93 tests, including an 8-CPU race on every track
lune run tests/syntax   # every file compiles
lune run tests/smoke    # builds every track, kart, item and the lobby in Lune's Roblox DOM
```

## Make it look more real in Studio

All of this is optional, and none of it needs code: the game finds things by
name. Check the licence of anything you download (some Sketchfab models need
a credit, some can't be used in games at all).

### 1. Your own 3D models (trees, rocks)

1. Bring them in with **File → Import 3D** (FBX, OBJ or glTF) or the Toolbox.
   Keep them low-poly: trees under about 2,000 triangles, distant trees under
   about 300.
2. In **ReplicatedStorage**, make a folder `KartAssets` with folders `Trees`,
   `Pines`, `Rocks`, `Bushes` and `FarTrees`, and put each model (as a Model)
   in the right one.
3. Too big or small? Add a number attribute `Scale` to that model.

Every tree, pine, rock and bush on the tracks then uses one of your models.
Each copy is scaled, turned, leaned and shaded a little differently, stands
on the ground, and never collides with karts.

### 1b. Cars from Blender

Put car Models in `KartAssets` → `Bodies`:

- **Named after an existing car** (`thunder`, `v12`, `blowerrod`,
  `dragster`, `dunehauler`, `classic`, …): your model replaces that car's
  look.
- **Any other name:** a new car in the garage. Optional attributes:
  `DisplayName`, `Price` (coins), `Cpu` (true = CPU drivers may race it),
  `SeatY`/`SeatZ` (driver position), and, only if you don't model wheels,
  `WheelX`, `FrontZ`, `RearZ`, `WheelRadius`, `RearWheelRadius`, `WheelWidth`.

How to model it:

- About 9–10 studs long and 5 wide. Nose toward -Z (if it comes in turned or
  the wrong size, add `Yaw` in degrees or `Scale` instead of re-exporting).
  The game stands the model's lowest point on the road.
- **Wheels** as four separate parts named `WheelFL`, `WheelFR`, `WheelRL`,
  `WheelRR`: they spin, the front pair steers, and the rear pair throws
  drift sparks. Leave them out to get the game's own wheels.
- **Paint:** parts named `Paint…` (or attribute `Role` = `main`) take the
  player's main colour; `Accent…` (or `Role` = `accent`) the accent colour.
- **Engine:** attribute `Anim` = `engine` on a part (blower, intake stacks)
  makes it rumble.
- Leave a gap for the driver; the seat is at the body's centre unless you
  set `SeatY`/`SeatZ`.
- Keep it light: under ~10,000 triangles for the whole car, textures
  1024×1024 at most. Eight cars race at once.

The driving doesn't change: speed and handling come from the engine type
(Zippy, Classic, Brute), whatever the body looks like.

### 2. PBR textures

- **Roads, verges and barriers:** in **MaterialService**, add MaterialVariants
  with these names and base materials: `KartAsphalt` (Asphalt),
  `KartConcrete` (Concrete), `KartGrass` (Grass), `KartSand` (Sand),
  `KartGravel` (Pebble), `KartDirt` (Ground), `KartStone` (Slate). Give each
  a ColorMap, NormalMap and RoughnessMap (MetalnessMap only for metal). The
  track builder uses them automatically.
- **Terrain:** in MaterialService's properties, point a terrain material (for
  example Grass) at your variant to retexture the land.
- **Models:** SurfaceAppearance (colour, normal, roughness, metalness maps)
  goes on the MeshParts of the models from step 1.

### 3. Sound

In `KartAssets`, add a folder `Sounds` with Sound objects (Toolbox audio or
your uploads) named:

| Name | Where it plays |
| --- | --- |
| `Wind` | over the whole track |
| `Water` | at every lake and along rivers |
| `Birds` | at six spots beside the road |
| `Engine` | on every kart; the pitch rises with speed |
| `LobbyAmbience` | inside the lobby |

### 4. Sky

Put a Sky (a custom skybox) in `KartAssets` named `Sky`, or straight into
Lighting. Without one, Roblox's sky is used with a bigger sun and stars.

### 5. Sculpt the land yourself

The land is generated for each race, so hand edits would be wiped unless
you save them. In Edit mode, open **View → Command Bar** and run:

```lua
local T = require(game.ServerScriptService.Server.StudioTools)
T.preview("ridgeline")   -- builds the track and its land
-- now use the Terrain Editor: Generate, Draw, Add, Smooth, Paint, Import
-- (heightmaps, e.g. from a heightmap website), or a plugin like World Engine
T.check("ridgeline")     -- lists spots where land comes within 1 stud of the road
T.save("ridgeline")      -- races use your land from now on
T.clear()                -- remove the preview, then File → Save
```

`T.forget("ridgeline")` goes back to generated land. Use `"lobby"` to shape
the view outside the lobby window. Track ids: `ridgeline`, `alpine`,
`sunny`, `canyon`, `backyard`, `emberfort`, `neon`, `toyroom`, `kitchen`.
The road always comes from the track data, so leave room under it.

Animated grass (Terrain Decoration) is on: generated terrain stays 3.5 studs
under every road and 8 under the lobby floor. If grass ever shows through
something, set `TerrainBuilder.GrassBlades = false`.

### Already set up in code

Future lighting with the Realistic lighting style, Atmosphere haze,
volumetric clouds, gentle bloom, sun rays, colour correction, a low ambient
fill for natural shadow contrast, and a warm or cool tint on sunlit surfaces
per map (`Tracks.Themes`).

### Keep it fast

- Low-poly models, and reuse a few models many times rather than many
  different ones.
- Few local lights; leave shadows off on small ones.
- Big pasted land and many models take longer to load at race start; test
  on a phone with the device emulator.

## Assets to replace

Everything is built from Roblox's own parts: boxes, spheres, stretched spheres
(SpecialMesh), cylinders and wedges. That keeps the game working without
uploads. These will look much better as custom meshes or sounds:

- **Kart bodies:** each body in `KartBodies.List`. Swap parts for MeshParts, and
  keep the simple ball collider.
- **Landmarks:** bed, toaster, cereal bowl, flowerpot, toy chest, crossers
  (robot, train, beetle), giant props (`Landmarks.luau`, `Props.luau`).
- **Trees and rocks:** built from textured parts until you add models to
  `ReplicatedStorage.KartAssets` (see "Make it look more real in Studio").
- **Sounds (none built in):**
  - engine, wind, water, birds, lobby: drop Sounds into
    `KartAssets.Sounds` (see above);
  - drift, boost: no slots yet;
  - item sounds: `ItemService.Sounds`;
  - horns: `Cosmetics.Horns[].soundId`;
  - countdown, music: no slots yet.
- **Track images:** vote cards and wall displays currently use animated 3D
  track previews generated from track data; uploaded artwork is optional.

Keep everything original: no Nintendo names, characters, items or tracks.

## Original Blender asset pack (awaiting Studio import)

See `art/README.md` for the reproducible headless Blender generator, model
previews, triangle manifest, FBX exports and post-import attribute helper.
`default.project.json` includes the empty KartAssets folders and preserves
manual children during live Rojo sync. A fresh build still has no imported
meshes: save Roblox asset models into the source project after review.
No Studio runtime, render, physics, avatar-fit or asset-audio checks have
been completed here. Original source renders must be reviewed before import.

The Blender kit now has a detailed revision with sculpted car panels, curved
wheel arches, treaded tyres, inset lights, mirrors, grille slats, instruments
and engine drive details. Nature models have branches, root flares, smoother
canopies and weathered rock material patches. Review the 1080×1080 renders
and per-model triangle counts under `art/` before importing; Studio rendering
and actual avatar/wheel behaviour remain unverified.

## Emberstone Citadel map preview and scenery import

`art/citadel/` contains the original Blender map, 1080p geometry renders,
512px textures, chunked scenery FBXs and a coordinate/triangle manifest.
The road is derived from the existing playable track. A Model named
`ReplicatedStorage.KartAssets.Tracks.emberfort` replaces the procedural
FortressBuilder scenery; native roads, checkpoints and race mechanics stay
active. See `art/citadel/README.md` before import. Blender renders do not
verify Roblox lighting, material loading, terrain overlap or performance.

The enclosed Citadel art revision adds a continuous volcanic cliff perimeter,
roofed cave galleries and dense original jungle/temple/supply scenery. It still awaits
Studio import; verify chase-camera clearance inside the galleries and terrain
overlap around temple islands. The playable road layout is unchanged.
