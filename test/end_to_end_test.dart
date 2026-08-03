import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/client/client_session.dart';
import 'package:multiscreen_slingshot/sdk/host/host_session.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/net/loopback_transport.dart';
import 'package:multiscreen_slingshot/sdk/net/websocket_transport.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';

/// The whole platform, wired up for real: a host running a game through the SDK
/// contract, its own loopback viewport, and a second phone on an actual
/// WebSocket.
///
/// This covers every step except the pixels — transport, the join gate, board
/// planning, the calibration handshake, entity spawn/despawn, the sim loop, the
/// scoreboard, and the interpolated playback both phones render from.
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
    // No UDP beacon here: this suite is about the game, and binding a
    // broadcast socket on a build machine is a different kind of flaky.
    // Discovery has its own test.
    host = HostSession(name: 'test board', advertise: false);
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
      joinCode: host.joinCode,
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

    expect(host.canStart, isTrue);
    expect(host.blockedReason, isNull);
    expect(host.upcoming!.manifest.id, 'slingshot');

    // One tap. Planning the board and building the renderer happen inside it —
    // there is no arrangement screen to pass through.
    host.startRound();
    expect(host.phase, HostPhase.placing);

    await waitFor(
      'both phones told where to sit',
      () => phone1.layout != null && phone2.layout != null,
    );
    expect(phone1.phase, ClientPhase.placing);
    expect(phone2.phase, ClientPhase.placing);

    // Identical phones, so the game's sort is a no-op and join order stands.
    expect(phone1.layout!.index, 0);
    expect(phone2.layout!.index, 1);
    expect(phone1.layout!.worldOffsetX, closeTo(0, 1e-9));
    expect(phone2.layout!.worldOffsetX, closeTo(15.24 + 0.6, 1e-9));
    expect(phone2.layout!.placement, contains('right of phone 1'));

    // Both were told what they are about to play, and how to stand for it.
    expect(phone1.manifest!.title, 'Slingshot');
    expect(phone2.instruction, contains('side by side'));

    // Both were also handed the compiled board, in board order — this is what
    // the placement diagram draws, and it must be the layout the game chose
    // rather than anything reconstructed from the lobby's join order.
    expect(phone1.slices, hasLength(2));
    expect(
      phone1.slices.map((s) => s.phoneId).toList(),
      phone2.slices.map((s) => s.phoneId).toList(),
      reason: 'every phone must be shown the same arrangement',
    );
    expect(phone1.slices.first.viewport.left, closeTo(0, 1e-9));
    expect(phone1.slices.last.viewport.left, closeTo(15.84, 1e-6));
    expect(phone1.slices.first.label, isNotEmpty);

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
          phone1.frameAt(16)?.entities.isNotEmpty == true &&
          phone2.frameAt(16)?.entities.isNotEmpty == true,
    );

    // Both were handed the same world description.
    final a = phone1.frameAt(16)!;
    final b = phone2.frameAt(16)!;
    expect(a.entities.keys.toSet(), b.entities.keys.toSet());
    expect(a.entities.containsKey('bird'), isTrue);
    expect(a.board.width, closeTo(31.08, 1e-9));

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
    final anchorX = phone1.sharedState['anchorX']! as double;
    final anchorY = phone1.sharedState['anchorY']! as double;

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

    // While pulled, every screen is told about the pouch — not just the one
    // being touched. Waiting on the pouch itself rather than on a fixed sleep:
    // how many milliseconds it takes depends on how loaded the machine is,
    // that it arrives at all does not.
    await waitFor('the pull to reach phone 2', () {
      final frame = phone2.frameAt(5);
      final pouch = frame?.byId('pouch');
      return pouch != null && (pouch.x - pullX).abs() < 0.5;
    });
    expect(phone2.sharedState['dragging'], phone1.phoneId);

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

      final one = phone1.frameAt(dtMs);
      final two = phone2.frameAt(dtMs);
      final birdA = one?.byId('bird');
      final birdB = two?.byId('bird');
      if (birdA == null || birdB == null) continue;

      maxX = math.max(maxX, birdA.x);

      // The moment that matters: while the bird is anywhere near the gap, the
      // two phones must agree about where it is, or it visibly steps across.
      if ((birdA.x - seamX).abs() < 4.0) {
        samplesWhileCrossing++;
        maxApart = math.max(maxApart, (birdA.x - birdB.x).abs());
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

  test('winning a round moves the whole table on to the next game', () async {
    await _startPlaying(host, phone1, phone2);
    expect(host.game!.manifest.id, 'slingshot');

    // Take the shot that ends the round.
    final anchorX = phone1.sharedState['anchorX']! as double;
    final anchorY = phone1.sharedState['anchorY']! as double;
    void touch(double wx, double wy, String phase) {
      final px = phone1.layout!.worldToPhysicalPx(wx, wy);
      final dpr = phone1.metrics.devicePixelRatio;
      phone1.sendTouch(px.x / dpr, px.y / dpr, phase);
    }

    touch(anchorX, anchorY, TouchPhase.down);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    touch(anchorX - 2.8, anchorY + 1.0, TouchPhase.move);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    touch(anchorX - 2.8, anchorY + 1.0, TouchPhase.up);

    await waitFor('the tower to be hit', () => host.phase == HostPhase.finished,
        timeout: const Duration(seconds: 12));

    // Both screens are told, not just the one that took the shot.
    await waitFor(
      'both phones on the results screen',
      () => phone1.phase == ClientPhase.finished &&
          phone2.phase == ClientPhase.finished,
    );
    expect(phone1.result!.won, isTrue);
    expect(phone2.result!.nextTitle, 'Ball Bin');
    expect(phone2.result!.nextInstruction, contains('one above the other'));

    // The playlist advances into placement, not straight to play: the phones
    // have to physically move first.
    host.advanceToNextGame();
    expect(host.phase, HostPhase.placing);
    expect(host.game!.manifest.id, 'ballbin');

    await waitFor(
      'new layouts delivered',
      () => phone1.layout != null &&
          phone2.layout != null &&
          phone1.layout!.worldOffsetY != phone2.layout!.worldOffsetY,
    );

    // Stacked this time: same phones, board rotated a quarter turn.
    expect(phone1.layout!.worldOffsetX, closeTo(0, 1e-9));
    expect(phone2.layout!.worldOffsetX, closeTo(0, 1e-9));
    expect(phone2.layout!.worldOffsetY, closeTo(6.858 + 0.6, 1e-9));
    expect(phone2.layout!.placement, contains('below phone 1'));

    // And it really plays: confirm through and the bin game starts.
    phone1.confirmPlacement();
    phone2.confirmPlacement();
    await waitFor('the bin game running', () =>
        host.phase == HostPhase.playing &&
        phone1.frameAt(16)?.byId('bin') != null);
    expect(phone1.manifest!.title, 'Ball Bin');

    // The game's own shared state reaches every phone.
    await waitFor('the catch counter to arrive',
        () => phone1.sharedState['goal'] == 10);
  });

  test('balls spawn and despawn on every phone without a hand-written message',
      () async {
    await _startPlaying(host, phone1, phone2);

    // Skip the slingshot by winning it outright, then play the bin game.
    final anchorX = phone1.sharedState['anchorX']! as double;
    final anchorY = phone1.sharedState['anchorY']! as double;
    void touch(double wx, double wy, String phase) {
      final px = phone1.layout!.worldToPhysicalPx(wx, wy);
      phone1.sendTouch(
        px.x / phone1.metrics.devicePixelRatio,
        px.y / phone1.metrics.devicePixelRatio,
        phase,
      );
    }

    touch(anchorX, anchorY, TouchPhase.down);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    touch(anchorX - 2.8, anchorY + 1.0, TouchPhase.move);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    touch(anchorX - 2.8, anchorY + 1.0, TouchPhase.up);
    await waitFor('slingshot won', () => host.phase == HostPhase.finished,
        timeout: const Duration(seconds: 12));

    host.advanceToNextGame();
    await waitFor('placed again', () => phone2.phase == ClientPhase.placing);
    phone1.confirmPlacement();
    phone2.confirmPlacement();
    await waitFor('bin game running', () => host.phase == HostPhase.playing);

    // A ball the sim spawned mid-round appears on the *joined* phone, which
    // never heard about it at world-init time.
    await waitFor(
      'a ball to reach the far phone',
      () => phone2.frameAt(16)?.ofKind('ball').isNotEmpty == true,
      timeout: const Duration(seconds: 8),
    );

    final ball = phone2.frameAt(16)!.ofKind('ball').first;
    expect(ball.propDouble('r'), greaterThan(0),
        reason: 'the descriptor arrived with the spawn, not just a transform');
  });

  test('the bird flies through the dead zone rather than stopping at it',
      () async {
    await _startPlaying(host, phone1, phone2);

    final coverage = phone1.coverage!;
    final seam = coverage.seamRects().single;
    final board = phone1.board!;

    // The gap is genuinely not backed by a screen...
    expect(coverage.isCovered(seam.centerX, board.centerY), isFalse);
    // ...but it is inside the board, so physics owns it like anywhere else.
    expect(board.contains(seam.centerX, board.centerY), isTrue);

    final anchorX = phone1.sharedState['anchorX']! as double;
    final anchorY = phone1.sharedState['anchorY']! as double;

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

    // Sample the trajectory and check it passes *through* the dead zone: seen
    // on both sides of it, with no plateau at its left edge.
    var seenBefore = false;
    var seenInside = false;
    var seenAfter = false;

    final clock = Stopwatch()..start();
    var lastUs = 0;
    while (clock.elapsedMilliseconds < 2500) {
      await Future<void>.delayed(const Duration(milliseconds: 8));
      final nowUs = clock.elapsedMicroseconds;
      final bird = phone1.frameAt((nowUs - lastUs) / 1000)?.byId('bird');
      lastUs = nowUs;
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
  host.startRound();
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
        phone1.frameAt(16)?.entities.isNotEmpty == true,
  );
  await waitFor(
    'snapshots flowing',
    () => phone1.buffer.bufferedSnapshots > 3 &&
        phone2.buffer.bufferedSnapshots > 3,
  );
}
