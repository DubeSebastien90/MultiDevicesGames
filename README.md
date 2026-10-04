# Bubble Games

Several phones laid on a table become **one shared game world**. One phone runs
the authoritative simulation; every phone — including the host's — is a viewport
onto it.

The mini-games are deliberately small. The interesting part is **the seam**: when
something flies off one phone's screen, across the physical gap between the
casings, and onto the next one, it has to read as one continuous motion across
one continuous surface. And it has to work whichever way the phones are laid out.

> **Before archiving a build for the App Store or Play Store:** make sure
> `--dart-define=FORCE_PREMIUM=true` is **not** in the build command. It unlocks
> Premium regardless of purchase state (`PremiumStatus.forcedPremium` in
> [lib/sdk/monetization/premium_status.dart](lib/sdk/monetization/premium_status.dart))
> and must never ship.

## Running it

Needs two devices on the same WiFi. iOS and Android are the shipping targets;
macOS, Linux and Windows build and are used for development.

```bash
flutter pub get
flutter run
```

On the first phone tap **Host a game** and name it. On the second tap **Join a
game** — the host appears in the list. Then:

1. Check each phone's measurements in the lobby (see [Millimetres](#millimetres)).
2. The host taps **Play**. The game decides where every phone goes and everyone
   is told at once; there is no arrangement screen to approve.
3. Each phone shows where it belongs. Push them together and tap
   **In place — confirm**.
4. Play. The chosen games are played through **once**, each with its own
   arrangement, then everyone lands back in the lobby.

Discovery has three ways in, because broadcast traffic is exactly what guest
networks drop: the list, scanning the host's QR, and typing the address by hand
(debug builds only). The host is a player too, and renders through the same code
path as everybody else.

## Purchases: live on Android, waiting on Apple

Premium is a one-time, non-consumable purchase through
[RevenueCat](https://www.revenuecat.com/).

- **Android: working.** Purchases go through Google Play Billing and RevenueCat
  in our closed-testing build, and Premium unlocks.
- **iOS: wired in, waiting on Apple.** The same code is configured for the App
  Store, but our Paid Applications Agreement is still being approved by Apple.
  Until it is, Apple returns no products, even in Sandbox, and the paywall shows
  *"Couldn't reach the store"* instead of a price. That is the store-side gate,
  not a bug in the app, and no code change is needed once the agreement is
  active.

What is already in place:

- **One `premium` entitlement** shared by the App Store and Google Play apps,
  so a single entitlement check covers both platforms.
- **The paywall reads RevenueCat's current offering** and buys its lifetime
  package, so no product ID is hard-coded in the app.
- **Only the host pays.** One purchase on the host's phone unlocks the premium
  games for everyone who joins that table.
- **Restore purchase**, and a **10-second timeout on the entitlement check** at
  launch and on retry: a customer who already paid gets a "check failed, retry"
  state, never an endless spinner.
- The code lives in
  [lib/sdk/monetization/](lib/sdk/monetization/):
  `premium_status.dart` (the SDK and entitlement state) and
  `paywall_view.dart` (the sheet).

The RevenueCat keys are not in the repo: `env/revenuecat.json` is gitignored
(shape in [env/revenuecat.example.json](env/revenuecat.example.json)). Without
it, a plain `flutter run` still works: debug builds unlock Premium, so every
game is playable. A real purchase also needs a Google account on our testers
list, so ask us if you want to try one.

With the keys, this shows the real paywall:

```bash
flutter run --dart-define-from-file=env/revenuecat.json --dart-define=LOCK_PREMIUM=true
```

## Running the tests

```bash
flutter test --no-pub                            # the whole suite, ~790 tests
flutter test test/arena_sword_test.dart --no-pub # one suite, while iterating
flutter analyze --no-pub
```

**Pass `--no-pub`.** Without it every invocation re-resolves the dependency graph
over the network before a single test runs, which costs more than the tests do.

**Name the suite you are working on.** Each test entry point compiles
separately over a heavy dependency graph (Flame, forge2d, rive, flutter_soloud,
purchases_flutter, bonsoir), and almost every suite imports something under
`lib/sdk/`, so one edit there invalidates nearly all of their cached builds.

`integration_test/native_smoke_test.dart` needs a real device: `flutter test`
runs plugin-free, so a crash inside Rive's or SoLoud's native code is invisible
to the unit suite.

## The games

Registered in [lib/sdk/catalog.dart](lib/sdk/catalog.dart), in playlist order.

| Game | Phones | Arrangement | Tier |
|---|---|---|---|
| Hot Potato | 3–8 | ring | free |
| Flood | 2–6, even | two facing rows | free |
| Arena | 2–8 | row / grid / brick | free |
| Pitch Cars | 2–8 | chain | free |
| Road Runner | 2–8 | row | free |
| Paint War | 2–8 | row / grid / brick | free |
| Guac-a-Mole | 3–8 | grid / brick | Premium |
| Marbles Madness | 2, 4 or 6 | grid / row | Premium |
| Dodgeball | 2–8 | row / grid / brick | Premium |
| Cops & Robbers | 2–8, even | grid | Premium |

A game states what it needs with `PlayerCount`, and the platform skips it when
the table cannot satisfy it. The playlist does not wrap — played through once,
"which is what makes it an evening rather than a treadmill".

## Architecture

Two halves. [lib/sdk/](lib/sdk/) is the platform: discovery, transport, the
lobby, device layout, the shared timeline, physics helpers, audio, scoring, the
UI shell. [lib/games/](lib/games/) is ten mini-games built on it.

One structural rule holds the boundary: **`catalog.dart` is the only file in
`sdk/` that imports from `games/`.** Everything else in the SDK works against
the `MultiscreenGame` interface.

### Host and client

The host runs the only simulation. Every device, *including the host's own
screen*, reaches the world through a `ClientSession`:

```
AppController.startHost()
  ├── HostSession          the authoritative sim, 60 Hz
  └── ClientSession ───────┐
        over a LoopbackPair │  in-memory, no sockets
                            ▼
                   the same code path a remote phone uses
```

That loopback is load-bearing. Rendering the host straight from the live sim
would put its screen one interpolation delay *ahead* of every other phone —
visible as a step at the seam, which is the one thing the project exists to
avoid. See [lib/sdk/app_controller.dart](lib/sdk/app_controller.dart).

### The frame loop

```
HOST                                          EVERY PHONE
sim.step(1/60) at a fixed timestep
  diff entities → spawn / despawn    ──────→  descriptors cached once
  state {tick, t, [x,y,angle,vx,vy]} ──────→  SnapshotBuffer.add()
  sharedState (only when changed)    ──────→  cached
  scores (only when changed)         ──────→  cached
  sound {cue, at: simTime}           ──────→  scheduled on the delayed clock
                                     ←──────  touch {lx, ly, phase}
layout.physicalPxToWorld → sim.onTouch

                                              each rendered frame:
                                                renderTime = local + offset − 80ms
                                                lerp the two bracketing snapshots
                                                view.render(canvas, frame)
```

Input travels one way, as raw **physical** pixels, and becomes world coordinates
only on the host — the only device that knows where any given screen sits.

### Why the seam works

[lib/sdk/client/snapshot_buffer.dart](lib/sdk/client/snapshot_buffer.dart) is the
heart of it. Every phone renders the same moment of the *host's* timeline,
`interpDelayMs = 80` in the past, interpolating between the two snapshots either
side of it. All screens sample one instant, and each is smooth on its own.

The render clock is `localTime + offset − delay`, so it advances at exactly local
frame rate: how a phone chunks its frames cannot affect where it thinks the ball
is. An earlier version nudged the clock's rate toward `newest − delay`, and two
phones at different frame rates settled at different offsets — about 0.8 mm of
disagreement at 20 cm/s, which is precisely the step this class exists to
prevent.

### Coordinates

**1 world unit = 1 cm** (`PlatformConfig.mmToWorld = 0.1`), which keeps a
two-phone board near 32 × 7 units — comfortably inside the range Box2D is tuned
for. A world unit is drawn at its true physical size on every screen, so the
camera's zoom is a function of that phone's measured DPI and nothing else.

Physics runs across the whole board, **including the dead millimetres between
phones**. An object crosses the gap invisibly and reappears exactly where
momentum says it should. That is the seam trick, and it is the default; a game
that wants the gap to be a wall builds one from `CoverageMap.seamRects()`.

### Millimetres

Flutter exposes only a density *bucket*, and a guess 8% out puts the seam about
5 mm wrong — clearly visible. So screen size is measured, not inferred:

```
DeviceMetrics (mm, user-correctable, refined by a native channel)
  → PhoneSpec.fromMetrics        → LobbyInfo
  → game.planBoard(lobby)        → BoardPlan      (millimetres, centre + turn)
  → NameDropOptimizer.optimize                    (see below)
  → BoardCompiler().compile      → BoardLayout    (world units, per-phone)
  → one `layout` message per phone → PhoneLayout  → Flame camera
```

`BoardCompiler` refuses a plan before anyone is asked to move a phone: unknown or
unplaced phones, dishonest mm↔px scale, overlapping screens (by separating axis,
not bounding boxes — two phones at 45° have overlapping boxes and separate
screens), or a board that isn't connected unless the game set `allowGaps`.

`getPhysicalScreenInfo` is answered natively in
[ios/Runner/AppDelegate.swift](ios/Runner/AppDelegate.swift) (a table of iPhone
model PPIs) and
[android/.../MainActivity.kt](android/app/src/main/kotlin/com/reallifecorp/bubblegames/MainActivity.kt)
(`getRealMetrics`, plus a check for OEMs that just echo the density bucket).
Elsewhere the Dart side catches `MissingPluginException` and estimates.

### NameDrop

iOS 17 puts a Share Contact card over the screen when the **tops** of two iPhones
touch — which is half the arrangements in this catalogue. iOS offers no way to
observe or disable it, so three pieces work around it:

- [name_drop_optimizer.dart](lib/sdk/layout/name_drop_optimizer.dart) turns
  phones 180° to move their antenna bands apart, before anybody is asked to lay
  the table out.
- [name_drop_detector.dart](lib/sdk/host/name_drop_detector.dart) infers a
  trigger from two phones reporting a covered screen at the same moment *and*
  the layout saying those two are a pair it could not separate.
- [name_drop_support.dart](lib/sdk/platform/name_drop_support.dart) asks whether
  this device could do it at all: iOS, an iPhone, version 17 or later.

### Networking

Everything is JSON over a `Transport`. **No message names a game** — the
platform ships transforms, and what they mean is the game's business at both
ends, which is why a new game needs no new message type.

| | |
|---|---|
| [discovery.dart](lib/sdk/net/discovery.dart) | the beacon vocabulary, deliberately transport-free |
| [udp_discovery.dart](lib/sdk/net/udp_discovery.dart) | broadcast on port 41234. Needs a multicast entitlement on iOS, so it finds nothing there |
| [bonjour_discovery.dart](lib/sdk/net/bonjour_discovery.dart) | mDNS, needs no entitlement. Why Android runs it too: an iPhone can neither send nor hear a UDP broadcast, so a mixed table needs a language both speak |
| [websocket_transport.dart](lib/sdk/net/websocket_transport.dart) | the game connection, ports 8080–8089 |
| [loopback_transport.dart](lib/sdk/net/loopback_transport.dart) | what makes the host a player |

Every beacon field is treated as hostile: size cap, magic check, scheme check,
control characters stripped, counts clamped. The beacon never carries the join
code.

A joining phone sends `GameCatalog.fingerprint`, and a mismatch is rejected with
a clear message — games ship in the binary, so a client that lacks one cannot
render it. That bites the first time two people install a week apart.

## Writing a game

Four members, in [lib/sdk/contract/](lib/sdk/contract/):

```dart
abstract class MultiscreenGame {
  GameManifest get manifest;                 // who am I, what table do I need
  BoardPlan planBoard(LobbyInfo lobby);      // where the phones go
  GameSim createSim(BoardContext context);   // the rules — host only
  GameView createView(ViewContext context);  // the pixels — every phone
}
```

```dart
abstract class GameSim {
  void step(double dt);                      // exactly dt seconds
  void onTouch(TouchEvent touch);            // already in world coordinates
  Iterable<Entity> get entities;             // new id = spawn, absent id = despawn
  Map<String, Object?> get sharedState => const {};
  GameOutcome? get outcome;                  // non-null ends the round
  void reset();
  void dispose() {}
}

abstract class GameView {
  Future<void> load() async {}               // awaited during placement
  void render(Canvas canvas, Frame frame);
  Widget? buildHud(BuildContext context, HudFrame frame) => null;
  void dispose() {}
}
```

The rules that matter:

- **`step` must be pure with respect to wall-clock time.** No `DateTime.now()`,
  no timers, no `Random()` without a fixed seed. The platform decides when time
  passes.
- **`render` must not mutate game state.** It runs on every device at each
  device's own frame rate; a view is a function of its `Frame`.
- **Transforms are interpolated; shared state is not.** Anything that must move
  smoothly across the seam belongs in an `Entity`, not in `sharedState`. Arena
  puts the sword on the wire as its own entity for exactly this reason.
- **`sharedState` is resent whole whenever any of it changes**, so nothing in it
  may change every tick. Quantise, or send corners instead of curves.
- **Build `outcome` once and keep it.** It is polled several times a tick.
- **A game that does not implement `PlayerPresence` ends in a draw** when
  somebody drops out, because the platform cannot know whether it is still fair.

Physics is opt-in: extend `Forge2DGameSim` for a world with bodies, or implement
`GameSim` directly — Arena, Hot Potato and Paint War do. `ShapeView` is a free
renderer driven by entity props if you do not want to paint anything yourself.

Registering is one import and one list entry in
[lib/sdk/catalog.dart](lib/sdk/catalog.dart). `test/games_contract_test.dart` is
the gate every game passes through.

Follow [lib/games/pitch_cars/](lib/games/pitch_cars/) for the file layout:
`*_game.dart` (the manifest and the three factories), `*_config.dart` (tunables),
`*_sim.dart`, `*_view.dart`, `*_art.dart`, and `sim_*.dart` `part` files when the
sim outgrows one file.

## Where the code lives

```
lib/
  main.dart              launch, orientation lock, audio warm-up
  sdk/
    catalog.dart         the game list — the one bridge to games/
    app_controller.dart  host vs join, and the host's loopback client
    contract/            what a game implements
    host/                HostSession: the only simulation
    client/              ClientSession, SnapshotBuffer, the Flame camera
    net/                 discovery, transports, wire protocol
    layout/              plans, the compiler, NameDrop avoidance
    model/              phones, players, colours, coverage
    physics/             forge2d base sim, play area
    render/              player art, animation, shared painters
    audio/               cue scheduling against the delayed clock
    ui/                  lobby, placement, results, scoreboard, stickers
    monetization/        RevenueCat, the paywall
    platform/            native channels (DPI, device info)
  games/                 ten mini-games, one folder each
archive/                 retired games, not compiled — see archive/README.md
audio-src/               recording masters, not bundled — see audio-src/README.md
docs/                    store setup runbooks
```

## Known rough edges

- **The join code is generated, shown and sent, but never checked.** Anyone on
  the WiFi who finds the beacon is let in. `_handleJoin` in
  [host_session.dart](lib/sdk/host/host_session.dart) is where the check
  belongs; the gate's old implementation is in git history.
- **macOS Bonjour is inconsistent.** `discovery_stack.dart` runs Bonjour on
  macOS, but `macos/Runner/Info.plist` has no `NSBonjourServices` key the way
  the iOS one does, and a comment plus `discovery_transports_test.dart` both say
  desktop stays on UDP alone. On macOS 15+ the failure mode is finding nothing,
  quietly.
- **`test/discovery_live_test.dart` is flaky.** It binds the real discovery port,
  so it occasionally fails in the full suite while passing on its own.
- **The package is still named `multiscreen_slingshot`** in `pubspec.yaml`, from
  an earlier version of the game. The old name also survives in
  `macos/Runner/Configs/AppInfo.xcconfig` and `linux/CMakeLists.txt`.
- **`GameManifest.supportsIpad` is read by nothing.** Declared so manifests need
  not change later; the lobby does not filter on it.

## License

The **source code** is released under the [MIT License](LICENSE) —
© 2026 Sébastien Dubé, Lamine Gueye, Charles Reny-Déry, David Mosquera.

The MIT License does **not** cover:

- **Artwork and animations** — everything under `assets/` except the fonts
  (the `.riv` files, the SVG characters, balls and game icons). All rights
  reserved; do not reuse them without permission.
- **Sound effects and audio sources** — `assets/sdk/sfx/` and `audio-src/`.
  All rights reserved.
- **The "Bubble Games" name and logo.** A fork is welcome, but it has to ship
  under a different name and icon.
- **Fonts** — Fredoka and Lilita One keep their own
  [SIL Open Font License](assets/fonts/), included alongside them.
