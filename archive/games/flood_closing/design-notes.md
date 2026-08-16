# Push-o'-War — Option B: Shrinking Playfield

## One-line pitch
Two phones face each other. One shared boundary line splits the world into blue territory and red territory. Tapping pushes the line toward the opponent, at a constant, fair push-per-tap — but the contested play area itself visibly narrows over time, so any lead gets swallowed by the shrinking field and the round is guaranteed to resolve fast.

---

## Core concept

There is exactly **one shared world**, a vertical strip running through both devices, same as a physical table with two phones laid end to end. Two separate values drive what's on screen:

- `boundary`: float, range `[-1.0, +1.0]`, starts at `0.0` — this is the raw, unshrunk tug-of-war position, and it moves at a flat, constant rate per tap (no ramping, unlike Option A).
- `contestedRange(t)`: how wide the "still undecided" window is, shrinking as a function of elapsed round time — this is what actually gets rendered.

Each device only ever renders **its own rectangle** of this shared world. Devices never send each other pixels or positions — they send **tap events**, and each device independently computes the same result from the same event log, keeping the game resilient to lag (a late tap just slots into the timeline and everything recomputes — no visible correction at this scale).

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

All devices maintain the same ordered log of tap events (ordered by timestamp, not arrival order). Applying a tap is flat and constant — this is the key difference from Option A:

```
if team == blue: boundary -= basePush
if team == red:  boundary += basePush
```

`boundary` at any time `t` = replay every tap event with `timestamp <= t` in order, starting from `0.0`, always using the same `basePush` regardless of elapsed time.

## The shrinking-range formula

This is the entire mechanic that distinguishes Option B. The raw `boundary` value never changes how it's computed — instead, the **window used to render and check for a win** shrinks over time:

```
elapsed = now - roundStartTime
rangeScale = max(minScale, 1 - elapsed / shrinkWindow)
```

Where:
- `shrinkWindow` — seconds until the field has shrunk to its minimum size (main tuning knob — start with something like 25s)
- `minScale` — the floor the range shrinks to, never zero, so there's always a sliver of contested space and the game doesn't become unwinnably twitchy (start with something like 0.15)

The **rendered / win-check boundary** is:

```
effectiveBoundary = boundary * (1 / rangeScale)
```

Then clamp `effectiveBoundary` to `[-1.0, +1.0]` for both rendering and the win check. Because `rangeScale` shrinks over time, the same raw `boundary` value maps to a larger and larger swing in `effectiveBoundary` — a lead that looked minor early in the round becomes decisive later, purely because the field around it has narrowed.

**Effect in play:** taps always feel the same weight (fair, no ramping), but the *visible contested strip* — the sliver of screen near the seam where the color is still undecided — visibly narrows over the course of the round. A small lead that wasn't enough to win a few seconds ago suddenly is, because the goalposts moved in. This reads very clearly on camera: the neutral zone visibly closing in from both sides.

---

## Rendering

Each device:
1. Reads the current `effectiveBoundary` value (recomputed every frame).
2. Maps its own screen rect onto the shared `[-1.0, +1.0]` world axis (top phone owns roughly `[-1.0, 0.0]`, bottom phone owns `[0.0, +1.0]`, adjust based on team-size / stacking rules).
3. Draws blue below `effectiveBoundary`, red above it, within its own rect only.
4. **Visualize the shrink directly**: render the "still contested" zone (the band around the boundary that could still move) as a visibly narrowing strip — e.g. a lighter/striped/pulsing band that gets thinner as `rangeScale` decreases. This is the signature visual of this variant and should be legible without a timer or any UI text — the narrowing band *is* the countdown pressure.

Suggested rendering detail: keep the boundary edge itself soft (flood/gradient, not a hard line), same as Option A, but make the shrinking contested band an obvious, separate visual element so viewers can see the round "closing in."

---

## Win condition

Round ends the instant `effectiveBoundary` reaches `-1.0` (blue wins) or `+1.0` (red wins). Because the range keeps shrinking (down to `minScale`), even a very slight, stable lead will eventually cross the win threshold — the round is mathematically guaranteed to end. Show a brief full-screen color-flood result state before returning to lobby / next round.

---

## Multi-device teams (2v2, 3v3)

- Every tap from any teammate on the same team applies the same flat `basePush` independently — team push is the **sum** of individual taps, not a shared budget.
- Optional (flag as tunable, not required for first build): mild diminishing returns per simultaneous tap burst from the same team, so 3v3 doesn't finish drastically faster than 1v1 purely from raw tap volume. Ship without this first; add only if playtesting shows an issue.
- Note: the shrink mechanic is a *global clock*, identical regardless of team size — this is one of its advantages over Option A, since no per-player tuning is needed for the pacing mechanism itself.

---

## Tunable parameters (expose as constants for easy playtesting)

| Parameter | Description | Starting guess |
|---|---|---|
| `basePush` | flat boundary movement per tap, constant all round | tune so ~20 solo taps = full swing with no shrink applied |
| `shrinkWindow` | seconds until field reaches minimum size | 25s |
| `minScale` | floor for `rangeScale`, prevents the field from vanishing entirely | 0.15 |

**Safety note:** because `minScale` puts a floor on how far the range shrinks, a perfectly even 1v1 (zero net boundary movement) could in theory never resolve. Add the same `maxRoundLength` hard backstop as Option A — if reached with no winner, resolve instantly in favor of whoever has the marginal lead (sudden-death snap). Start with `maxRoundLength = 45s`.

---

## What this variant should feel like
Steady, fair mashing throughout — no sudden power spikes — but mounting visual tension as the neutral zone visibly narrows on both screens simultaneously. Good camera moment: the strip of "still undecided" space closing to almost nothing while both teams are still mashing at full speed, then a sudden win the instant it closes.
