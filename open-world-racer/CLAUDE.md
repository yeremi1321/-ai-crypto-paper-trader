# Open World Racer: handoff notes for Claude Code

This is a Roblox open-world street racing game, managed with Rojo. Read
`README.md` for the design, controls, file layout and the table that maps each
design idea to its code. This file covers where the work stands and what to do next.

## The game in one paragraph

Players start with an ordinary car in their own garage and become known across
the city's racing scene. The open world is the core. Players spawn at the garage
and drive anywhere. Races, shops, meets and other players are all places on the
same map. Nothing is picked from a menu, so driving between races has to be fun
on its own.

## Status

- All code for the first playable slice is written. Map, cars, shops, races,
  flash races, midnight meet, challenges, reputation, records, discoveries, HUD
  and saving all exist.
- **It has never been run in Roblox Studio.** It was written in a cloud container.
  Only the pure-Luau rules and the map/car builders were checked there, with Lune.
- `lune run tests/run` (42 tests), `lune run tests/syntax` and `lune run tests/smoke` all pass.

## Setup on this PC

1. Install Rojo (Aftman or Rokit, or the release binary) and the Rojo Studio plugin.
2. Install Lune for tests: `cargo install lune --locked`, or a release binary.
3. In this folder, run `rojo serve`. Open a new Baseplate place in Studio and connect with the Rojo plugin.
4. In Studio, go to Game Settings → Security and turn on "Enable Studio Access to API Services" so saving works.
5. Press Play. Check the Output window for errors from `[DataService]`, `[RaceService]`, `[WorldEventService]` and `[DiscoveryService]`.

## Finish list, in priority order

Before moving on from each item, verify it in Studio: Play solo, or use
Test → Clients and Servers with 2 players for multiplayer features.

1. **Boot cleanly.** No errors in Output on Play, for both server and client. The
   map generates, you spawn at the garage, and a car appears on the street in front of it.
2. **Driving works.**
   - F gets you in, W moves the car forward. If it goes backwards, flip `FORWARD_SIGN` in `src/client/DriveController.luau`.
   - Steering direction is right (the `-steer * angle` sign in `drive()`).
   - The car doesn't flip, bounce, or have wheels fighting the chassis. Check the `NoCollisionConstraint` setup and mass in `VehicleFactory`.
   - Brake, reverse and handbrake (Left Shift) behave sensibly. Space gets you out.
3. **Driving feel.** Tune the acceleration formula, `BRAKE_DECEL` and the steering
   falloff in `DriveController`, and wheel friction in `VehicleFactory`. Add spring
   suspension (`SpringConstraint` + `PrismaticConstraint` or `CylindricalConstraint`
   per wheel) if the car feels stiff. The six cars must feel different from each other.
4. **Shops.** Press E at the dealership, tuning shop and garage. Buy a part, install
   it, and check the car rebuilds with the new class/rating. Save and load a build,
   paint the car, buy a garage bay, buy a car, and switch cars.
5. **Races.**
   - Drive into each yellow start zone. The lobby countdown runs, the grid places the car, the countdown releases it, and checkpoint pillars show the way.
   - Finishing pays cash and district rep, and the records sign updates.
   - With 2 clients, check the class cap works and the standings order is right.
6. **World events.**
   - Flash races appear and can be joined.
   - The midnight meet clue shows at dusk and the meet opens at 23:30 game time. To test quickly, temporarily shorten `WorldClock.DayLength`.
   - Test a challenge between 2 clients (C, then Y).
7. **Discoveries.** Speed trap readout, drift zone score, the hidden part stash
   (shows up in the garage inventory), and the scenic road cash reward.
8. **Saving.** Leave and rejoin. Cash, cars, parts, rep and discoveries persist.
9. **Sounds.** Upload or choose engine loops, tire squeal and rain sounds. Put their
   ids in `EngineAudio.Profiles[*].soundId` and `Ambience.SOUNDS`.
10. **Mobile.** Check the VehicleSeat thumbstick drives the car, and add on-screen
    buttons for handbrake, reset and challenge.

After that, follow "Next steps" in `README.md`: personal garage interiors, meet
route voting and photo mode, crew rivalries, traffic and detours, more districts,
and visual customization.

## Conventions

- `src/shared` stays **pure**: no `game`, no Instances. That keeps it testable in Lune.
  Shared modules require each other with string requires (`require("./X")`).
  Put new game rules here and add tests in `tests/*.spec.luau`, registered in `tests/run.luau`.
- Server and client code use instance requires (`require(script.Parent.X)`).
- The server is authoritative. Validate every RemoteEvent argument and check the
  player is at the right physical place (`GarageService.nearPlaceKind`).
- Map coordinates live only in `src/shared/WorldMap.luau`. `tests/WorldMap.spec.luau`
  checks that every event and place sits on a road.
- Car and brand names stay fictional unless licensing is sorted out.
- Run `lune run tests/run && lune run tests/syntax && lune run tests/smoke` before committing.

## Git

The game currently lives in `open-world-racer/` inside the `-ai-crypto-paper-trader`
repo, on the branch `claude/open-world-racing-design-4glnag`. The rest of that repo
is an unrelated crypto trading bot, so don't touch it. The owner may move this
folder into its own repo. If so, copy `open-world-racer/` to the root of the new repo.
