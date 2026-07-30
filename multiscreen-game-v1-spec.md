# Multiscreen Slingshot Game — v1 Prototype Spec

## What we're building

A **local multiplayer mobile game where multiple phones combine to form one shared game world.** Players lay their phones side by side on a table; the game treats the combined screens as a single "board." One phone is authoritative (runs the simulation); the others are viewports onto the same world.

The v1 game is deliberately tiny: **an Angry-Birds-style slingshot** — one draggable "bird" you sling across the board. The point of v1 is not the game; it's proving the **multiscreen architecture** works and *feels* seamless.

### The one thing that must work

The **seam**: when the bird flies from one phone's screen across the physical gap into the next phone's screen, it must look like one continuous motion across one continuous screen. If that feels right, the concept is validated. Everything else in v1 exists to serve this.

---

## Core architecture

Server-authoritative with client-side viewport rendering.

- **The server owns the "true" world.** A continuous coordinate space (e.g. a 10×10 board) holding all physics and entity state. Single source of truth.
- **Each phone is a viewport** onto a slice of that world. Phone 1 shows world region x:0–5, phone 2 shows x:5–10 (values determined by calibration, not hardcoded).
- **Phones send raw local input.** "Finger down at local pixel (x, y) on my screen." The server converts local → world coordinates using that phone's viewport offset, runs the sim, and streams entity state back.
- **Clients are render-only for the sim.** They draw the entities the server describes and interpolate between snapshots. They do NOT run authoritative physics.

### Host model (v1 has NO separate server / NO cloud)

One of the phones runs the authoritative loop. Since the game is inherently same-room (phones physically adjacent), keeping the loop local gives the lowest latency and needs zero infrastructure. There is no backend to deploy in v1.

- Ship **a single Flutter app** with two roles chosen at launch: **Host** or **Join**.
- **Host**: starts a WebSocket server, runs the Flame/Forge2D sim, AND renders its own viewport (the host is also a player).
- **Join**: connects to the host over local WiFi, renders its viewport slice, sends touches up.

---

## Stack (all Dart, local)

| Concern | Choice | Notes |
|---|---|---|
| Language | **Dart** | One language across host + clients. |
| Engine | **Flame** | 2D game loop, sprites, components, camera. Flame's camera maps directly onto "this phone shows world region X." |
| Physics | **Forge2D** | Box2D port in the Flame ecosystem. Runs on the host only. Gives slingshot + collisions for free. |
| Transport | **`dart:io` WebSockets** | Built into Dart, no package. Host runs a WebSocket server; clients connect. |
| Discovery | **QR code** | Host displays `ws://<its-ip>:<port>` as a QR; joiners scan (`mobile_scanner`) or type the IP. This is the entire "matchmaking" for v1. |

No TypeScript, no cloud, no dedicated server in v1. (Those come later as an optional lobby/platform layer that sits *beside* the local loop, never inside it.)

---

## Networking details (v1)

### Transport = WebSockets over the local LAN

Both phones are on the same WiFi. Each has a local IP (e.g. `192.168.1.42`). The host binds a WebSocket server on a port; clients open a persistent two-way connection to it. Traffic never leaves the local network.

**Host (server) sketch:**
```dart
import 'dart:io';
import 'dart:convert';

final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
final clients = <WebSocket>[];

await for (final HttpRequest req in server) {
  final socket = await WebSocketTransformer.upgrade(req);
  clients.add(socket);
  socket.listen((message) {
    final msg = jsonDecode(message as String);
    // handle {type: 'touch', ...} etc — feed into the sim
  }, onDone: () => clients.remove(socket));
}

// On each sim tick, broadcast state:
void broadcast(Map<String, dynamic> state) {
  final json = jsonEncode(state);
  for (final c in clients) { c.add(json); }
}
```

**Client sketch:**
```dart
final socket = await WebSocket.connect('ws://192.168.1.42:8080');
socket.listen((message) {
  final state = jsonDecode(message as String);
  // render my viewport from state
});
socket.add(jsonEncode({'type': 'touch', 'x': 2.3, 'y': 7.1, 'phase': 'down'}));
```

- Use **TCP/WebSocket** for v1 (reliable, ordered, simple). Do NOT reach for UDP yet — only if latency is measured to be a real problem later.
- The host holds the list of connected sockets, runs a fixed-tick loop (30–60 Hz), reads queued client inputs, steps physics, broadcasts state.

### Discovery = QR code

Host renders `ws://<ip>:<port>` into a QR code on screen. Joiners scan it (or type the IP as fallback). No mDNS, no Nearby/Multipeer in v1 — those are v2 polish. QR sidesteps discovery entirely and is reliable for demoing to friends.

### The gotcha to document in-app

Both phones must be on the **same WiFi network**, and that network must allow devices to talk to each other:
- **Public/guest WiFi** often has "client isolation" → devices can't see each other → connection silently fails. Home WiFi is fine.
- **Cellular vs WiFi mismatch** → not the same LAN → no connection.
- v1.5 escape hatch (no code change): one phone runs a **hotspot**, the other joins it; the same WebSocket code works unchanged.

### Keep the transport swappable

Put networking behind a small Dart interface so the game code never touches raw sockets. Later you can swap QR+WebSockets for a lobby server, hotspot, or Nearby/Multipeer by changing one file.

```dart
abstract class Transport {
  Future<void> connect();
  void send(Map<String, dynamic> message);
  Stream<Map<String, dynamic>> get onMessage;
  Future<void> dispose();
}
// v1: WebSocketTransport implements Transport
```

---

## Calibration & the coverage map

Before gameplay, run a **calibration phase** so the server's mental model matches the physical arrangement of phones.

### Handshake

1. Each phone reports:
   - **Screen size in real-world units (mm, not pixels)** — derive from resolution + DPI (both iOS/Android expose this).
   - **Bezel / casing thickness** (the dead zone around the active screen).
2. Host builds a **mental model**: per phone, an *active rectangle* sitting inside a slightly larger *physical rectangle*.
3. Host computes a layout, packs the physical rectangles, and figures out where the world seam falls.
4. Host sends each phone a **"place yourself here"** instruction (relative to a shared anchor).
5. Both/all phones hit **Confirm** → physical arrangement now matches the mental model → gameplay starts.

### v1 simplification: constrain the arrangement

Don't build freeform packing yet. For v1, **force a clean arrangement**: phones butt together left-to-right, top edges aligned, forming a 2-wide strip. Phones may still differ in size/DPI (that's handled by the per-phone transform), but you avoid the hard packing math. Earn freeform layouts later.

### What calibration produces (per phone `i`)

- `worldOffset_i = (ox, oy)` — where the phone's top-left active pixel sits in world coords.
- `scale_i` = world units per mm (shared across phones so the world has one consistent physical size).
- `activePx_i`, `dpi_i` — for converting touches.

### Touch → world transform

```
worldPos = worldOffset_i + (localPx / dpi_i) * mmToWorld
```
where `mmToWorld` is the shared world-units-per-mm scale.

### The honest limitation

There is **no sensor confirming the phones are actually placed correctly.** "Confirm" is a human promise, not a measurement. If a user is a few mm off or slightly rotated, the seam drifts.
- v1: accept it — the bezel gap hides small errors anyway.
- v2 option: **visual calibration** — show half a shape on each screen, let the user nudge a slider until the halves line up to their eye (turn the human into the sensor).
- Overkill later: cameras / UWB / NFC to measure relative position.

---

## The board = full rectangle + known dead zones

The board is the full bounding rectangle. The server maintains a **coverage map**: which sub-regions are backed by a real screen ("live") vs not ("dead").

- **The world is continuous.** Physics runs everywhere, including dead zones. The bird keeps flying through the bezel gap and emerges on the next screen exactly where momentum says — this IS the seamless-seam trick, generalized (a dead zone is just a wider seam).
- **The coverage map is metadata on top.** The game can query `isCovered(worldX, worldY)` and pick a policy:
  - **Ignore** (v1 default for the slingshot) — bird flies through dead zones invisibly, reappears on the next screen.
  - Treat as walls / void (a platformer might).
  - Design levels around live zones (a puzzle game).

### Dead-zone types (encode the difference)

- **Bezel/gap dead zones** — the mm between two active screens. Physically real space the bird *should* traverse. Want continuity here.
- **Uncovered board corners** — space only "dead" because the board is defined as the bounding box. Arguably no gameplay should happen there.
- v1 simplification: make the board **hug the covered area tightly** so the only dead zones are real bezel gaps, and every dead zone means the same thing.

### Data structure

For a ~10×10 prototype, keep it simple: a **list of live rectangles** (one per phone active area, in world coords) + point-in-rect tests. Everything not in a live rect is dead. Do NOT build a grid/quadtree/bitmask yet — only needed for many screens or fast per-pixel queries later.

---

## Message protocol (starting point)

**Client → Host:**
```json
{ "type": "touch", "phoneId": "p2", "x": 2.3, "y": 7.1, "phase": "down|move|up" }
{ "type": "calibration", "phoneId": "p2", "screenMm": {"w": 64, "h": 140}, "bezelMm": 3, "dpi": 420, "activePx": {"w": 1080, "h": 2400} }
{ "type": "confirmPlacement", "phoneId": "p2" }
```

**Host → Client:**
```json
{ "type": "state", "tick": 42, "timestamp": 169..., "entities": [ {"id": "bird", "x": 5.2, "y": 3.1, "vx": ..., "vy": ...} ] }
{ "type": "layout", "phoneId": "p2", "worldOffset": {"x": 5, "y": 0}, "scale": ..., "placement": "right of p1, top-aligned" }
{ "type": "start" }
```

Include `tick` + `timestamp` on state so clients can **interpolate/extrapolate** between snapshots — critical for smooth motion across the seam.

---

## Client rendering

- Each client knows its **viewport rect in world coords** (from the `layout` message).
- Render only entities overlapping its viewport; cull the rest.
- **Interpolate between state snapshots** rather than snapping to the latest — this is what makes the bird's motion (and especially the seam crossing) look continuous. Buffer ~2 snapshots and render slightly in the past, or extrapolate from velocity.
- Map world coords → local screen pixels using the inverse of the touch transform.

---

## Build order (do these in sequence)

1. **Two phones talking.** Host prints a QR of `ws://<ip>:<port>`; client scans and connects; ping-pong JSON both ways. (Proves transport + discovery.)
2. **Calibration handshake → coverage map.** Phones report screen mm + bezel; host builds live rectangles; host sends "place yourself" + confirm flow.
3. **Host runs a Forge2D world** with one draggable bird; broadcast entity positions at a fixed tick.
4. **Each phone renders only its viewport slice; make the SEAM feel continuous** (interpolation). ← *This is the riskiest unknown. Get here as fast as possible; everything before it is scaffolding for this moment.*

---

## Explicitly OUT of scope for v1

- TypeScript / cloud / dedicated server of any kind.
- Online play with people not in the same room.
- Accounts, persistence, leaderboards.
- mDNS auto-discovery, Nearby Connections, Multipeer, WiFi Direct, Bluetooth.
- Freeform phone-packing layouts (v1 forces left-to-right, top-aligned).
- Sensor-based placement verification (v1 trusts the human "Confirm").
- Downloadable/data-driven game definitions (design logic as data-ish to keep this door open, but don't build the loader).
- More than a handful of players.

## Design-forward hints (don't build, but don't paint into a corner)

- Keep game logic **data-ish rather than hardcoded** so "games as downloadable definitions" stays possible later.
- Keep networking behind the `Transport` interface so a cloud lobby / hotspot / Nearby can slot in without touching game code.
- The eventual mature shape: **real-time loop stays local** (latency), while an optional **cloud layer in TypeScript** handles catalog / matchmaking / accounts — sitting beside the loop, used only at connect time, never during play.
