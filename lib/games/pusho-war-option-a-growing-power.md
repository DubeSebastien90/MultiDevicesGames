# Push-o'-War — Option A: Growing Tap Power

## One-line pitch
Two phones face each other. One shared boundary line splits the world into blue territory and red territory. Tapping pushes the line toward the opponent. The longer a round runs, the harder every tap hits — so stalemates snap into a decisive finish instead of dragging on.

---

## Core concept

There is exactly **one shared world**, a vertical strip running through both devices, same as a physical table with two phones laid end to end. The world is measured on a single float axis from `-1.0` to `+1.0`.

- `-1.0` = total blue victory (blue's color fills both screens)
- `+1.0` = total red victory (red's color fills both screens)
- `0.0` = neutral start, boundary sits exactly at the seam between the two phones

Each device only ever renders **its own rectangle** of this shared world. Devices never send each other pixels or positions — they send **tap events**, and each device independently computes the same result from the same event log. This keeps the game trivially resilient to lag (a late-arriving tap just slots into the timeline and the boundary recomputes — no visible correction needed at this scale).

---

## Setup

- **Two teams**: Blue (top phone(s)) and Red (bottom phone(s)). Always even team sizes (1v1, 2v2, 3v3).
- **Orientation**: phones face each other vertically, portrait. Top phone(s) show blue as "their side," bottom phone(s) show red as "their side."
- **Countdown**: host device (or server) broadcasts a synced future timestamp `t_go`. All devices display 3-2-1-GO locally against their synced clock. Taps before `t_go` do not count.

---

## The shared state

```
boundary: float, range [-1.0, +1.0], starts at 0.0
roundStartTime: timestamp, set at t_go
```

## Tap events

Every tap is broadcast as a minimal event:

```
{ team: "blue" | "red", timestamp: t }
```

All devices maintain the same ordered log of tap events (ordered by timestamp, not arrival order — a tap that arrives late but timestamped earlier gets inserted in its correct place and the boundary is recomputed from that point forward).

## The growing-power formula

Each tap's push strength is not constant — it scales with how far into the round it lands. This is the entire mechanic that distinguishes Option A.

```
elapsed = tap.timestamp - roundStartTime
pushStrength = basePush * (1 + elapsed / rampWindow)
```

Where:
- `basePush` — the strength of a tap at t=0 (tune so a solo player needs ~15-25 taps to move the boundary meaningfully at the start)
- `rampWindow` — how many seconds until push strength has doubled (tune this as the main "how fast does it snowball" knob — start with something like 15s)

Applying a tap:

```
if team == blue: boundary -= pushStrength
if team == red:  boundary += pushStrength
```

Recomputing `boundary` at any time `t` = replay every tap event with `timestamp <= t` through the formula above, in timestamp order, starting from `0.0`.

**Effect in play:** early taps feel light and evenly matched — the round can go back and forth. But every tap gets stronger as the clock runs, so once one side pulls even slightly ahead, their taps start hitting harder in absolute terms too, and the round runs away quickly. A round cannot stall indefinitely because *all* taps are getting more powerful, which mechanically prevents a long grinding stalemate — someone always breaks through as the ramp escalates.

---

## Rendering

Each device:
1. Reads the current `boundary` value (recomputed every frame from the tap log).
2. Maps its own screen rect onto the shared `[-1.0, +1.0]` world axis (top phone owns roughly `[-1.0, 0.0]`, bottom phone owns `[0.0, +1.0]`, adjust based on team-size / stacking rules).
3. Draws blue below `boundary`, red above it, within its own rect only.
4. Because both devices share the same world axis and the same `boundary` value, the color line lines up across the physical seam between phones.

Suggested rendering detail: a soft gradient or subtle animated "flood" texture at the boundary edge itself (not a hard ruler-line) reads better on camera than a flat color cut.

---

## Win condition

Round ends the instant `boundary` reaches `-1.0` (blue wins) or `+1.0` (red wins). Show a brief full-screen color-flood result state (loser's screen fully overtaken by winner's color) before returning to lobby / next round.

---

## Multi-device teams (2v2, 3v3)

- Every tap from any teammate on the same team applies the same push formula independently — i.e. team push is the **sum** of each individual tap's `pushStrength`, not a single shared tap budget.
- Optional (flag as tunable, not required for first build): apply mild diminishing returns per simultaneous tap burst from the same team so 3v3 isn't literally 3x the raw speed of 1v1 — e.g. cap effective taps/second counted per team. Ship without this first; add only if playtesting shows 3v3 rounds end too fast to be fun.

---

## Tunable parameters (expose as constants for easy playtesting)

| Parameter | Description | Starting guess |
|---|---|---|
| `basePush` | boundary movement per tap at t=0 | tune so ~20 solo taps = full swing at start |
| `rampWindow` | seconds for push strength to double | 15s |
| `maxRoundLength` | hard safety cap — if no winner by this time, resolve immediately (see note below) | 45s |

**Safety note:** even with growing power, a perfectly even back-and-forth 1v1 could theoretically run long. Add a hard `maxRoundLength` cap as a backstop — if reached, whichever side is even marginally ahead when the cap hits wins instantly (sudden death snap). This guarantees the minigame always respects the 90-second play rule regardless of edge cases in tuning.

---

## What this variant should feel like
Loose and scrappy at the start, then a visible, almost adrenaline-spiking acceleration as the round tips — the tap-tap-tap sound and visual flood speed up together. Good camera moment: the boundary suddenly "breaking" and flooding fast in the last few seconds after a slow tug in the middle.
