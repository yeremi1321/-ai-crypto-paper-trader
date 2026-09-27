# Open World Racer (Roblox)

Start with an ordinary car, build it up, and become known across the city's racing
scene. The open world is the core of the game: you spawn at your garage, drive
anywhere, and find races, shops and other players on the same map. There is no
event menu.

This folder is the **first playable slice**: one downtown district, a highway loop,
a circuit, a drag strip, a garage, six distinct cars, and three race types, plus
flash races, the midnight meet, challenges, reputation and discoveries.

## Run it

1. Install [Rojo](https://rojo.space) and the Rojo Studio plugin.
2. From this folder: `rojo serve`, then connect from Studio in an empty Baseplate place.
3. Press Play. The map is generated at startup by `WorldBuilder`, so there is nothing to build by hand.
4. To test saving in Studio, turn on *Game Settings → Security → Enable Studio Access to API Services*.
   Without it the game still runs; progress just is not saved.

Shared modules use Luau string requires (`require("./CarCatalog")`), which Roblox
supports for ModuleScripts. Server and client code use instance requires.

### Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Throttle / brake / steer | W S A D | triggers + stick |
| Handbrake (drift) | Left Shift | B |
| Get in your car | F (at the car) | |
| Get out | Space | A |
| Reset a stuck car (or bring a car out at the garage) | R | Y |
| Challenge the nearest driver | C | D-pad up |
| Accept / pass a challenge | Y / N | |
| Use a shop | E at the shop pad | |

## The map

```
                 Highway Loop (octagon, r = 900)
          ┌───────────────────────────────────────┐
          │           Downtown grid (7×7)          │
 Westside ├── ramp ──  garage · dealership ── ramp ┤── Harbor Ring
  Strip   │           tuning · Night Owl Gas       │   (2-lap circuit)
 (drag)   └───────────────────────────────────────┘
```

All coordinates live in `src/shared/WorldMap.luau`: roads, districts, shops, event
routes, flash-race spots, midnight-meet spots and discoveries. `WorldBuilder` turns
that data into parts. A hand-built map can replace `WorldBuilder` later as long as
the coordinates in `WorldMap` still match it.

## How the design maps to code

| Design idea | Where it lives |
| --- | --- |
| Spawn at your garage, drive anywhere | `GarageService` (car spawns in front of the garage), `WorldBuilder` |
| Shops you drive to (dealership, tuning, garage) | Shop pads with prompts. The server rejects shop actions unless you're parked at the right place (`GarageService.nearPlaceKind`). Menus are in `ShopMenu` |
| Races are places on the map | Drive into a yellow start zone to join its lobby (`RaceService`). Lobbies wait 20s for more drivers, and solo play works |
| Fair competition by class | Performance rating 100–999 and classes D–S (`Performance`). A lobby is capped at the class of the first car to join |
| Circuit / sprint / drag | `WorldMap.Events`: Harbor Ring, Downtown Sprint, Highway Run, Westside Quarter |
| Flash races at changing spots | `WorldClock.flashRace`: every 150s, a 70% chance of a race opening at one of four spots for 90s |
| Midnight meet | `WorldClock.midnightMeet`: the clue appears at dusk and the exact spot is revealed at 23:30. Players gather for 2 minutes, then drive together from the meet to the featured race's start (meet-to-race flow) |
| Same meet on every server | Everything in `WorldClock` is computed from Unix time, so all servers agree without talking to each other |
| Challenge anyone anywhere | Press C near another driver. The server picks a landmark 500–1600 studs away and you race there by any route |
| District reputation | `Progression`: Unknown → Regular → Known → Respected → Legend, tracked per district. Your title ("Known of Harbor Ring") comes from your best district |
| Local records at each spot | Leaderboard signs at every start zone. Speed traps and drift zones keep their own boards (`Records`, `DataService`) |
| Speed traps, drift zones, hidden parts, scenic roads | `DiscoveryService` + `WorldMap.Discoveries` |
| Customization and saved builds | Parts (engine, turbo, tires, suspension, weight, gearing) and paint. Street / drag / drift / track setups can be saved and loaded (`PlayerProfile`) |
| Garage expansion | Bays 1→6. Buying a car needs a free bay |
| Day/night, rain | `WorldEventService` drives `Lighting.ClockTime`, and some days get a rain shower (particles + optional sound) |
| Engine sound follows RPM and upgrades | `EngineAudio` simulates gears and RPM, and `Ambience` sets pitch and volume on every nearby car. A turbo raises the pitch slightly. Rain muffles the engine a little |

## Layout

```
open-world-racer/
  default.project.json      Rojo mapping
  src/shared/               pure game rules, tested outside Studio
    CarCatalog              fictional cars + performance parts
    Performance             rating and class matching
    RaceLogic               checkpoints, laps, standings, DNF
    Progression             payouts, reputation tiers, titles
    PlayerProfile           save data and every rule for changing it
    Records                 per-spot leaderboards
    WorldMap                the whole map as data
    WorldClock              day/night, rain, flash races, midnight meet
    EngineAudio             gearbox + RPM → pitch/volume
    RemoteNames             remote event names
  src/server/
    Main.server             boot order
    DataService             DataStore profiles and leaderboards, autosave
    WorldBuilder            generates the map
    VehicleFactory          builds a car from an owned-car record
    GarageService           cars, shops, garage actions
    RaceService             lobbies, races, challenges, record signs
    WorldEventService       lighting, weather, flash races, midnight meet
    DiscoveryService        speed traps, drift zones, stashes, scenic roads
  src/client/
    Main.client             wiring
    DriveController         drives the car (the driver owns its physics)
    Hud                     cash, speedo, race panel, world panel, toasts, invites, results
    ShopMenu                dealership / tuning / garage menus
    Ambience                engine + tire audio, rain, map markers, checkpoints
  tests/                    Lune test suites
```

## Tests

The shared rules and the map/car builders run outside Roblox with
[Lune](https://github.com/lune-org/lune) (`cargo install lune --locked`):

```sh
lune run tests/run      # 42 unit tests for shared game rules
lune run tests/syntax   # every .luau file compiles
lune run tests/smoke    # builds the full map and every car in Lune's Roblox DOM
```

The smoke test catches invalid classes, properties and enums. It cannot simulate
physics, events or services, so check those in Studio.

## Check in Studio first

These couldn't be verified outside Roblox:

- **Wheel direction.** If cars drive backwards, flip `FORWARD_SIGN` in `DriveController`.
- **Handling feel.** Tune acceleration, braking and steering in `DriveController`, and wheel friction in `VehicleFactory`. Cars have no suspension springs yet.
- **Sounds.** Engine, tire and rain sound ids are empty on purpose. Upload loops and set them in `EngineAudio.Profiles` and `Ambience.SOUNDS`.
- **DataStore limits.** Leaderboards use one key per spot. If lots of servers write to the same spot at once, move to OrderedDataStore or MemoryStore.

## Next steps

1. Tune driving feel. Add spring suspension, then weight transfer and drift assist.
2. Personal garages: an instanced interior where you can see all your cars and invite friends.
3. Car meets: route voting, a build showcase and photo mode.
4. Crew rivalries: AI or ghost rivals per district, and a leader challenge that unlocks a special car.
5. Traffic, construction detours and street closures on a schedule from `WorldClock`.
6. More districts, following the design: neon nightlife, industrial docks, wealthy hills, suburbs, mountain roads, coastal highway.
7. Visual customization: wheels, ride height, body kits, wraps, lights and exhaust notes.

Cars and brands are fictional on purpose. Check licensing before adding any real brands or designs.
