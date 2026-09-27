# Rising Escape — escape the volcano

A co-op obby for 1–6 players. The host picks the party capacity, friends join
from the lobby, and the host starts whenever ready. Each party climbs out of its
own volcano while lava rises from below. Teammates are tied together by a rope.
Free to complete: no purchases, ads, saved data or external assets.

## Install in Roblox Studio

1. **File → New → Baseplate**.
2. **ServerScriptService** → **+** → **Script**, rename `EscapeObbyServer`,
   replace everything inside with `EscapeObbyServer.lua`.
3. **StarterPlayer → StarterPlayerScripts** → **+** → **LocalScript**, rename
   `EscapeObbyClient`, replace everything inside with `EscapeObbyClient.lua`.
4. Press **Play**, pick a size, **Create party**, **Start**.
5. Team test: **Test** tab → Clients and Servers → 2–3 players → **Start**.

Check after pasting: the scripts are long, and the last line in Studio should
match the last line of each file.

## How a round plays

The route climbs the inside of the volcano through three zones: Smoky Cave, then
Magma Tunnels, then Crater Rim, ending at a rescue helicopter. It is made of six
obstacle sections, shuffled every round:

| Section | What happens |
| --- | --- |
| Basalt Pillars | Hop across pillars. |
| Rescue Ledges | Cracked ledges crumble. A falling teammate dangles from the rope and others tap PULL to haul them up. |
| Split Path | Two paths over a lava channel. Teammates stand on both switches at the same time to open the gate. Solo players need one switch. |
| Geyser Field | Vents glow, smoke and shake the camera for 2.5 s, then erupt. There is always a safe lane. |
| Collapsing Bridge | The bridge breaks a few seconds after the first step (longer for bigger parties), then rebuilds. |
| Rope Swing | The gap is too wide to jump. Jump at the hook to swing across, then hit the lever to lower a bridge for everyone. The bridge also lowers by itself after 35 s, so nobody gets stuck. |

- **Team rope:** each player is roped to the next one in the party. If you fall
  while a teammate stands above you, the rope catches you and you dangle. The
  teammate sees a **PULL** button (key **E** on desktop). If they fall too,
  nobody is holding you. The rope detaches when teammates are far apart, for
  example after a respawn, and reconnects when you catch up.
- **Checkpoints:** green pads at the start of sections 3 and 5. If the lava has
  already passed your checkpoint when you die, you are out.
- **Win:** land on the helipad before the lava or the 180 s timer gets you.

All tuning values (timer, lava speed, rope length, bridge time, geyser timing)
are at the top of `EscapeObbyServer.lua`.

## Testing status

The server logic was run headless against a stand-in for the Roblox API. 300
random courses built without errors and were all completable with default
jumps, and a full 3-player round played through. The rope and swing physics run
on each player's device and can only be judged in Studio.
