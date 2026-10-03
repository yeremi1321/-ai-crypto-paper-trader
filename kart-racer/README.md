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
| 🔥 Emberstone Citadel | Cobblestone gates, stone arches, battlement towers, lava canals, warm torches, basalt spires, raised bridge and ramp |
| 🧸 Midnight Toy Room | Ruler bridge, block ramps, a dash under the bed, toy robot and train crossings, corner shortcut |
| 🍳 Kitchen Chaos | Toaster launch onto a countertop shelf that bridges the start, conveyors, spatula ramps, syrup, cutting-board shortcut |
| 🐞 Backyard Bug Rally | Hose tunnel, flowerpot jumps, crossing beetles, sprinklers that turn the dirt slippery, hollow-log shortcut |
| 🌳 Sunny Loop / 🏜️ Canyon Climb / 🌃 Neon Eight | Earlier tracks: fast corners, hills, figure-eight bridge |

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

Eighteen bodies:
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
  Items        item list and position-weighted odds
  Voting       options, tally, winner
  Rewards      coins, awards, challenges, mastery badges
  PlayerData   save data and every rule for changing it
  Cosmetics    wheels, stickers, horns, trails, text rules
  KartBodies   kart designs (data) and paint palette
  LobbyLayout  where everything in the lobby goes
src/common/    Roblox code shared by server and client
  KartRig      builds and drives a kart; Shapes = rounded parts; Atmos = lighting
src/server/
  RoundService    lobby → vote → race → results loop, garage actions, tokens
  RaceService     one race: grid, laps, respawns, CPUs, crossers, results
  ItemService     item boxes and all six items
  DataService     saving with retries and safe failure
  TrackBuilder / FortressBuilder / Landmarks / Props / LobbyBuilder   world building
src/client/
  KartController  your kart, camera, input
  KartVisuals     lean, wheels, character animations
  TrackAnimator   crossers, sprinklers
  LobbyUI / LobbyScreens / GarageUI / Hud / UI / Spectate   screens
```

## Tests

```sh
lune run tests/run      # 82 tests, including an 8-CPU race on every track
lune run tests/syntax   # every file compiles
lune run tests/smoke    # builds every track, kart, item and the lobby in Lune's Roblox DOM
```

## Assets to replace

Everything is built from Roblox's own parts: boxes, spheres, stretched spheres
(SpecialMesh), cylinders and wedges. That keeps the game working without
uploads. These will look much better as custom meshes or sounds:

- **Kart bodies:** each body in `KartBodies.List`. Swap parts for MeshParts, and
  keep the simple ball collider.
- **Landmarks:** bed, toaster, cereal bowl, flowerpot, toy chest, crossers
  (robot, train, beetle), giant props (`Landmarks.luau`, `Props.luau`).
- **Sounds (none yet):**
  - engine, drift, boost: no slots yet, needs adding;
  - item sounds: `ItemService.Sounds`;
  - horns: `Cosmetics.Horns[].soundId`;
  - countdown, music: no slots yet.
- **Track images:** vote cards and wall displays currently use animated 3D
  track previews generated from track data; uploaded artwork is optional.

Keep everything original: no Nintendo names, characters, items or tracks.

## Road surface repair

RoadRibbon builds shared-edge triangles from the track centerline; old
rectangular Road parts retain metadata but are invisible and noncolliding.
The native wedge ribbon owns road collision. Segment roll is disabled so
geometry and checkpoint heights agree. Lobby ramps are continuous wedges
instead of stair-like stacks. Studio must verify seam traversal, hills,
raycasts, camera clearance, and appearance; Lune does not render or simulate
Roblox physics.
