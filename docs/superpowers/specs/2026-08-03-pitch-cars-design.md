# Pitch Cars — design

A new game under `games/pitch_cars/`, implementing `MultiscreenGame`. Inspired by
the physical board game Pitch Car: a pichenotte (flick) racer where players
launch a car around a track built from the phones on the table, and can fall
off the track's edge into dead space — including by being knocked off by
another player's car.

## Manifest

```dart
GameManifest(
  id: 'pitch_cars',
  title: 'Pitch Cars',
  tagline: 'Flick your car around a randomized track.',
  goal: 'First past the finish line.',
  players: PlayerCount.range(min: 2, max: 4),
)
```

One car per phone. Turn-based: exactly one player's car may be flicked at a
time, in join order, wrapping.

## Board & track topology

`planBoard` randomly chooses a topology each game:

- **2–3 phones → always "line."** `Layouts.row` arranges the phones in a
  straight strip (existing SDK helper, no changes needed). The *track path*
  drawn across that strip is a random centerline that snakes left-to-right —
  forced minimum curvature per phone-width segment so it is never straight —
  from a start line on the first phone to a finish line on the last.
- **Exactly 4 phones → coin-flip between "line" and "loop."** Loop uses
  `Layouts.circle(phones)` — the existing ring layout (already proven by
  `HotPotatoGame`), which turns all 4 phones to face outward with a deliberate
  gap (`allowGaps: true`), leaving a real hole in the middle. One full lap
  around that ring wins. No new SDK layout code — a true rotated ring, not an
  axis-aligned approximation.

Track representation (per phone cluster, regardless of topology): a chain of
waypoints forming a centerline, with a fixed `trackWidthWorld`. A point is
"on track" if its perpendicular distance to the nearest centerline segment is
≤ `trackWidthWorld / 2`. Everything beyond that is dead space a car can fall
into — this lives entirely in `games/pitch_cars/track.dart`, analogous to
(but independent from) the platform's `CoverageMap`. No new SDK primitive.

Progress is tracked as arclength along the centerline from the start. Line
finishes at `arclength >= trackLength`; loop finishes at one full circuit
(`arclength >= ringCircumference`).

## Turns & input — never phone-gated

Because the board spans multiple phones and a car can end up physically under
a different phone's screen than the one its owner joined from, turn-taking
must not gate on `TouchEvent.phoneId`. `phoneId` is only remembered after the
touch goes down, to route the rest of that one drag.

Nor does it gate on *where* the touch lands. It originally did — proximity to
the car, the pattern `SlingshotSim` uses for its single shared bird — but a
car that comes to rest against the edge of a screen, or on the seam between
two phones, then has no room to drag towards: half the draw would land on a
neighbour's glass. So a touch anywhere starts an aim, and proximity only picks
which point the draw is measured from:

```dart
void onTouch(TouchEvent touch) {
  final car = _cars[currentTurn]!;
  final p = Vector2(touch.worldX, touch.worldY);
  switch (touch.phase) {
    case down:
      if (_draggingPhoneId != null) return;
      // On the car: the car follows the finger, as a slingshot does.
      // Anywhere else: the finger's displacement from here is the draw.
      _dragOrigin =
          p.distanceTo(car.position) <= reach ? _preTurnPosition : p;
      _draggingPhoneId = touch.phoneId;                  // routes this one drag
      ...
    case move:
      if (_draggingPhoneId != touch.phoneId) return;
      _pull = clamp(_preTurnPosition + (p - _dragOrigin));
    case up:
      if (_draggingPhoneId != touch.phoneId) return;
      _launch();
  }
}
```

Input is pull-back-and-release, reusing Slingshot's aiming interaction
(drag away from the car, release to launch toward it, magnitude scales
impulse). A draw under `PitchCarsConfig.cancelPullFraction` of the maximum is
a tap rather than a shot: nothing fires and the turn is not consumed. The aim
arrow uses that same threshold to appear, so an arrow on screen means the
release will fire.

## Physics & the off-track rule

`PitchCarsSim extends Forge2DGameSim`. Each car is a dynamic circle body.
A Forge2D contact listener sets `lastHitBy = otherCarsOwner` on a car when
another car's body touches it; cleared once that car returns to rest with no
further contact.

Every `step`, each car is checked against the track centerline. A car whose
lateral distance exceeds `trackWidth / 2` is off-track and is reset
immediately:

- `lastHitBy == null` (fell off on its own shot) → snapped back to its
  position **before this turn's flick** — the whole turn is wasted.
- `lastHitBy != null` (knocked off by another car) → snapped to the **last
  on-track point** it had passed through — it keeps the progress it made.

This asymmetry is deliberate: it punishes reckless flicking harder than being
a sabotage victim, which makes bumping opponents a clean tactical choice
rather than a double-punishment for the person bumped.

Once the flicked car (and anything it hit) comes to rest and any off-track
resolution is applied, turn advances to the next connected phone in join
order.

## Rendering, HUD, scoring

- Cars: circle `Entity`s via the default `ShapeView`, one color per player.
  No custom `GameView`.
- Track surface: drawn as a chain of `ShapeView` entities along the
  centerline (on-track ribbon color vs. background dead-space color) — no
  custom canvas rendering needed.
- HUD: `buildHud` shows `sharedState['currentTurn']` and each car's progress
  (e.g. "2/3 laps" or a percentage).
- Scoring: single-shot — first to finish gets
  `context.scores.award(winnerId, 1)` and `GameOutcome.won(summary: ...)`.
  No per-tick scoring.
- Wire cost: none beyond what the contract already sends — cars are ordinary
  `Entity`s (interpolated for free), turn/progress state is plain
  `sharedState`.

## Explicitly out of scope for v1

- Tile-piece track construction (real Pitch Car's modular wooden segments) —
  the waypoint-chain approach was chosen instead for build speed.
- More than 4 phones, or loop topology below/above exactly 4 phones.
- Any new SDK primitive or `Layouts` helper — the design deliberately reuses
  `Layouts.row`, `Layouts.circle`, `Forge2DGameSim`, and `ShapeView` as-is.
