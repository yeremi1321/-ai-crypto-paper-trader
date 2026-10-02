# Kart Racer (Roblox)

An arcade kart racer in the spirit of classic kart games, with original
characters, karts, items and tracks. Your Roblox avatar drives. Pick a kart,
ready up, and race a 3-track Grand Prix against friends, with CPU drivers
filling the empty spots of the 8-kart grid.

## What's in it

- **Three tracks:** Sunny Loop (flat and fast), Canyon Climb (hills), and Neon
  Eight (a figure-eight with a bridge crossover at night). They're generated from
  a handful of control points, so new tracks are cheap to add.
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

## Layout

```
kart-racer/
  default.project.json
  src/shared/      pure game rules, tested outside Studio
    Karts          kart bodies + CPU drivers
    KartPhysics    arcade handling: speed, steering, drift, mini-turbos, hits
    Track          spline centerline, projection, surfaces, grid, lap progress
    Tracks         the three tracks + the cup
    Items          item list and position-weighted rolls
    RaceRules      placings, points, rocket start, CPU catch-up
    AIDriver       CPU steering, drifting and braking
    RemoteNames
  src/common/
    KartRig        builds a kart and connects KartPhysics to Roblox physics
  src/server/
    RaceService    lobby, Grand Prix, grid, laps, respawns, CPUs, results
    ItemService    item boxes, oil, bouncers, rockets, leader bolt
    TrackBuilder   turns a track's centerline into parts
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
lune run tests/run      # 33 tests, including a full 8-CPU race on every track
lune run tests/syntax   # every .luau file compiles
lune run tests/smoke    # builds every track, kart and item box in Lune's Roblox DOM
```

The simulation runs the real handling, track and AI code, so editing a track
into an undrivable shape (corners too tight, slopes too steep) fails the tests.
Lap times in the simulation are about 20–27 seconds.

## Original, not Nintendo

Kart racing as a genre is fair game, but Nintendo's characters, names, item
designs (shells, bananas, mushrooms, stars) and track designs are not. Keep
everything original before publishing.
