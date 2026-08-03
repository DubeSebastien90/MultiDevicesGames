# Multiscreen SDK — the game contract

**Status: implemented.** Both shipped games run through this contract and
nothing else. Where the built code differs from the original proposal, the
section says so.

Today the platform hard-codes two games. This document turns it into a tool: the
platform owns lobby, discovery, transport, timing and the seam; a game author
owns rules, layout and pixels.

The whole contract is one interface with three parts:

```dart
abstract class MultiscreenGame {
  GameManifest get manifest;                    // who am I, how many phones
  BoardPlan planBoard(LobbyInfo lobby);         // where do the phones go
  GameSim createSim(BoardContext context);      // rules   — host only
  GameView createView(ViewContext context);     // pixels  — every phone
}
```

Everything else in this document is the supporting cast for those four members.

---

## 1. What the platform guarantees

A game author never writes, and cannot break:

- **Discovery and lobby** — the beacon, the 5-digit code, the QR, who is in,
  each phone's physical measurements, and the running standings.
- **Transport** — WebSockets, reconnection, the loopback that makes the host a
  player too.
- **The shared timeline** — a fixed-timestep loop on the host, snapshots at
  60 Hz, and an interpolation buffer on every phone. This is what makes an
  object cross the physical gap without stepping.
- **The camera** — each phone's viewfinder is positioned and zoomed so one world
  unit is the same physical size on every panel, whatever its density.
- **Input plumbing** — a finger on any phone arrives at the host sim already
  converted to world coordinates, tagged with the phone it came from.

## 2. What the game owns

- **How many phones it needs**, so the platform can skip it when it will not fit.
- **Where the phones go** — the arrangement, and which phone goes where in it.
- **The rules** — one authoritative simulation, on the host.
- **The pixels** — a renderer that runs on every phone and draws into that
  phone's slice of the world.
- **The score** — reading and awarding points on the shared, cross-game
  scoreboard.
- **What "winning" means.**

### A game is code in this repo, not a plugin

Worth stating plainly, because it removes a whole category of design problem: a
game author has the project open. They add a folder under `games/`, drop sprites
into `assets/games/<id>/`, add the line to `pubspec.yaml`, and register the game
in the catalog. Their view code imports their own Dart types and their own
assets directly — there is no serialisation boundary between a game's simulation
and a game's renderer, no plugin ABI, no sandbox.

The SDK is therefore *structure*, not isolation. It exists to answer "where does
this code go and what is it handed?" so that adding a game is an afternoon
instead of a rewrite. It is not trying to protect the platform from the game.

One consequence is worth keeping in view. Because the sim runs on the host and
the view runs everywhere, the host↔client hop is still a real network boundary
even though it is not a *code* boundary — which is why §6 is strict about what
crosses it and §7 is strict about the view not mutating anything.

---

## 3. Coordinates, once

One world unit = **1 cm**. The board's top-left is `(0, 0)`; **y grows
downward** everywhere — physics, rendering, touches. Layout is authored in
**millimetres**, because that is what a ruler and a spec sheet give you; the SDK
converts. A game never sees a pixel unless it asks the frame for one.

---

## 4. Describing a game

```dart
class GameManifest {
  final String id;            // stable, wire-visible: 'slingshot'
  final String title;         // 'Slingshot'
  final String tagline;       // one line on the arrangement screen
  final String goal;          // 'Hit the tower to win.'

  final int minPhones;        // below this the platform skips the game
  final int maxPhones;        // above this, likewise
}
```

`minPhones`/`maxPhones` are the only thing the lobby needs to decide whether a
game is offerable. One phone is one player; a phone is never two players.

---

## 5. Deciding the layout

The game is handed everything known about the connected phones and returns an
explicit position for each.

```dart
class PhoneSpec {
  final String phoneId;       // 'p1'
  final String label;         // 'Pixel 7'
  final double widthMm, heightMm;   // active area, landscape
  final double bezelMm;             // casing edge to lit pixel
  final double dpi, devicePixelRatio;
  final double activePxWidth, activePxHeight;

  double get areaMm2 => widthMm * heightMm;
  double get diagonalMm => ...;
}

class LobbyInfo {
  final List<PhoneSpec> phones;   // in join order
  int get phoneCount => phones.length;
}
```

### The primitive

```dart
class PhonePlacement {
  const PhonePlacement(this.phoneId, {required this.xMm, required this.yMm});
  final String phoneId;
  final double xMm, yMm;      // top-left lit pixel of this screen, in board mm
}

class BoardPlan {
  const BoardPlan(this.placements, {this.instruction, this.hintPerPhone});

  final List<PhonePlacement> placements;

  /// 'Stack the phones one above the other, long edges touching.'
  final String? instruction;

  /// Optional per-phone line: 'below the big one'.
  final Map<String, String>? hintPerPhone;
}
```

Positions are of the **lit area**, not the casing. Bezels are the game's
business precisely because a game may want the screens touching (bezels leave a
gap the ball flies through) or deliberately spaced.

### The helpers, for the common 90%

```dart
BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(
      lobby.phones,
      sort: PhoneSort.smallestFirst,
      align: CrossAlign.start,       // top edges flush
      gap: Gaps.casingsTouching,     // account for both bezels
    );

BoardPlan planBoard(LobbyInfo lobby) => Layouts.column(
      lobby.phones,
      sort: PhoneSort.largestLast,   // biggest phone at the bottom
      align: CrossAlign.start,       // left edges flush
      gap: Gaps.casingsTouching,
    );
```

`PhoneSort` ships `joinOrder`, `smallestFirst`, `largestFirst`,
`smallestLast`, `largestLast`, and `by(Comparator<PhoneSpec>)`.
`Gaps` ships `casingsTouching` (bezel + bezel), `flush` (zero), and
`of(mm)`. Both helpers return an ordinary `BoardPlan`, so a game can call one
and then adjust a placement by hand.

Anything the helpers cannot express — an L, a grid, a ring, a phone deliberately
set apart as a scoreboard — is written directly as placements.

### The plan leads; people follow

`planBoard` is not a suggestion the host then adjusts. It runs the instant a
game is chosen, and the placement screen tells each phone where to go — so the
plan describes the table people are about to build, not one that already exists.
That is what removes the arranging step entirely (§10), and it is why sorting
belongs to the game: only the game knows whether the big phone should be at the
bottom of the well or on the left of the runway.

### What the SDK does with the plan

It validates, then compiles it into the same `BoardLayout` the platform already
uses: per-phone world offsets, the board bounds, and a `CoverageMap`.

Validation is a hard error at development time, surfaced on the host screen:

- every connected phone placed exactly once, no unknown phone ids
- no two lit areas overlapping
- the board connected — no phone floating with no neighbour

Overlap is an error rather than a warning because two screens claiming the same
world coordinates is not a layout, it is a bug that will look like a rendering
glitch.

---

## 6. The simulation — host only

```dart
abstract class GameSim {
  /// Advance by exactly [dt] seconds. Called at a fixed 60 Hz.
  void step(double dt);

  /// A finger, already in world coordinates, tagged with its phone.
  void onTouch(TouchEvent touch);

  /// Everything that can be drawn, this instant.
  Iterable<Entity> get entities;

  /// Small, slow-changing values every phone should see: phase, lives, whose
  /// turn it is. Broadcast when it changes, never interpolated. Per-phone
  /// points do NOT go here — that is the platform scoreboard, §8.
  Map<String, Object?> get sharedState;

  /// Non-null ends the round.
  GameOutcome? get outcome;

  /// Put the round back to its opening position.
  void reset();

  void dispose();
}

class TouchEvent {
  final String phoneId;
  final double worldX, worldY;
  final TouchPhase phase;    // down | move | up
  final int pointerId;       // multi-touch, per phone
}

class GameOutcome {
  const GameOutcome.won({this.summary});
  const GameOutcome.lost({this.summary});
  final String? summary;     // '10 caught'
}
```

`step` must be **pure with respect to wall-clock time** — no `DateTime.now()`,
no timers. The platform decides when time passes, which is what keeps the
timeline reproducible and the snapshots evenly spaced.

### Entities

An entity is anything with a position that the SDK will interpolate for you.

```dart
class Entity {
  final String id;            // stable for the entity's lifetime
  final String kind;          // game-defined: 'bird', 'ball', 'bin'
  final Map<String, Object?> props;   // immutable, sent once: radius, colour
  final double x, y, angle;
  final double vx, vy;        // used for extrapolation when a packet is late
}
```

`kind` and `props` are declared when the entity first appears and never change.
Everything that changes per tick is the transform, and the transform is the only
thing the SDK interpolates — that is the deal that keeps the seam exact.

Spawning and despawning are ordinary: return a new id from `entities` and it
appears on every phone; stop returning an id and it vanishes. The SDK diffs the
set and sends `spawn`/`despawn` alongside the snapshot stream.

Anything that is *not* a smoothly moving transform — score, a "level cleared"
flag, whose turn it is — goes in `sharedState`, which is diffed and sent only
when it changes.

### Physics is optional

`GameSim` says nothing about physics. Most games will want it, so the SDK ships:

```dart
abstract class Forge2DGameSim extends GameSim {
  World get world;
  Body addEntity(String id, String kind, BodyDef def, {Map<String, Object?> props});
  // entities/step wired up; you write build() and the rules
}
```

A card game or a puzzle extends `GameSim` directly and never links a physics
engine into its logic.

---

## 7. The renderer — every phone

```dart
abstract class GameView {
  /// Load sprites, fonts, audio. Awaited during the placement screen, so the
  /// game is ready by the time the first frame is asked for.
  Future<void> load();

  /// Paint this phone's slice. Called every frame, already transformed into
  /// world coordinates: draw at world positions and it lands correctly.
  void render(Canvas canvas, Frame frame);

  void dispose();
}

class Frame {
  final Map<String, RenderEntity> entities;  // interpolated, this instant
  final Map<String, Object?> sharedState;
  final ScoreView scores;           // read-only standings, §8
  final double timeMs;              // shared timeline, identical on all phones
  final double dt;

  final PhoneLayout me;             // this phone's slice
  final WorldRect board;            // the whole board
  final CoverageMap coverage;       // which parts are backed by a screen
  final WorldRect visible;          // == me.viewport, for culling
}
```

The canvas arrives with the camera applied: `canvas.drawCircle(Offset(e.x, e.y),
r, paint)` puts the circle at that world position on whichever phone can see it.
A stroke width of `1 / frame.me.logicalPxPerWorldUnit` is one physical pixel.

`render` **must not mutate game state.** It runs on every device, at each
device's own frame rate, and two phones that disagree about the world produce
exactly the artefact this whole project exists to avoid. The host's sim is the
only writer; the view is a pure function of `Frame`.

### Not writing a renderer

Most prototypes should not have to. The SDK ships a `ShapeView`:

```dart
GameView createView(ViewContext c) => ShapeView(
      // draws every entity from its props: circle/box, colour, rotation
      background: const Color(0xFF0B1020),
      grid: true,
    );
```

That is exactly today's renderer, demoted from "the only way" to "the default".

### HUD

Score and buttons are Flutter widgets, not canvas painting:

```dart
Widget? buildHud(BuildContext context, HudFrame frame) => ScorePill(
      '${frame.sharedState['caught']} / 10',
    );
```

Returns null for no HUD. Rebuilt only when `sharedState` changes, so it never
touches the render loop.

---

## 8. The scoreboard

Score belongs to the **lobby**, not to a game. Each phone has one running total
that survives across rounds, so a table can play five minigames and still know
who is winning. A game reads it, adds to it, and is otherwise not responsible
for it.

```dart
class Scoreboard {
  /// This phone's running total for the session.
  int operator [](String phoneId);

  /// How much it has changed since the current round began — what the win
  /// screen shows as '+3'.
  int roundDelta(String phoneId);

  void award(String phoneId, int points);   // += points, may be negative
  void setTo(String phoneId, int value);
  void awardAll(int points);                // co-op: everyone at the table

  List<ScoreEntry> get ranked;              // highest first
  ScoreEntry? get leader;                   // null when everyone is level
  bool get isUsed;                          // any non-zero score this session
}

class ScoreEntry {
  final String phoneId;
  final String label;    // 'Pixel 7'
  final int total;
  final int roundDelta;
}
```

### Who may write to it

The host, and only during `sim.step` or `sim.onTouch` — the same rule as every
other piece of authoritative state. A sim reaches it through its context:

```dart
@override
void step(double dt) {
  for (final ball in _caughtThisStep) {
    context.scores.award(ball.caughtBy, 10);
  }
}
```

Views get it read-only on the frame, so any phone can draw the standings:

```dart
void render(Canvas canvas, Frame frame) {
  final me = frame.scores[frame.me.phoneId];   // int
  ...
}
```

### What the platform does with it

- **Lobby** — a standings list under the connected phones, so people see where
  they are between rounds. Hidden entirely while every score is zero.
- **Win screen** — final standings with each phone's `+n` for the round.
- **Round boundaries** — the platform snapshots totals when a round starts,
  which is the whole implementation of `roundDelta`. Games never manage it.
- **Reset** — the host can clear the board from the lobby. Nothing else clears
  it; leaving a game does not.

### Scoring is optional

Both current games are co-operative: the whole table beats the tower or catches
the balls together, and nobody has an individual score. A game that never
touches `scores` is completely normal, and the platform simply shows no
standings. `awardAll` exists so a co-op game can still put points on the board
for the table as a whole.

### Identity, and one honest gap

Scores are keyed by `phoneId`, which the host assigns per connection. A phone
that drops and rejoins mid-session is therefore a **new player with a zero
score**. That is wrong in the obvious way — someone's WiFi hiccups and their 40
points evaporate.

The fix is small and I have deliberately not folded it into this proposal: have
each client generate a random device id once, persist it locally, and send it in
the join message; the host keys the scoreboard by that instead, so a reconnect
reclaims its total. It costs one dependency and one field. Say the word and it
goes in the first implementation; otherwise the limitation is real and should be
written down rather than discovered.

---

## 9. Dead zones

The bezel gap is real space. Physics runs through it; the question is only what a
game wants to happen there, and the game answers by consulting the map it is
handed:

```dart
final coverage = context.coverage;
coverage.isCovered(x, y);      // is there a screen under this point
coverage.seamRects();          // the gaps, in layout order
```

The SDK provides the three policies as helpers, not as rules:

- `DeadZones.ignore()` — nothing. Physics is continuous, the object is briefly
  invisible, and it reappears exactly where momentum says. Both current games.
- `DeadZones.wall(world)` — inserts static bodies filling each seam, for a game
  where a piece must never be lost in a gap.
- `DeadZones.despawn(sim)` — an entity that comes to rest in a gap is removed.

A game that wants something else — score bonus for threading the gap, a portal —
writes it against `coverage` directly.

---

## 10. Lifecycle

```
        ┌──────────────────────────────────────────────┐
        │  lobby        platform: code, QR, who is in,   │
        │               standings, phone measurements    │
        └───────┬──────────────────────────────────────┘
                │  host taps Play
                │    ├─ game.planBoard(lobby)      automatic
                │    ├─ compile → BoardLayout      automatic
                │    └─ game.createView()          automatic
        ┌───────▼──────────────────────────────────────┐
        │  placing      'Slingshot — hit the tower'     │
        │               'you are leftmost'  + diagram   │
        │               view.load() in the background   │
        │               everyone confirms position      │
        └───────┬──────────────────────────────────────┘
                │  all confirmed
        ┌───────▼──────────────────────────────────────┐
        │  playing      sim.step() 60Hz → snapshots     │
        │               view.render() every frame       │
        └───────┬──────────────────────────────────────┘
                │  sim.outcome != null
        ┌───────▼──────────────────────────────────────┐
        │  won          standings, next game + how to   │
        │               rearrange for it                │
        └───────┬──────────────────────────────────────┘
                │  host taps Set up <next>
                └──► back to placing
```

### There is no arranging step

An earlier draft had the host review the arrangement before broadcasting it.
With `planBoard` there is nothing left to review: the game already decided the
axis, the order and the spacing, and it decided better than a host squinting at
a diagram could. Selecting a game runs the plan and goes straight to placing.

The old arranging screen's contents did not disappear, they moved to where they
belong:

| Was on the arranging screen | Now |
| --- | --- |
| Game title, tagline, goal | The placing screen, above the instruction |
| Arrangement diagram | The placing screen, next to "you are leftmost" |
| Manual phone reordering | **Gone.** `planBoard` decides the order |
| Phone measurements | The lobby, where they belong — they are a property of the phone, not of the game |

Losing manual reordering is not a loss. The placement screen already tells each
phone where to go, so the plan leads and people follow it; it never had to
describe an arrangement that already existed. Two identical phones make the
order arbitrary, and arbitrary is fine when everyone is being told where to
stand.

There is still exactly one deliberate tap before anyone is asked to pick up a
phone — **Play** from the lobby, **Set up &lt;next&gt;** from the win screen —
so the table is never surprised.

### When the plan is bad

`planBoard` runs before anything is broadcast, so a game that returns a broken
plan (overlapping screens, a phone left unplaced) fails at that moment. The host
sees the validation error on the lobby screen and the round never starts. Nobody
is asked to rearrange a table for a game that cannot run.

Assets load during `placing`, which is dead time anyway — people are pushing
phones together. A game whose `load()` throws is reported on the host screen and
the playlist moves on rather than hanging the table.

---

## 11. Choosing the next game

The playlist stays fixed and wrapping, filtered by phone count:

```dart
class GameCatalog {
  static final playlist = <MultiscreenGame>[
    SlingshotGame(),
    BallBinGame(),
  ];

  /// Next game in the list that fits [phoneCount], wrapping.
  static MultiscreenGame? nextPlayable(int after, int phoneCount);
}
```

Registering a game is one import and one list entry. If no game fits the current
phone count, the lobby says so plainly ("Ball Bin needs 2+ phones — connect
another") instead of offering a Play button that fails.

---

## 12. Wire protocol

Generalised from today's, and now carrying game-defined content. Every message
still JSON.

| Message | When | Payload |
| --- | --- | --- |
| `welcome` | on join | phoneId, game name, **catalogFingerprint** |
| `lobby` | on change | phases, phones, current game id + manifest |
| `layout` | placement | this phone's offsets, board, coverage, plan hints |
| `worldInit` | play starts | game id, board, initial entity descriptors, game init blob |
| `spawn` | entity appears | id, kind, props |
| `despawn` | entity leaves | ids |
| `state` | 60 Hz | tick, t, `[id, x, y, a, vx, vy]` |
| `shared` | on change | the diffed `sharedState` map |
| `scores` | on change | phoneId → total, plus each round's starting totals |
| `event` | game-fired | game-defined one-shots, for sound and particles |
| `outcome` | round ends | won/lost, summary, next game |

### Every device must be running the same build

Game code runs on clients, so a phone whose build lacks a game cannot render it.
The host sends a **catalogFingerprint** — a hash of the game ids and the contract
version — in `welcome`, and a client whose fingerprint differs is rejected with
"This phone has a different version of the app."

This is not exotic: it is the ordinary consequence of games shipping in the
binary, and it bites the first time two people install a week apart. A clear
message beats a blank screen or, worse, a table that half-works.

---

## 13. A complete game, end to end

```dart
class PongGame implements MultiscreenGame {
  @override
  GameManifest get manifest => const GameManifest(
        id: 'pong',
        title: 'Pong',
        tagline: 'One paddle each, ball down the middle.',
        goal: 'First to 5.',
        minPhones: 2,
        maxPhones: 2,
      );

  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(
        lobby.phones,
        sort: PhoneSort.joinOrder,
        gap: Gaps.casingsTouching,
      );

  @override
  GameSim createSim(BoardContext c) => PongSim(c);

  @override
  GameView createView(ViewContext c) => PongView(c);
}

class PongSim extends Forge2DGameSim {
  PongSim(super.context);

  @override
  void build() {
    addEntity('ball', 'ball', BodyDef(type: BodyType.dynamic, position: board.center),
        props: {'r': 0.5});
    // paddles, walls...
  }

  @override
  void onTouch(TouchEvent t) => _paddleFor(t.phoneId)?.moveTo(t.worldY);

  @override
  void step(double dt) {
    super.step(dt);
    final scored = _ballLeftTheBoard();
    if (scored != null) {
      // The session scoreboard, not a local counter: these points follow the
      // player into the next minigame.
      context.scores.award(scored, 1);
      _serve();
    }
  }

  @override
  GameOutcome? get outcome {
    final leader = context.scores.ranked.first;
    return leader.roundDelta >= 5 ? const GameOutcome.won() : null;
  }
}

class PongView extends GameView {
  late final Image _ball = context.assets.image('games/pong/ball.png');

  @override
  void render(Canvas canvas, Frame frame) {
    for (final e in frame.entities.values) {
      if (e.kind == 'ball') {
        canvas.drawImage(_ball, Offset(e.x, e.y), _paint);
      }
    }
  }
}
```

Roughly 60 lines for a working two-phone game with a perfect seam.

---

## 14. Where the code lives

```
lib/
  sdk/
    contract/     game.dart  manifest.dart  sim.dart  view.dart
                  entity.dart  frame.dart  touch.dart  outcome.dart
    layout/       phone_spec.dart  board_plan.dart  layouts.dart
                  board_compiler.dart   (plan → BoardLayout + CoverageMap)
    physics/      forge2d_game_sim.dart  dead_zones.dart
    render/       shape_view.dart
    score/        scoreboard.dart
    model/        PhoneLayout (the transforms), CoverageMap, WorldRect
    net/          transport, protocol, discovery, websocket, loopback
    host/         host_session.dart
    client/       client_session.dart  snapshot_buffer.dart  viewport_game.dart
    ui/           role, lobby, placement, game, results screens
    app_controller.dart
    platform_config.dart
    catalog.dart  the playlist
  games/
    slingshot/    slingshot_game.dart  _sim  _view  _config
    ball_bin/     ball_bin_game.dart   _sim  _view  _config
  main.dart

assets/
  games/
    pong/         ball.png  paddle.png
```

A game's assets live under `assets/games/<id>/` and are declared in
`pubspec.yaml` like any other Flutter asset. `context.assets` scopes lookups to
the game's own folder and loads them during the placement screen, so a game
never blocks a frame on a decode.

`sdk/` never imports from `games/` except in `catalog.dart` — one file, easy to
check, and the line a compiler would enforce later if this becomes a real
package. Nothing in the contract assumes it will not.

---

## 15. What changed during the build

Four things the proposal got slightly wrong, found by making the two existing
games the contract's first customers — which was the point of doing it that way.

**The sling needed no platform support.** The proposal left the slingshot band
as an open question. It turned out to be expressible with nothing but the
generic machinery: the pouch is an ordinary entity, so it rides the same
interpolated timeline as the bird and the band can never lag the thing it is
flinging. `SlingState` and `sampleSling` are gone from the protocol and the
buffer entirely. This was the single best sign the contract was the right shape.

**Seams are computed, not declared.** `CoverageMap` used to be told which axis
the phones ran along. With freeform layouts there is no such axis, so it now
works the gaps out geometrically — two screens separated on one axis and
overlapping on the other, with anything sitting *between* them disqualifying the
pair. A 2×2 grid produces four seams, two of each orientation, with no enum
anywhere.

**A board is not always the box around the screens.** A row of one tall phone
and one short one is only fully covered as deep as the short one, and treating
the tall phone's extra centimetre as playfield invents a dead zone that is not a
real gap. `BoardPlan` therefore carries optional `bounds`; the `Layouts` helpers
set it to the intersection band, and freeform plans fall back to the bounding
box.

**Config split by owner.** `GameConfig` held both platform constants and
slingshot tuning. Now `sdk/platform_config.dart` has the three numbers the
platform owns, and each game's tunables live in its own folder.

---

## 16. Migration

The two existing games are the first two customers of the contract, which is the
only honest way to find out whether it is any good.

1. Add `sdk/contract` and `sdk/layout` alongside the current code.
2. `BoardPlan` → `BoardLayout` compiler; reimplement today's `Arrangement.strip`
   and `.stack` as `Layouts.row` / `Layouts.column` and check the existing layout
   tests still pass unchanged.
3. Generalise the protocol (spawn/despawn, shared, event) with today's renderer
   still in place.
4. Move `SlingshotSim` and `BallBinSim` behind `GameSim`; extract their drawing
   from `_BoardPainter` into `SlingshotView` / `BallBinView`, with `ShapeView`
   doing most of the work.
5. Add the scoreboard: host-owned, broadcast, shown in the lobby and on the win
   screen. Ball Bin awards a point to whichever phone the bin was on when a ball
   landed — the first per-phone scoring in the project, and a real test of
   whether §8 is shaped right.
6. Delete `Arrangement`, `MiniGameDef` and `game_catalog.dart`; the manifest and
   `planBoard` replace them. Delete `arrange_view.dart` and the
   `HostPhase.arranging` state with them, moving the metrics card back to the
   lobby and the game's title and diagram onto the placement screen.
7. Write a third game that exists only to prove the contract — one that neither
   existing game's shape would have suggested. A grid layout, a 3-phone minimum,
   and genuinely competitive per-phone scoring.

Each step keeps the app running and the suite green.

---

## 17. Deliberately not in v1

- **Rotated phones.** `PhonePlacement` has no rotation; every phone is landscape.
  Portrait means orientation-lock work in the shell and a rotated camera, and no
  current game needs it. `PhonePlacement` gains a `quarterTurns` field when one
  does, without disturbing anything else.
- **Client-side prediction.** The dragging phone still renders the shared delayed
  timeline like everyone else. Consistency first; the SDK can add opt-in
  prediction per entity later.
- **Downloadable games.** Dart cannot load compiled code at runtime, so games
  ship in the binary. The catalog fingerprint exists partly to make that
  limitation loud instead of mysterious.
- **Per-game networking.** A game cannot open its own socket. Everything goes
  through the platform's timeline, which is what makes it correct.
- **More than one authoritative writer.** The host owns the world. Always.
