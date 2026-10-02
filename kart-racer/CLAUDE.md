# Kart Racer: handoff notes for Claude Code

A Roblox arcade kart racer managed with Rojo. Read `README.md` first for
features, controls and layout.

## Status

- All code for the first playable version is written: 3 tracks, 3 karts,
  drifting and mini-turbos, 7 items, CPU drivers, a 3-race Grand Prix, lobby,
  results and touch buttons.
- **It has never been run in Roblox Studio.** Only the pure rules
  (`src/shared`), the track builder, the kart builder and the item boxes were
  checked outside Roblox, with Lune.
- `lune run tests/run` (33 tests, including an 8-CPU race simulation on every
  track), `lune run tests/syntax` and `lune run tests/smoke` all pass.

## Setup on this PC

1. Install Rojo and its Studio plugin, plus Lune (`cargo install lune --locked`).
2. `rojo serve` in this folder, then connect from a new Baseplate place in Studio.
3. Press Play. Look for `[KartRacer] server ready` in Output. Pick a kart, press READY.

## Finish list, in priority order

Verify each one in Studio before moving on.

1. **Boot and lobby.** No errors in Output. The lobby screen shows 3 kart cards, and READY starts a race.
2. **Seating and countdown.** Your avatar sits in the kart on the grid behind the
   line. The camera is behind the kart, and the 3-2-1-GO countdown shows.
3. **Driving.** W moves the kart forward (if it goes backwards, check the sign in
   `KartPhysics.forward`). A/D steer the right way. The kart follows slopes on
   Canyon Climb and the Neon Eight bridge, and walls stop it without launching it.
   - Tune feel in `KartPhysics` (speeds, drift, turbo times) and `KartRig.apply`
     (force, `Responsiveness`).
   - If the kart bounces or tips, raise `AlignOrientation.Responsiveness` or lower ball elasticity.
4. **Drift.** Hold Space while turning. Sparks go blue → orange → purple, and letting go boosts.
   Make sure Space doesn't make the avatar jump out of the seat (`KartDrift` action in `KartController`).
5. **CPU drivers** drive the track, drift and use items, and don't get stuck on walls.
   The race simulation passes, but real physics may differ.
6. **Items.** Boxes give items after the roulette. Each item works: oil spins
   karts, the bouncer bounces off walls, the rocket chases the racer ahead,
   the bolt hits 1st, and Overdrive makes you immune.
7. **Laps and results.** Lap / final lap / finish messages appear, positions
   update, and results and points show. The next track loads, then cup results,
   then back to the lobby.
8. **Respawn.** Driving off the Neon Eight bridge or getting stuck puts you back on the road.
9. **Multiplayer** (Test → Clients and Servers, 2–3 players). Bumping, items
   hitting other players, and everyone seeing each other's karts.
10. **Mobile.** Use Studio's device emulator to check the thumbstick drives and
    the DRIFT/ITEM buttons work.
11. **Sound.** Add engine, drift, boost, item and countdown sounds. There are none yet.

After that:
- More tracks and cups (add to `Tracks.List`; the simulation test checks they're drivable).
- Battle mode, time trials with ghosts, unlockable karts, character customisation.
- Drift sparks for other players' karts (now only visible to the driver and on CPU karts).
- Server-side sanity checks on player kart speed (players currently simulate their own kart).

## Conventions

- `src/shared` stays pure (no `game`, no Instances) and is tested in Lune. Shared
  modules require each other with `require("./X")`. Add tests for new rules in
  `tests/*.spec.luau` and register them in `tests/run.luau`.
- `src/common` is Roblox code used by both server and client (`KartRig`).
- The server decides item hits, laps and placings. Clients only drive their own kart.
- Keep everything original: no Nintendo names, characters, items or tracks.
- Run `lune run tests/run && lune run tests/syntax && lune run tests/smoke` before committing.

## Git

Lives in `kart-racer/` on branch `claude/open-world-racing-design-4glnag` of the
`-ai-crypto-paper-trader` repo, next to the separate `open-world-racer/` game.
The rest of that repo is an unrelated crypto bot, so don't touch it.
