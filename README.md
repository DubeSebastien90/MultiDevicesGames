# Multiscreen Slingshot — v1 prototype

Several phones laid side by side on a table become **one shared game world**. One
phone runs the authoritative simulation; every phone is a viewport onto it.

The games are deliberately tiny — an Angry-Birds-style slingshot, and a bin that
catches falling balls. The point is not the games. It is **the seam**: when the
bird flies off one phone's screen, across the physical gap, and onto the next
one, it has to look like one continuous motion across one continuous screen. The
ball bin is the same trick turned ninety degrees.

Built to [`multiscreen-game-v1-spec.md`](multiscreen-game-v1-spec.md).

## Running it

```bash
flutter pub get
flutter run                # pick a device; two phones on the same WiFi
```

On the first phone tap **Host a game**, name it, and it shows a 5-digit code.
On the second tap **Join a game**: your friend's game is already in the list —
pick it and type the code. Then:

1. Check the measurements in the lobby (see *Millimetres* below).
2. Host taps **Play**. The game decides where every phone goes, and everyone is
   told at once — there is no arrangement screen to review.
3. Each phone shows where to sit. Push them together, tap **In place — confirm**.
4. Play. Win, and the next minigame starts — with a different arrangement.
   The list is played through **once**, then everyone is back in the lobby.

The host is a player too — it renders its own viewport through the same code path
as everybody else.

## It is an SDK now

The platform owns lobby, discovery, transport, the shared timeline and the
camera. A game owns its rules, its pixels, and **where the phones go**. The whole
contract is four members:

```dart
abstract class MultiscreenGame {
  GameManifest get manifest;                    // who am I, how many phones
  BoardPlan planBoard(LobbyInfo lobby);         // where do the phones go
  GameSim createSim(BoardContext context);      // rules   — host only
  GameView createView(ViewContext context);     // pixels  — every phone
}
```

Full write-up in [`sdk-architecture.md`](sdk-architecture.md).

| Game | Layout it asks for | Board | Won by |
| --- | --- | --- | --- |
| **Slingshot** | `Layouts.row`, smallest first | wide and short | hitting the tower |
| **Ball Bin** | `Layouts.column`, largest last | narrow and tall | catching 10 balls |
| **Hot Potato** | `Layouts.circle`, join order | a ring | not holding it at the end |
| **Flood** | `Layouts.grid`, 2 rows, upright | two rows facing each other | flooding the other team off the board |
| **Flood: Closing In** | the same grid | the same | holding the lead as the field closes |

Adding a third is a folder under `games/` and one line in `sdk/catalog.dart`.
Transport, layout, snapshots and interpolation never learn its name.

---

# Writing a game

**Read this before touching anything. If you are an AI agent, this section is
the brief.**

## The one rule

> **Do not modify anything under `lib/sdk/`.**
>
> A new game — new rules, new layout, new artwork, no physics, whatever it needs
> — is written entirely inside `lib/games/<your_game>/`. The platform is
> finished. If it looks like you need to change it, you have almost certainly
> missed something the contract already gives you.

There is **exactly one exception**, and it is one line:

```dart
// lib/sdk/catalog.dart
import '../games/your_game/your_game.dart';   // ← add this

static const playlist = <MultiscreenGame>[
  SlingshotGame(),
  BallBinGame(),
  HotPotatoGame(),
  YourGame(),                                 // ← and this
];
```

That file exists *to be* the seam. Nothing else in `sdk/` names a game, and
that is checked: `grep -rn "Slingshot" lib/sdk/` returns only `catalog.dart`.

If your game ships images or sounds, you also add them to `assets/games/<id>/`
and declare the folder in `pubspec.yaml`. That is the whole list of files
outside your own folder.

### When the platform genuinely is missing something

Rarely, and it wants saying out loud rather than quietly. Adding Flood turned up
two, and both are in `sdk/` on purpose:

- **`Layouts.grid`** — `row`, `column` and `circle` pack one axis. Two rows of
  players facing each other is two axes, and it is not a Flood idea: any
  team-versus-team game wants it. It went in as a helper beside the others
  rather than living in one game's folder.
- **`host_session.dart` catching a failed `createSim`** — `planBoard` was
  already guarded, but a game that refuses at `createSim` threw straight
  through the phase transition, and every phone sat on the placement screen
  forever with nothing on any screen to say why. That is a platform gap; Flood
  merely found it first.

The test is whether the next game would want it too. If the answer is no, it
belongs in your folder — Flood's `overlap` helper stayed in `FloodView` for
exactly that reason, because filling regions rather than drawing entities is
peculiar to it.

## What you implement

Four members. That is the entire contract.

```dart
class YourGame implements MultiscreenGame {
  const YourGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'yourgame',                    // stable, wire-visible
    title: 'Your Game',
    tagline: 'One line, shown before the round.',
    goal: 'How it ends, in the player\'s words.',
    players: PlayerCount.range(min: 2, max: 6),
    supportsIpad: false,               // claim it only once you have tried one
  );

  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(lobby.phones);

  @override
  GameSim createSim(BoardContext context) => YourSim(context);   // host only

  @override
  GameView createView(ViewContext context) => YourView();        // every phone
}
```

### `manifest` — who you are, and what table you need

`PlayerCount` has four shapes. Reach for the last only when nothing else fits:

```dart
PlayerCount.range(min: 3)                                    // 3 or more
PlayerCount.range(min: 2, max: 8, parity: CountParity.even)  // teams
PlayerCount.exactly(2)                                       // head to head
PlayerCount.anyOf([3, 5, 9])                                 // escape hatch
```

The lobby greys your game out and explains why, entirely from this. You write no
UI for it.

### `planBoard` — where the phones go

Called the moment your game is chosen, *before* anything is broadcast, so a bad
plan fails on the host's screen instead of sending everyone to rearrange a table
for a round that cannot start.

You are handed a `LobbyInfo`:

| What you get | Meaning |
| --- | --- |
| `phones` | `List<PhoneSpec>`, in join order — which means nothing physical |
| `phoneCount` | how many |
| `byId(id)` | lookup |

And per phone (`PhoneSpec`):

| Field | Meaning |
| --- | --- |
| `phoneId` | `'p1'`, stable for the connection |
| `label` | `'Pixel 7'`, for diagrams |
| `widthMm`, `heightMm` | **portrait**: width is the *short* edge |
| `bezelMm` | casing edge to first lit pixel |
| `dpi`, `devicePixelRatio` | density |
| `activePxWidth`, `activePxHeight` | resolution |
| `areaMm2`, `diagonalMm` | derived, for sorting by size |

Use a helper unless you genuinely need something else:

```dart
Layouts.row(lobby.phones, sort: PhoneSort.smallestFirst)   // wide runway
Layouts.column(lobby.phones, sort: PhoneSort.largestLast)  // tall well
Layouts.circle(lobby.phones)                               // ring, 3+ phones
Layouts.grid(lobby.phones, rows: 2)                        // teams facing off
```

`grid` is the two-axis one: it fills row by row, so with `rows: 2` the first
half of the sorted phones is the top row and the second half the bottom. Rows
are pulled toward the seam they share, so a shallower phone gives up its far
edge rather than its front line — which matters when the game happens at the
seam. Flood uses it; anything team-versus-team wants the same shape.

Every helper returns a plain `BoardPlan`, so you can call one and then nudge a
single phone with `withPlacement`. Or build placements yourself — position is
the **centre** of the lit area in millimetres, plus `turnDeg` clockwise:

```dart
BoardPlan([
  PhonePlacement('p1', xMm: 0,   yMm: 0, turnDeg: 90),
  PhonePlacement('p2', xMm: 160, yMm: 0, turnDeg: 90),
], instruction: 'Side by side, on their sides.')
```

The compiler **refuses** a plan that overlaps two screens, leaves a phone
unplaced, names a phone that is not there, or strands one far from the rest.
Pass `allowGaps: true` if the spacing is deliberate, as a ring's is.

### `createSim` — the rules, host only

```dart
abstract class GameSim {
  void step(double dt);                 // fixed 60Hz
  void onTouch(TouchEvent touch);       // world coordinates, tagged by phone
  Iterable<Entity> get entities;        // everything drawable, right now
  Map<String, Object?> get sharedState; // slow-changing values, e.g. phase
  GameOutcome? get outcome;             // non-null ends the round
  void reset();
}
```

`BoardContext` gives you:

| What you get | Meaning |
| --- | --- |
| `board` | the playfield, `WorldRect`, world units |
| `coverage` | which parts are backed by a screen; `seamRects()` |
| `scores` | the session scoreboard, **writable** |
| `slices` | named screen rectangles, turn included |
| `phoneAt(x, y)` | whose screen is this point on? |
| `nearestPhone(x, y)` | same, but never null |

### `createView` — the pixels, every phone

Each frame you are handed a `Frame`:

| What you get | Meaning |
| --- | --- |
| `entities` | interpolated to this instant, by id |
| `sharedState`, `scores` | as the sim published them |
| `timeMs` | the **shared** clock — identical on every phone |
| `dt` | local frame delta, for effects that need not agree |
| `me` | this phone's `PhoneLayout` |
| `board`, `coverage`, `visible` | geometry, and what to cull against |
| `onePixel` | one physical pixel in world units, for stroke widths |
| `ofKind(kind)`, `byId(id)` | convenience |

The canvas arrives with the camera applied: draw at world coordinates and it
lands correctly, at true physical scale, on whichever phone can see it.

## Physics is optional

Two starting points. Pick by whether you have anything to integrate.

**No physics** — extend `GameSim` directly and link no engine. Hot Potato does
this: its whole world is "who is holding it" and "how long is left".

```dart
class YourSim implements GameSim { ... }
```

**Physics** — extend `Forge2DGameSim`, which wires up a world and the
body↔entity plumbing. Build in your constructor body with `addBody`:

```dart
class YourSim extends Forge2DGameSim {
  YourSim(super.context) : super(gravity: Vector2(0, 9)) {
    addBoundaryWalls();
    addBody('ball', 'ball', BodyDef(type: BodyType.dynamic, position: ...),
        props: {ShapeProps.shape: ShapeKind.circle, ShapeProps.radius: 0.5});
  }
}
```

`hide(id)` / `show(id)` park a body without destroying it — how Ball Bin
recycles a pool of six balls.

**Even with no physics, still use entities.** Physics is optional; the
platform's interpolation is not. An entity's transform is smoothed onto the
shared timeline, so easing one toward a new position makes it visibly slide
across the table on every screen at once, in step. That is the whole point of
the project, and it costs you a lerp.

## Rendering: free, or your own

**Free** — return a `ShapeView`. It draws every entity from its props, and a
prototype gets a working picture without a line of paint code:

```dart
GameView createView(ViewContext c) => ShapeView();
// entity props: shape (circle|box), r / w+h, color, spin
```

**Extend it** — keep the shapes and add your own layer, which is what Slingshot
does for its rubber band:

```dart
class YourView extends ShapeView {
  @override
  void renderForeground(Canvas canvas, Frame frame) { ... }
}
```

**Replace it** — implement `GameView.render` outright for full custom art. Load
sprites in `load()`, which is awaited during the placement screen so nothing
blocks a frame mid-round.

**A HUD is Flutter widgets**, not canvas painting:

```dart
@override
Widget? buildHud(BuildContext context, HudFrame frame) =>
    Text('${frame.sharedState['caught']} / 10');
```

## Connectors: not your job

Those coloured stripes players line their phones up against — **you do nothing
about them.** There is no field for them on the manifest, no hook to implement,
nothing to draw. They are not even in your `Frame`, deliberately.

They fall out of the compiled geometry: after `planBoard` returns, `BoardLinks`
judges every pair of screens, and the answer travels with the layout. It is
computed once, on the host, so two phones can never disagree about which edge is
red. That one rule covers rows, columns, grids and rings without knowing any of
their names — which is exactly why it does not need your help.

The only lever you have is the plan you return:

| What your plan does | What players see |
| --- | --- |
| Two screens within 40mm of each other, sharing some edge | A stripe on each facing edge, same colour, spanning only the length they share |
| Three or more screens touching nothing — a ring, or `allowGaps: true` | A neutral stripe on the edge facing the middle, **plus** a paired-colour stripe facing the neighbour on each side, so the order round the circle is unambiguous |
| Two screens touching nothing | The neutral middle-facing stripe only. Two phones across a table are one relationship, not a loop |
| A single phone alone | No stripe. There is nothing to line it up with |
| A gap wider than 40mm without `allowGaps` | A validation error. The round refuses to start and the host is told which phone is stranded |

Two things follow from this, and both are load-bearing:

**Do not draw your own alignment hints.** Yours would be computed from different
numbers and would disagree with the SDK's on somebody's screen. Connectors also
only appear during placement, then get out of the way — a round is your canvas
alone.

**A wrong-looking connector is never a bug in your game.** It comes from the plan
or from a phone's measurements, most often `bezelMm`. `BoardLinks.explain()`
judges every pair and returns the reason it did or did not join, in words — call
it on `board.slices` and read the verdicts before touching anything of your own.

## Scoring

Score belongs to the lobby and survives every round. Award it and nothing else:

```dart
context.scores.award(phoneId, 10);   // or a negative number
context.scores.awardAll(5);          // co-operative
```

The platform shows standings in the lobby and on the results screen, and shows
**nothing at all** until somebody scores — so a co-operative game that never
awards is completely normal.

## Five rules that will break the seam if you ignore them

1. **`step(dt)` must be pure with respect to wall-clock time.** No
   `DateTime.now()`, no timers. Accumulate `dt`. The platform decides when time
   passes, and that is what keeps every screen agreeing.
2. **`render` must not mutate game state.** It runs on every device at each
   device's own frame rate. The host's sim is the only writer; a view is a pure
   function of its `Frame`.
3. **Award points in `step`, never in the `outcome` getter.** `outcome` is polled
   more than once per tick, so awarding there double-charges. Latch it:
   `if (!_awarded) { _awarded = true; scores.award(...); }`
4. **An entity's `kind` and `props` are immutable.** Declared once when it
   appears. Only the transform moves per tick, and only the transform is
   interpolated.
5. **Animate from `frame.timeMs`, not a local clock.** Two phones on separate
   clocks pulse out of step.

## Checklist for a new game

```
lib/games/your_game/
  your_game.dart          implements MultiscreenGame — the four members
  your_game_sim.dart      the rules (GameSim, or Forge2DGameSim)
  your_game_view.dart     the pixels (ShapeView, or GameView)
  your_game_config.dart   your tunables, as plain data
```

- [ ] Registered in `sdk/catalog.dart` (one import, one list entry)
- [ ] `manifest.players` says the truth about your table
- [ ] `planBoard` uses a helper, or a plan the compiler accepts
- [ ] Nothing under `lib/sdk/` modified
- [ ] No alignment hints of your own — connectors are the platform's job
- [ ] `flutter analyze` clean, `flutter test` green
- [ ] A test that drives the sim headlessly — see `test/hot_potato_test.dart`,
      which plays a whole round with no host, no sockets and no rendering

---

## Score

Score belongs to the lobby, not to a game: one running total per phone that
survives across rounds, so a table can play five minigames and still know who is
winning. A game calls `scores.award(phoneId, points)`; the platform does the
rest, and shows nothing at all until somebody actually scores — both shipped
games are co-operative, and Ball Bin is the only one that credits catches to
individual phones.

### A float in `sharedState` is a 60 Hz stream

Worth writing down, because it is invisible and the next game to skip entities
will hit it. `sharedState` is diffed by the host every tick and sent *only when
it changed* — which quietly stops being true the moment a value in it changes
every tick. Flood's first version put the raw round clock in the map, so every
diff differed, and an untouched board pushed a packet sixty times a second
forever.

The fix is to broadcast at the precision the screen can actually show: the
countdown as the whole second the HUD prints, the boundary to a thousandth of
the axis, the ramp and the closing field to a hundredth. An idle board went from
600 messages per ten seconds to fewer than fifty, and nothing on screen looks any
different. `flood_test.dart` pins it, because the failure mode is a network
becoming busy rather than anything visibly breaking.

Scanning the host's QR instead skips the code — it carries `ws://<ip>:<port>#<code>`,
and standing in front of the screen is the same proof the code asks for. Typing
the address by hand still works too; both fallbacks are on every device, because
broadcast is the first thing a locked-down network drops.

It also runs on Windows desktop, which is the fastest way to iterate: launch two
instances, tap **Type address** and join `127.0.0.1:8080` with the host's code.
Bezels default to 0mm there, so the two windows behave as one gapless board.

## Architecture

```
lib/
  sdk/          the platform — knows nothing about any particular game
    contract/     MultiscreenGame, GameSim, GameView, Entity, Frame
    layout/       PhoneSpec, BoardPlan, Layouts.row/column, BoardCompiler
    physics/      Forge2DGameSim base class, DeadZones helpers
    render/       ShapeView — the default renderer, for games without art
    score/        Scoreboard: per-phone, survives every round
    model/        PhoneLayout (the transforms), CoverageMap, WorldRect
    net/          Transport + WebSocket, loopback, discovery beacon
    host/         HostSession (the only thing that runs a simulation)
    client/       ClientSession, SnapshotBuffer (the interpolator), ViewportGame
    ui/           role → lobby → placement → game → results
    catalog.dart  the playlist — the ONLY file in sdk/ that knows games/ exists
  games/
    slingshot/     game + sim + view + config
    ball_bin/      game + sim + view + config
    flood_common/  board, config, and the sim/view both variants share
    flood/         Flood — growing tap power
    flood_closing/ Flood: Closing In — shrinking field
  main.dart
```

`sdk/` imports from `games/` in exactly one file. That is what makes the
boundary real, and it is the line a package extraction would cut along.

Server-authoritative, client-side viewport rendering:

- **The host owns the world.** A continuous coordinate space holding all physics.
  A `GameSim` imports no Flutter and no Flame — a client cannot accidentally
  become a second source of truth.
- **Phones send raw local input** as physical pixels. The host converts to world
  coordinates using that phone's offset, because only the host knows where that
  screen sits.
- **Clients render, and only render.** A game's `GameView` runs on every phone
  and paints whatever it likes, but it is a pure function of the `Frame` it is
  handed. The host is the only writer.
- **Only transforms are interpolated.** An entity declares its kind and its
  fixed properties once; what moves every tick is `(x, y, angle)`, and that is
  the one thing the platform smooths. It is what lets a game own its pixels
  without being able to break the seam.

### Coordinates

1 world unit = 1cm. Two 152mm phones make a board about 31 × 7 units. Each phone
gets a `worldOffset` and the *shared* `mmToWorld` scale, so a phone at 400dpi and
one at 267dpi draw the same world at the same physical size.

The whole mapping is two mutually inverse functions in `PhoneLayout`:
`physicalPxToWorld` for touches, `worldToPhysicalPx` for rendering. A test pins
them as exact inverses, because a drift between them would desynchronise both the
grab and the seam.

### Why the seam works

Two things, and neither is obvious:

**1. Everyone renders the past.** Each phone plays the snapshot stream back on a
clock 80ms behind the host and interpolates between the two snapshots bracketing
it. Rendering the *newest* snapshot on arrival would put each phone wherever the
network last left it, and the bird would step sideways crossing the gap.

**2. The host renders the past too.** The host reaches its own screen through an
in-memory `LoopbackPair` that satisfies the same `Transport` interface as a
socket. Without that it would draw straight from the live sim, sit a full
interpolation delay *ahead* of every other screen, and produce exactly the jump
this prototype exists to avoid.

The render clock is built as `localTime + offset - delay`, so it advances at
exactly local frame rate and a phone's frame *pacing* cannot move it. An earlier
version nudged the clock's rate toward `newest - delay` instead; a phone
rendering at a different frame rate settled at a different offset — about 0.8mm
of disagreement at 20cm/s. A test caught it (`snapshot_buffer_test.dart`, the
frame-pacing case) and the offset formulation fixed it.

The offset itself rises immediately and decays slowly: latency can only ever make
a snapshot look *older* than it is, so the largest offset seen recently is the
best estimate of the host's clock. No clock synchronisation protocol is needed.

### The board and its dead zones

The world is continuous and physics runs **everywhere**, including the
millimetres of bezel between two screens. The bird keeps flying through the gap
and emerges on the next screen exactly where momentum says. A `CoverageMap` of
live rectangles is metadata on top (`isCovered(x, y)`), and v1's policy is to
ignore it — a dead zone is just a wider seam.

The board hugs the covered area: its height is the *shortest* screen, so the only
dead zones are real bezel gaps and they all mean the same thing.

## Millimetres, and the honest limitation

Calibration works in millimetres, not pixels. Flutter only exposes a density
*bucket*, not the panel's real DPI, so the derived size can be several percent
out — several millimetres of seam misalignment. **The measurements are editable**
(tap *Measure*): a ruler across the glass beats any estimate.

And nothing verifies the phones are actually where the host thinks they are.
**Confirm is a human promise, not a sensor reading.** The placement screen makes
a wrong promise visible instead: its guide lines and the circle straddling the
seam are drawn in world coordinates, so on correctly placed phones they run
unbroken across the gap. A step means the placement or a measurement is off. The
bezel gap hides small errors anyway.

## Debug overlay

The bug icon during play opens readouts and, most usefully, an **interpolation
delay slider**. Drag it to 0 and the bird stutters — that is the jitter the
buffer normally hides. It also toggles the 1cm world grid (unbroken grid lines
across the gap are a live calibration check) and marks the dead zone.

## Networking gotchas

Both phones must be on the same WiFi, and that network must let devices talk to
each other.

- **Guest/public WiFi** usually has client isolation → no beacons arrive and the
  join list stays empty. The QR and typed address are right there for this.
- **One phone on cellular** → not the same LAN → no connection.
- **Escape hatch, no code change:** run a hotspot on one phone and join it from
  the other. The same WebSocket code works unchanged.
- **iOS 14+** wants the `com.apple.developer.networking.multicast` entitlement
  before an app may broadcast. Without it the beacon never leaves the phone:
  hosting and joining still work, and joiners use the QR. Requesting it from
  Apple is the only thing that turns the list on for iOS — the app needs no
  change.
- **macOS** is sandboxed, and Flutter's template grants
  `com.apple.security.network.server` but *not* `network.client` — and the
  release profile grants neither. Without the client entitlement the sandbox
  denies every outgoing operation: joining a game, and sending the beacon. The
  latter shows up as `SocketException: Send failed (OS Error: Operation not
  permitted, errno = 1)`, which reads like a bug in the app rather than a
  permission it was never given. Both are granted in
  `macos/Runner/*.entitlements`; macOS needs no multicast entitlement.
- **Android** filters broadcast traffic in the WiFi chip unless a `MulticastLock`
  is held; `MainActivity.kt` takes one while the app is in front.
- **A refused send does not throw at the call site.** `RawDatagramSocket.send`
  reports OS refusals asynchronously on the socket's own stream, so the only
  place to catch one is an `onError` on the `listen`. Wrapping `send` in a
  `try`/`catch` looks right and catches nothing.

## Deliberately not built

No TypeScript, no cloud, no dedicated server. No accounts or persistence. No
mDNS/Nearby/Multipeer — discovery is 200 lines of UDP broadcast with a QR and a
typed address behind it, and it never leaves the LAN. No automatic freeform
packing — a game that wants something the `Layouts` helpers cannot express
writes its placements by hand, as Flood's 2×N grid does. No sensor-based placement
verification. No game-definition loader — but game logic is kept as data in
`game/game_config.dart` so that door stays open.

Two doors are held open on purpose: the `Transport` interface, so a lobby server
or Nearby can slot in without touching game code; and the fact that the real-time
loop is local, so an optional cloud layer later sits *beside* it rather than
inside it.

## Known rough edges

- Dragging feels 80ms late **on the phone doing the dragging**, because that
  phone renders the same delayed timeline as everyone else. Consistency across
  screens is the v1 priority; the slider makes the trade visible. Client-side
  prediction for the dragging phone only is the real fix, and it belongs to
  whatever comes after this.
- A phone that joins after the board is laid out is turned away — joining
  mid-game would invalidate a board people physically arranged. Re-calibrate from
  the debug panel instead.
- If a phone disconnects mid-game the world keeps running and its slice goes
  dark, rather than silently rearranging the board.
- Launch feel is tuned for a two-phone board and scaled by `sqrt(width)` from
  there, so a four-phone board needs more shots to cross.
- Measurements are not persisted, so they need re-entering each launch.
- On desktop, resizing the window after the board is laid out leaves the recorded
  viewport extent stale (phones do not resize).
