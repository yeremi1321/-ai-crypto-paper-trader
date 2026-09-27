# Rising Escape Obby — first playable prototype

Solo or party play (1–6). The host picks the party capacity, friends join from the
lobby, and the host starts whenever ready (fewer players than the capacity is fine).
Each party gets its own freshly generated course, so several parties can play at
once in one server: 12 jumps, checkpoints on stages 4 and 8, rising lava, a
100-second timer and a results screen. Free to complete — no purchases, ads,
saved data or external assets.

## Install in Roblox Studio

1. **File → New → Baseplate**.
2. In **Explorer**, hover **ServerScriptService**, click **+**, choose **Script**.
   Rename it `EscapeObbyServer`. Delete the default `print("Hello world!")` line and
   paste the entire contents of `EscapeObbyServer.lua`.
3. Expand **StarterPlayer**, hover **StarterPlayerScripts**, click **+**, choose
   **LocalScript**. Rename it `EscapeObbyClient`. Delete the default line and paste
   the entire contents of `EscapeObbyClient.lua`.
4. Press **Play**. Pick a size with **− / +**, press **Create party**, then **Start**.
5. Multiplayer test: **Test** tab → Clients and Servers → choose 2–3 players →
   **Start**. Create a party in one client window, press **Join** in the others.
6. Mobile test: **Test** tab → **Device** → pick a phone (e.g. iPhone 14) and Play.

Nothing else needs to be created by hand: the server script makes its own
`ReplicatedStorage.RisingEscapeRemotes` folder, courses and (if missing) a lobby spawn.

## What to check in the first playtest

- Every jump is makeable at normal speed (gaps are 3–5.5 studs, rises 0.5–2.5).
- Dying before stage 4 returns you to the start; after touching a green pad you
  return there; if lava is already above that pad you are eliminated.
- Two parties at once get two separate courses side by side.
- A party member leaving mid-round doesn't stall the round; the host role moves on.

All tuning values (timer, lava speed, gap sizes) are at the top of
`EscapeObbyServer.lua`.

## Volcano theme

On by default. Courses use dark rock platforms with glowing magma edges between
rock canyon walls with lavafalls, and embers rise from the lava. The world gets a
smoky orange sky, a dark rock lobby floor and a big volcano in the background.
Checkpoints stay green and the finish stays gold so they are easy to spot.

These changes are made by the script while the game runs, so your saved place
is not altered. To switch them off, set `VOLCANO_COURSE` or `VOLCANO_WORLD` to
`false` near the top of `EscapeObbyServer.lua`.
