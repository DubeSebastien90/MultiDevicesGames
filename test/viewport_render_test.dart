import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/client/client_session.dart';
import 'package:multiscreen_slingshot/client/viewport_game.dart';
import 'package:multiscreen_slingshot/host/layout_solver.dart';
import 'package:multiscreen_slingshot/host/slingshot_sim.dart';
import 'package:multiscreen_slingshot/model/device_metrics.dart';
import 'package:multiscreen_slingshot/net/loopback_transport.dart';
import 'package:multiscreen_slingshot/net/protocol.dart';

DeviceMetrics landscapePhone(String label) => DeviceMetrics(
  activePxWidth: 2400,
  activePxHeight: 1080,
  widthMm: 152.4, // 400 dpi
  heightMm: 68.58,
  bezelMm: 3,
  devicePixelRatio: 3,
  label: label,
);

void main() {
  /// Feeds a client the exact messages a real host would send, using the real
  /// solver and the real sim, then mounts the real renderer on top.
  Future<(ClientSession, ViewportGame, LoopbackPair)> mountViewport(
    WidgetTester tester, {
    required int phoneIndex,
  }) async {
    final board = const LayoutSolver().solve([
      CalibratedPhone('p1', landscapePhone('p1')),
      CalibratedPhone('p2', landscapePhone('p2')),
    ]);
    final sim = SlingshotSim(coverage: board.coverage);

    final loopback = LoopbackPair();
    final session = ClientSession(
      transport: loopback.transport,
      metrics: landscapePhone('me'),
    );
    await session.connect();

    final me = board.phones[phoneIndex];
    loopback.peer
      ..send({'type': HostMsg.welcome, 'phoneId': me.phoneId})
      ..send({
        'type': HostMsg.layout,
        ...me.toJson(),
        'coverage': board.coverage.toJson(),
      })
      ..send({
        'type': HostMsg.worldInit,
        'board': board.coverage.board.toJson(),
        'anchor': {'x': sim.anchor.x, 'y': sim.anchor.y},
        'entities': [for (final s in sim.specs) s.toJson()],
      })
      ..send({'type': HostMsg.start});

    // Two snapshots so there is something to interpolate between.
    for (final t in const [0.0, 100.0]) {
      sim.step(1 / 60);
      loopback.peer.send({
        'type': HostMsg.state,
        'tick': sim.tick,
        't': t,
        'entities': [for (final e in sim.entityStates()) e.toJson()],
        'sling': sim.slingState().toJson(),
      });
    }

    final game = ViewportGame(session: session);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GameWidget(game: game))),
    );
    // Let the loopback microtasks land, then run a few frames.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return (session, game, loopback);
  }

  testWidgets('the camera shows one world unit at its true physical size',
      (tester) async {
    final (session, game, loopback) =
        await mountViewport(tester, phoneIndex: 0);
    expect(tester.takeException(), isNull);

    // 400 dpi, dpr 3, 1 world unit = 10mm:
    //   physical px per unit = 400 / 25.4 * 10 = 157.5
    //   logical px per unit  = 157.5 / 3       = 52.49
    expect(session.layout, isNotNull);
    expect(session.layout!.logicalPxPerWorldUnit, closeTo(52.4934, 1e-3));
    expect(game.camera.viewfinder.zoom, closeTo(52.4934, 1e-3));

    await _teardown(tester, session, loopback);
  });

  testWidgets("the camera is pinned to this phone's slice of the world",
      (tester) async {
    // The right-hand phone must be looking at the right-hand half of the board,
    // one bezel gap past where the left phone's pixels end.
    final (session, game, loopback) =
        await mountViewport(tester, phoneIndex: 1);
    expect(tester.takeException(), isNull);
    expect(game.camera.viewfinder.anchor, Anchor.topLeft);
    expect(game.camera.viewfinder.position.x, closeTo(15.84, 1e-6));
    expect(game.camera.viewfinder.position.y, closeTo(0, 1e-6));
    expect(session.layout!.viewport.left, closeTo(15.84, 1e-6));

    await _teardown(tester, session, loopback);
  });

  testWidgets('renders interpolated entities without throwing',
      (tester) async {
    final (session, game, loopback) =
        await mountViewport(tester, phoneIndex: 0);
    // The render loop is reading the delayed timeline and finding entities on it.
    expect(game.entities, isNotEmpty);
    expect(game.entities.containsKey('bird'), isTrue);
    expect(game.sling, isNotNull);
    expect(session.buffer.bufferedSnapshots, greaterThan(0));

    // Exercise both debug overlays too — they draw extra geometry.
    game
      ..showGrid = true
      ..showSeams = true;
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);

    await _teardown(tester, session, loopback);
  });
}

/// Unmounts the game and cancels the session's ping timer.
///
/// The widget-test framework asserts no timers are outstanding, and it checks
/// that *before* `addTearDown` callbacks run — so this has to happen inline.
Future<void> _teardown(
  WidgetTester tester,
  ClientSession session,
  LoopbackPair loopback,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  session.dispose();
  await loopback.dispose();
  await tester.pump();
}
