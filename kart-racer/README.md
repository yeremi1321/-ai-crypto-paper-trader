# Kart Racer (Roblox)

An arcade kart racer in the spirit of classic kart games, with original
characters, karts, items and tracks. Your Roblox avatar drives. Pick a kart,
ready up, and race a 3-track Grand Prix against friends, with CPU drivers
filling the empty spots of the 8-kart grid.

## What's in it

- **Three big tracks** with their own lighting and scenery: Sunny Loop (trees,
  grandstands, flags), Canyon Climb (hills, mesas, rocks, cacti, golden-hour
  haze) and Neon Eight (a figure-eight with a bridge at night, among glowing
  towers). Curbs, lane lines and boost pads on the road.
- **Six kart body designs** (Classic, Wedge Racer, Dune Buggy, Muscle, Bubble,
  Formula) with 12 paint and 12 trim colours, picked in the lobby. Bodies are
  looks only; the three kart classes (Zippy, Classic, Brute) set the stats.
- **Drifting and mini-turbos.** Hold drift through a corner and the sparks go blue,
  then orange, then purple. Let go for a bigger boost the longer you held it.
- **Rocket start.** Hit the gas between "2" and "1" on the countdown.
- **Boost pads, grass shoulders that slow you down, walls, and a wrong-way warning.**
- **Item boxes and 7 items:** Nitro, Triple Nitro, Oil Slick, Bouncer,
  Homing Rocket, Leader Bolt (hits 1st place) and Overdrive (invincible speed).
  Drivers near the back get better items.
- **CPU drivers** take racing lines, drift, use items, and catch up a little when
  far behind (never faster than players can manage).
- **Grand Prix points** (15-12-10-8-6-4-2-1), grid order reversed by standings,
  and final cup results.
- Respawns when you fall off, lap counting that blocks shortcuts, and touch
  buttons on phones and tablets.

## Run it

**Easiest:** download `KartRacer.rbxlx` from this folder and double-click it (or use
File → Open in Roblox Studio), then press Play. It is a snapshot built from
`src/` with `rojo build . -o KartRacer.rbxlx`, so rebuild it after changing code.

**For development:**

1. Install [Rojo](https://rojo.space) and the Rojo Studio plugin.
2. From this folder: `rojo serve`, then connect from Studio in an empty Baseplate place.
3. Press Play, pick a kart and press **READY**. Solo play starts straight away with 7 CPU drivers.
   To race friends, use Test → Clients and Servers or publish the place.

### Controls

| Action | Keyboard | Gamepad | Touch |
| --- | --- | --- | --- |
| Gas / brake / steer | W S A D | R2 / L2 / stick | thumbstick |
| Drift (hold) | Space or Shift | R1 | DRIFT |
| Use item | E | X | ITEM |

## Customising tracks and karts

**Bigger tracks:** in `src/shared/Tracks.luau`, raise a track's `scale` (stretches
the whole layout, hills included) and `width` (road width in studs).

**New track shapes:** edit or add `controls`, the points the road passes through
in driving order. The road is smoothed between them automatically.

**Scenery:** `src/shared/Scenery.luau` sets how many of each prop each theme gets
and how far from the road they go. `src/server/Props.luau` sets what each prop
looks like. To add a new prop, add a builder there and list it under a theme.

**Lighting and colours:** each theme in `Tracks.Themes` has the time of day,
atmosphere (haze, colour), bloom, colour tint, and road / curb / line colours.

**Kart designs:** `src/shared/KartBodies.luau`. Each body is a list of boxes,
balls, cylinders and wedges with a size, an offset and a colour role (paint,
trim, dark, glass, chrome, light). Copy a body, change the parts, and it shows
up in the lobby picker. Add colours to `Palette` for more paint options.

After any change, run the tests (below). They check that tracks are still
drivable and that no scenery lands on the road. Then rebuild the place file:
`rojo build . -o KartRacer.rbxlx`.

## Layout

```
kart-racer/
  default.project.json
  src/shared/      pure game rules, tested outside Studio
    Karts          kart bodies + CPU drivers
    KartPhysics    arcade handling: speed, steering, drift, mini-turbos, hits
    Track          spline centerline, projection, surfaces, grid, lap progress
    Tracks         the three tracks, their themes and lighting, the cup
    Scenery        where props go around each track
    KartBodies     kart body designs and paint palette
    Items          item list and position-weighted rolls
    RaceRules      placings, points, rocket start, CPU catch-up
    AIDriver       CPU steering, drifting and braking
    RemoteNames
  src/common/
    KartRig        builds a kart and connects KartPhysics to Roblox physics
  src/server/
    RaceService    lobby, Grand Prix, grid, laps, respawns, CPUs, results
    ItemService    item boxes, oil, bouncers, rockets, leader bolt
    TrackBuilder   turns a track's centerline into parts, markings and lighting
    Props          scenery models (trees, rocks, towers, grandstands...)
  src/client/
    KartController input, drives your kart, chase camera
    Hud            lobby, race HUD, item roulette, results, touch buttons
  tests/
```

How a kart moves: an invisible ball carries the kart. KartPhysics decides
speed and heading. A `LinearVelocity` pushes the ball horizontally (vertical
movement is left to gravity, so hills and jumps work), and an
`AlignOrientation` turns the visible body to match the heading and road slope.
Your client simulates your own kart; the server simulates the CPU karts with
the same code.

## Tests

With [Lune](https://github.com/lune-org/lune) installed (`cargo install lune --locked`):

```sh
lune run tests/run      # 40 tests, including a full 8-CPU race on every track
lune run tests/syntax   # every .luau file compiles
lune run tests/smoke    # builds every track, kart and item box in Lune's Roblox DOM
```

The simulation runs the real handling, track and AI code, so editing a track
into an undrivable shape (corners too tight, slopes too steep) fails the tests.
Lap times in the simulation are about 32–42 seconds.

## Original, not Nintendo

Kart racing as a genre is fair game, but Nintendo's characters, names, item
designs (shells, bananas, mushrooms, stars) and track designs are not. Keep
everything original before publishing.
