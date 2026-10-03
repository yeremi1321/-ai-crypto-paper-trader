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
  track, kart, item and the lobby in Lune's Roblox DOM. The lobby screen
  smoke check uses service/preview doubles to exercise phases, headshot retry,
  countdowns, unique voter counts and door transforms; it cannot render UI.
- **What hasn't been checked:** physics, input, UI layout, networking,
  DataStores and text filtering.
- **Checks:** `lune run tests/run` (90 tests), `tests/syntax` and `tests/smoke`
  all pass.

## Setup on this PC

1. Install Rojo, its Studio plugin, and Lune (`cargo install lune --locked`).
2. `rojo serve` here, then connect from a new Baseplate place. Or just open
   `KartRacer.rbxlx`.
3. Turn on Game Settings → Security → "Enable Studio Access to API Services"
   (for saving and text filtering).
4. Press Play and look for `[KartRacer] server ready` in Output.

## Verify in Studio, in this order

1. **Boot.** No errors in Output. You spawn on the raised entrance in indoor Kart HQ. The wall screen
   cycles track previews; the status board, four pad signs and HUD show.
2. **Compact lobby.** No practice track, lounge or viewing room. Verify the
   short stairs, side ramps, soft lighting, garage, trophies and party bays.
3. **Ready → vote → race.** READY or stepping onto a pad starts the countdown.
   Check all four pads (three tracks plus Random), card votes, wall counts and
   headshots, the winner reveal, gold departure glow, live standings on the
   chamber screen, results top three, and return to the lobby. Confirm countdowns
   use server time and names/health labels and the Invisicam camera behave.
   Walk toward and away from room doors: panels, glass and strips slide
   together without drifting. Departure doors stay shut unless Lit is true.
4. **Realistic land and roads** (first time Terrain runs for real): on
   Pinewater Pass, Sunny Loop and Canyon Climb check the land loads during the
   winner reveal without a long hitch, the road sits slightly above the grass
   everywhere (no grass poking through asphalt), raised road sits on earth
   banks, the Pinewater bridge crosses real water on pillars, and lakes,
   mountains and clouds show. Drive the seams: no bumps between road pieces,
   barriers continuous. Through the lobby's back window: lake, pines, peaks.
5. **Each new track:** Emberstone Citadel gates, clear road under arches,
   lava channels outside barriers, elevated bridge and ramp; the toy room bed tunnel, robot and train; the kitchen
   toaster launch up to the shelf, the conveyors and syrup; the backyard hose,
   sprinklers and beetles. Try the shortcuts.
6. **Items:** each of the six, warnings, the shield blocking, and hit protection.
7. **Garage:** the preview rotates, buying and equipping work, coins update,
   and name and plate get filtered. Rejoin to check saving.
8. **Multiplayer:** Test → Clients and Servers with 2–3 players. Voting, items
   hitting other players, spectating, and the podium celebration.
9. **Mobile:** device emulator. Touch buttons, auto-accelerate, readable UI.
10. **Performance:** each track is about 4,600–6,900 objects plus terrain. If it's slow on phones,
   lower the counts in `Scenery.Themes` first.

## Kart HQ client integration

- `LobbyBuilder` builds chamber/rooms and exposes `setPodium`, `setKartDisplay`,
  `setDeparture`, `celebrate`, the garage prompt, and collectibles.
- `LobbyScreens` owns PlayerGui SurfaceGuis with Adornee references to the
  chamber vote screen/status board/four pad signs. Round
  events call `setState`; RenderStepped calls `step(dt)` for previews,
  countdowns, thumbnail loading, and local sliding doors.
- Door movement stores closed CFrames and offsets every Side-marked part on
  its local X axis. Departure Lit is server-owned; proximity is local.
- Lobby lighting uses `Atmos.apply("hq")`, including after spectating/results.
- Streaming is disabled; walking camera uses Invisicam, zoom max 80, avatar
  name distance 45, health distance 0.

## Current visual revision

- Chamber shrunk from 240 × 300 to 136 × 156 studs, ceiling from 110 to 44.
- Practice and viewing rooms are not built; their room prompts are removed.
  `LobbyScreens` no longer waits for a lounge to exist. Spectating HUD remains.
- HQ bloom is 0.04; matte trim replaces broad neon strips. Warm white fixtures
  provide visibility, and departure color pulses are restrained.
- Emberstone Citadel is in the vote pool. `FortressBuilder` adds original
  stone gates, towers, arches, torches, lava canals and basalt spires.
- Three original racing body cosmetics added, with twin exhaust details on
  the existing starter kart. Cosmetics do not alter class performance.
- Lune checks cover absent rooms, six chamber screens, five sliding doors,
  reachable tokens, fortress gates/canals and racing every track.

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

## Realism pass (roads, terrain, lobby)

- Roads: `shared/RoadGeometry` gives one frame per centreline point;
  `server/RoadSurface` builds the road (2-stud solid triangle slab), curbs,
  lines, shoulders and barriers from those frames, so pieces share their
  ends exactly. `RoadRibbon` and the invisible per-segment Road parts are
  gone. Realistic themes (`theme.realistic`) use asphalt, concrete jersey
  barriers and concrete curbs; `roadMaterial` / `wallMaterial` /
  `shoulderMaterial` override per theme.
- Terrain: a theme's `terrain` table drives `shared/Landscape.plan` (pure,
  tested: nothing on the road, ground always under it). `TerrainBuilder`
  applies it with FillBlock/FillBall/FillCylinder; only one track's land
  exists at a time. `RoundService` starts it during the winner reveal and
  `TrackBuilder` reuses it. In Lune there is no Terrain, so fills are only
  counted (`TerrainBuilder.lastCounts`).
- Earth banks replace pillars under raised road, except over other road or
  a lake the track bridges (`def.lakes`). Props are lifted onto the land via
  `Landscape.groundAt` and skipped over water.
- Lobby: `finish` maps palette colours to materials; the back wall has a
  window over a terrain vista (`buildVista`), rebuilt after every track's
  terrain via `TerrainBuilder.onCleared`.
- Unverified until Studio: terrain build time on a live server, terrain
  surface accuracy at road edges (ground is planned 0.7 studs under the
  road), how water, clouds and PBR materials look on phones.
