# Kart Racer: handoff notes for Claude Code

A Roblox party kart racer managed with Rojo. Read `README.md` first for
features, controls and layout. The original design brief is followed in
stages; this file says where things stand.

## Status

All six stages of the first playable build are written:

1. Lobby, ready-up, map voting, round flow
2. Driving polish
3. Track features and three themed tracks
4. Six items
5. Progression, saving and garage
6. Creative karts

- **None of it has been run in Roblox Studio.** It was written in a cloud
  container.
- **What was checked there:** the pure rules (`src/shared`), and building every
  track, kart, item and the lobby in Lune's Roblox DOM.
- **What hasn't been checked:** physics, input, UI layout, networking,
  DataStores and text filtering.
- **Checks:** `lune run tests/run` (78 tests), `tests/syntax` and `tests/smoke`
  all pass.

## Setup on this PC

1. Install Rojo, its Studio plugin, and Lune (`cargo install lune --locked`).
2. `rojo serve` here, then connect from a new Baseplate place. Or just open
   `KartRacer.rbxlx`.
3. Turn on Game Settings → Security → "Enable Studio Access to API Services"
   (for saving and text filtering).
4. Press Play and look for `[KartRacer] server ready` in Output.

## Verify in Studio, in this order

1. **Boot.** No errors in Output. You spawn in the Kart Carnival, and the status
   board and HUD show.
2. **Practice loop.** Press E at the PRACTICE sign. The kart drives forward on
   W (if it goes backwards, check `KartPhysics.forward` and the yaw maths in
   `KartRig.apply`). Space drifts and doesn't jump you out of the seat. The
   ramp launches you, and a trick in the air gives a boost. R resets.
3. **Ready → vote → race.** READY starts a 10-second countdown, then voting
   (cards and pads), then the race. The grid, countdown, laps and results all
   work, and you're returned to the lobby.
4. **Each new track:** the toy room bed tunnel, robot and train; the kitchen
   toaster launch up to the shelf, the conveyors and syrup; the backyard hose,
   sprinklers and beetles. Try the shortcuts.
5. **Items:** each of the six, warnings, the shield blocking, and hit protection.
6. **Garage:** the preview rotates, buying and equipping work, coins update,
   and name and plate get filtered. Rejoin to check saving.
7. **Multiplayer:** Test → Clients and Servers with 2–3 players. Voting, items
   hitting other players, spectating, and the podium celebration.
8. **Mobile:** device emulator. Touch buttons, auto-accelerate, readable UI.
9. **Performance:** each track is 2,800–6,000 parts. If it's slow on phones,
   lower the counts in `Scenery.Themes` first.

## Known gaps and next steps

- **No sounds yet.** See "Assets to replace" in the README.
- **Kart bodies and landmarks are built from parts.** Replace them with
  MeshParts for a polished look.
- **Tricks are client-side.** The server rewards server-measured jumps, not the
  trick itself.
- **Other players' drift sparks** only show on CPU karts and your own.
- **Later from the brief:**
  - tracks: Neon Arcade, Dragon's Volcano, Candy Factory, Cloud Carnival,
    Aquarium Escape, Laundry Tornado, Birthday Bash, Mini Golf Madness,
    Clockwork Tower, Music Room Rush;
  - items: Bowling Boulder, Triple Firecracker, Storm Cloud, Party Popper;
  - private friend races where the host picks the map.
- **New tracks:** add them to `Tracks.List` and `Tracks.VotePool`. The
  simulation test checks they're drivable, and the feature tests check
  shortcuts and zones.

## Conventions

- `src/shared` stays pure (no `game`, no Instances) and is tested in Lune. Use
  `require("./X")` between shared modules, and add tests to `tests/` (register
  them in `tests/run.luau`).
- `src/common` is Roblox code used by both sides (KartRig, Shapes, Atmos).
- The server owns progress, laps, item ownership, hits and rewards. Clients
  only drive their own kart and request things.
- In code the smoke test runs, read part positions via `CFrame.Position`. Lune
  can't read `.Position`, `PivotTo` or `GetServerTimeNow`.
- Keep everything original: no Nintendo names, characters, items or tracks.
- Run `lune run tests/run && lune run tests/syntax && lune run tests/smoke`
  before committing, and rebuild `KartRacer.rbxlx` after code changes.

## Git

Lives in `kart-racer/` on branch `claude/open-world-racing-design-4glnag` of
the `-ai-crypto-paper-trader` repo. The rest of that repo is an unrelated
crypto bot and the separate `open-world-racer/` game, so don't touch them.
