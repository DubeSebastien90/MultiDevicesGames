# Multiscreen Slingshot — v1 prototype

Several phones laid side by side on a table become **one shared game world**. One
phone runs the authoritative simulation; every phone is a viewport onto it.

The game is deliberately tiny — an Angry-Birds-style slingshot with one bird.
The point of v1 is not the game. It is **the seam**: when the bird flies off one
phone's screen, across the physical gap, and onto the next one, it has to look
like one continuous motion across one continuous screen.

Built to [`multiscreen-game-v1-spec.md`](multiscreen-game-v1-spec.md).

## Running it

```bash
flutter pub get
flutter run                # pick a device; two phones on the same WiFi
```

On the first phone tap **Host a game**, name it, and it shows a 5-digit code.
On the second tap **Join a game**: your friend's game is already in the list —
pick it and type the code. Then:

1. Check the measurements on each phone (see *Millimetres* below).
2. Host taps **Lay out the board**.
3. Each phone shows where to sit. Push them together, tap **In place — confirm**.
4. Drag the bird and let go.

The host is a player too — it renders its own viewport through the same code path
as everybody else.

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
  net/          Transport interface + WebSocket, loopback, QueuedBroadcast
                  discovery.dart       UDP beacon: hosts announce, joiners listen
  model/        DeviceMetrics, PhoneLayout (the transforms), CoverageMap
  host/         HostSession (the only thing that runs physics)
                  layout_solver.dart   packs phones left-to-right
                  slingshot_sim.dart   headless Forge2D world
  client/       ClientSession, SnapshotBuffer (the interpolator), ViewportGame
  ui/           role → lobby → placement → game
```

Server-authoritative, client-side viewport rendering:

- **The host owns the world.** A continuous coordinate space holding all physics.
  `slingshot_sim.dart` imports no Flutter and no Flame — a client cannot
  accidentally become a second source of truth.
- **Phones send raw local input** as physical pixels. The host converts to world
  coordinates using that phone's offset, because only the host knows where that
  screen sits.
- **Clients are render-only.** They draw what the host describes and interpolate
  between snapshots.

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

## What is verified

`flutter test` — 27 tests, all passing:

- **`layout_solver_test.dart`** — packing, bezel gaps, top alignment, the
  coverage map, transforms as exact inverses, and mixed-density phones drawing at
  one physical scale.
- **`snapshot_buffer_test.dart`** — interpolation, capped extrapolation, angle
  wraparound, timeline restarts, and the frame-pacing property above.
- **`end_to_end_test.dart`** — a real host with a real Forge2D world, its own
  loopback viewport, and a second phone over an **actual WebSocket**: full
  handshake, placement, launch, and flight. Asserts the bird crosses onto the
  second phone, that both phones agree at the seam, and that the bird is
  simulated *inside* the dead zone rather than stopped by it.
- **`viewport_render_test.dart`** — the Flame camera resolves to the physically
  correct zoom (52.49 logical px per cm at 400dpi/dpr 3) and is pinned to this
  phone's world offset.

Measured on a two-phone board, host + socket client: the bird crosses the seam
1.05s into a flight that peaks 1.2 units above the sling and stays on screen the
whole way, and the two phones disagree by **0.0005 world units (5µm)** while
crossing.

Both real builds compile: `flutter build windows` and `flutter build apk`.

Not covered by tests: the actual physical experience on two phones on a table.
That needs two phones, and it is the only thing that can truly validate the
concept.

## Networking gotchas

Both phones must be on the same WiFi, and that network must let devices talk to
each other.

- **Guest/public WiFi** usually has client isolation → no beacons arrive and the
  join list stays empty. The QR and typed address are right there for this.
- **One phone on cellular** → not the same LAN → no connection.
- **Escape hatch, no code change:** run a hotspot on one phone and join it from
  the other. The same WebSocket code works unchanged.
- **iOS 14+** wants the `com.apple.developer.networking.multicast` entitlement
  before an app may broadcast. Without it the beacon simply never leaves the
  phone: hosting still works, and joiners use the QR. Requesting it from Apple is
  the only thing that turns the list on for iOS hosts — the app needs no change.
- **Android** filters broadcast traffic in the WiFi chip unless a `MulticastLock`
  is held; `MainActivity.kt` takes one while the app is in front.

## Deliberately not built

No TypeScript, no cloud, no dedicated server. No accounts or persistence. No
mDNS/Nearby/Multipeer — discovery is 200 lines of UDP broadcast with a QR and a
typed address behind it, and it never leaves the LAN. No freeform phone
packing (v1 forces a left-to-right strip; the per-phone transform already handles
different sizes, which was the part worth proving). No sensor-based placement
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
