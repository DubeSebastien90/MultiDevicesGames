import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/client/client_session.dart';
import 'package:multiscreen_slingshot/host/host_session.dart';
import 'package:multiscreen_slingshot/model/device_metrics.dart';
import 'package:multiscreen_slingshot/net/loopback_transport.dart';
import 'package:multiscreen_slingshot/net/protocol.dart';
import 'package:multiscreen_slingshot/net/websocket_transport.dart';

/// The whole thing, wired up for real: a host with an authoritative Forge2D
/// world, its own loopback viewport, and a second phone on an actual WebSocket.
///
/// This covers every step of the build order except the pixels: transport,
/// discovery payload, calibration handshake, coverage map, the sim loop, and the
/// interpolated playback both phones render from.
DeviceMetrics landscapePhone(String label) => DeviceMetrics(
  activePxWidth: 2400,
  activePxHeight: 1080,
  widthMm: 152.4, // 400 dpi
  heightMm: 68.58,
  bezelMm: 3,
  devicePixelRatio: 3,
  label: label,
);

/// Polls [condition] until it holds, so the test follows the real async flow
/// instead of guessing at sleep durations.
Future<void> waitFor(
  String what,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for: $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late HostSession host;
  late LoopbackPair loopback;
  late ClientSession phone1; // the host's own screen
  late ClientSession phone2; // a real socket
  late Uri address;

  setUp(() async {
    host = HostSession();
    address = await host.start();

    loopback = LoopbackPair();
    phone1 = ClientSession(
      transport: loopback.transport,
      metrics: landscapePhone('host phone'),
    );
    await phone1.connect();
    host.addLocalPeer(loopback.peer);

    // Loop back over the real stack rather than trusting the advertised LAN IP,
    // which on a build machine may not be routable to itself.
    final local = address.replace(host: '127.0.0.1');
    phone2 = ClientSession(
      transport: WebSocketTransport(local),
      metrics: landscapePhone('joined phone'),
    );
    await phone2.connect();
  });

  tearDown(() async {
    phone1.dispose();
    phone2.dispose();
    host.dispose();
    await loopback.dispose();
    // Let the server socket actually let go before the next test binds.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('the host advertises a ws:// address a joiner can use', () {
    expect(address.scheme, 'ws');
    expect(address.port, greaterThan(0));
    expect(address.host, isNotEmpty);
  });

  test('both phones handshake, get placed, and start playing', () async {
    await waitFor('both phones calibrated', () =>
        host.phones.length == 2 && host.phones.every((p) => p.calibrated));
    expect(host.canPlacePhones, isTrue);

    host.sendPlacement();

    await waitFor(
      'both phones told where to sit',
      () => phone1.layout != null && phone2.layout != null,
    );
    expect(phone1.phase, ClientPhase.placing);
    expect(phone2.phase, ClientPhase.placing);

    // The host is phone 1 because it connected first; the joiner goes to its
    // right, top edges aligned.
    expect(phone1.layout!.index, 0);
    expect(phone2.layout!.index, 1);
    expect(phone1.layout!.worldOffsetX, closeTo(0, 1e-9));
    expect(phone2.layout!.worldOffsetX, closeTo(15.24 + 0.6, 1e-9));
    expect(phone2.layout!.placement, contains('right of phone 1'));

    // Nothing starts until both humans promise they are in place.
    phone1.confirmPlacement();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(host.phase, HostPhase.placing, reason: 'one confirm is not enough');

    phone2.confirmPlacement();
    await waitFor('play started', () => host.phase == HostPhase.playing);

    await waitFor(
      'both phones playing with a world to draw',
      () =>
          phone1.phase == ClientPhase.playing &&
          phone2.phase == ClientPhase.playing &&
          phone1.specs.isNotEmpty &&
          phone2.specs.isNotEmpty,
    );

    // Both were handed the same world description.
    expect(
      phone1.specs.map((s) => s.id).toList(),
      phone2.specs.map((s) => s.id).toList(),
    );
    expect(phone1.specs.map((s) => s.id), contains('bird'));
    expect(phone1.board!.width, closeTo(31.08, 1e-9));

    await waitFor(
      'snapshots streaming to both',
      () => phone1.buffer.bufferedSnapshots > 3 &&
          phone2.buffer.bufferedSnapshots > 3,
    );
  });

  test('a bird slung on one phone flies across the seam onto the other',
      () async {
    await _startPlaying(host, phone1, phone2);

    final seamX = phone2.layout!.worldOffsetX; // first lit pixel of phone 2
    final anchorX = phone1.anchorX!;
    final anchorY = phone1.anchorY!;

    expect(
      anchorX,
      lessThan(seamX),
      reason: 'the sling must start on phone 1 for the flight to cross',
    );

    // Pull back and down, so the launch is a shallow rising shot to the right.
    // Sent as raw local pixels on phone 1, exactly as a finger would.
    const pullBack = 2.8;
    const angle = 20 * math.pi / 180;
    final pullX = anchorX - pullBack * math.cos(angle);
    final pullY = anchorY + pullBack * math.sin(angle);

    void touchPhone1(double wx, double wy, String phase) {
      final px = phone1.layout!.worldToPhysicalPx(wx, wy);
      // sendTouch takes logical pixels and scales by the device ratio, so undo
      // that here to feed it a genuine local coordinate.
      final dpr = phone1.metrics.devicePixelRatio;
      phone1.sendTouch(px.x / dpr, px.y / dpr, phase);
    }

    touchPhone1(anchorX, anchorY, TouchPhase.down);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    touchPhone1(pullX, pullY, TouchPhase.move);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    // While pulled, every screen is told about the band — not just the one being
    // touched.
    phone1.buffer.advance(16);
    phone2.buffer.advance(16);
    final slingOnPhone2 = phone2.buffer.sampleSling();
    expect(slingOnPhone2, isNotNull);
    expect(slingOnPhone2!.active, isTrue);
    expect(slingOnPhone2.draggingPhoneId, phone1.phoneId);

    touchPhone1(pullX, pullY, TouchPhase.up);

    // Now watch the flight on both phones at once, advancing each buffer with
    // real elapsed time the way a frame loop would.
    var maxX = anchorX;
    var maxApart = 0.0;
    var samplesWhileCrossing = 0;
    final clock = Stopwatch()..start();
    var lastUs = 0;

    while (clock.elapsedMilliseconds < 2500) {
      await Future<void>.delayed(const Duration(milliseconds: 8));
      final nowUs = clock.elapsedMicroseconds;
      final dtMs = (nowUs - lastUs) / 1000;
      lastUs = nowUs;

      phone1.buffer.advance(dtMs);
      phone2.buffer.advance(dtMs);

      final a = phone1.buffer.sampleAll()['bird'];
      final b = phone2.buffer.sampleAll()['bird'];
      if (a == null || b == null) continue;

      maxX = math.max(maxX, a.x);

      // The moment that matters: while the bird is anywhere near the gap, the
      // two phones must agree about where it is, or it visibly steps across.
      if ((a.x - seamX).abs() < 4.0) {
        samplesWhileCrossing++;
        maxApart = math.max(maxApart, (a.x - b.x).abs());
      }
    }

    expect(
      maxX,
      greaterThan(seamX),
      reason: 'the bird never reached the second phone (got to $maxX, '
          'seam at $seamX)',
    );
    expect(
      samplesWhileCrossing,
      greaterThan(5),
      reason: 'never observed the bird near the seam',
    );
    // 0.3 world units = 3mm. Over a real socket, against a loopback peer, on
    // two independently advanced render clocks.
    expect(
      maxApart,
      lessThan(0.3),
      reason: 'phones disagreed by ${maxApart.toStringAsFixed(3)} units at the '
          'seam',
    );
  });

  test('the bird flies through the dead zone rather than stopping at it',
      () async {
    await _startPlaying(host, phone1, phone2);

    final coverage = phone1.coverage!;
    final seam = coverage.seamRects().single;

    // The gap is genuinely not backed by a screen...
    expect(coverage.isCovered(seam.centerX, phone1.board!.centerY), isFalse);
    // ...but it is inside the board, so physics owns it like anywhere else.
    expect(phone1.board!.contains(seam.centerX, phone1.board!.centerY), isTrue);

    final anchorX = phone1.anchorX!;
    final anchorY = phone1.anchorY!;

    void touchPhone1(double wx, double wy, String phase) {
      final px = phone1.layout!.worldToPhysicalPx(wx, wy);
      final dpr = phone1.metrics.devicePixelRatio;
      phone1.sendTouch(px.x / dpr, px.y / dpr, phase);
    }

    touchPhone1(anchorX, anchorY, TouchPhase.down);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    touchPhone1(anchorX - 2.8, anchorY + 1.0, TouchPhase.move);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    touchPhone1(anchorX - 2.8, anchorY + 1.0, TouchPhase.up);

    // Sample the trajectory and check it passes *through* the dead zone: seen on
    // both sides of it, with no plateau at its left edge.
    var seenBefore = false;
    var seenInside = false;
    var seenAfter = false;

    final clock = Stopwatch()..start();
    var lastUs = 0;
    while (clock.elapsedMilliseconds < 2500) {
      await Future<void>.delayed(const Duration(milliseconds: 8));
      final nowUs = clock.elapsedMicroseconds;
      phone1.buffer.advance((nowUs - lastUs) / 1000);
      lastUs = nowUs;

      final bird = phone1.buffer.sampleAll()['bird'];
      if (bird == null) continue;

      if (bird.x < seam.left) seenBefore = true;
      if (bird.x >= seam.left && bird.x <= seam.right) seenInside = true;
      if (bird.x > seam.right) seenAfter = true;
    }

    expect(seenBefore, isTrue);
    expect(seenInside, isTrue, reason: 'never simulated inside the gap');
    expect(seenAfter, isTrue, reason: 'the gap acted like a wall');
  });
}

/// Drives the handshake to the point where both phones are rendering.
Future<void> _startPlaying(
  HostSession host,
  ClientSession phone1,
  ClientSession phone2,
) async {
  await waitFor('both calibrated', () =>
      host.phones.length == 2 && host.phones.every((p) => p.calibrated));
  host.sendPlacement();
  await waitFor(
    'layouts delivered',
    () => phone1.layout != null && phone2.layout != null,
  );
  phone1.confirmPlacement();
  phone2.confirmPlacement();
  await waitFor(
    'playing',
    () => phone1.phase == ClientPhase.playing &&
        phone2.phase == ClientPhase.playing &&
        phone1.specs.isNotEmpty,
  );
  await waitFor(
    'snapshots flowing',
    () => phone1.buffer.bufferedSnapshots > 3 &&
        phone2.buffer.bufferedSnapshots > 3,
  );
}
