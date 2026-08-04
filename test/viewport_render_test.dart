import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/client/client_session.dart';
import 'package:multiscreen_slingshot/sdk/client/viewport_game.dart';
import 'package:multiscreen_slingshot/games/slingshot/slingshot_game.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/net/loopback_transport.dart';
import 'package:multiscreen_slingshot/sdk/net/protocol.dart';
import 'package:multiscreen_slingshot/sdk/catalog.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// The camera half of the contract: whatever a game paints, the platform
/// guarantees it lands at the same physical size and the same place on every
/// panel. Feeds a client the exact messages a real host sends, using the real
/// compiler and the real sim, then mounts the real renderer on top.
DeviceMetrics portraitPhone(String label) => DeviceMetrics(
  // The app is locked portrait, so a phone measures itself short-edge-first.
  activePxWidth: 1080,
  activePxHeight: 2400,
  widthMm: 68.58, // 400 dpi
  heightMm: 152.4,
  bezelMm: 3,
  devicePixelRatio: 3,
  label: label,
);

void main() {
  Future<(ClientSession, ViewportGame, LoopbackPair)> mountViewport(
    WidgetTester tester, {
    required int phoneIndex,
  }) async {
    const game = SlingshotGame();
    final lobby = LobbyInfo([
      PhoneSpec.fromMetrics('p1', portraitPhone('p1')),
      PhoneSpec.fromMetrics('p2', portraitPhone('p2')),
    ]);
    final board =
        const BoardCompiler().compile(game.planBoard(lobby), lobby);
    final sim = game.createSim(board.contextFor(Scoreboard()));

    final loopback = LoopbackPair();
    final session = ClientSession(
      transport: loopback.transport,
      metrics: portraitPhone('me'),
    );
    await session.connect();

    final me = board.phones[phoneIndex];
    loopback.peer
      ..send({'type': HostMsg.welcome, 'phoneId': me.phoneId})
      ..send({
        'type': HostMsg.layout,
        ...me.toJson(),
        'coverage': board.coverage.toJson(),
        'instruction': board.instruction,
        'game': game.manifest.id,
      })
      ..send({
        'type': HostMsg.worldInit,
        'board': board.coverage.board.toJson(),
        'entities': [
          for (final e in sim.entities) e.descriptor.toJson(),
        ],
        'game': game.manifest.id,
      })
      ..send({'type': HostMsg.shared, 'state': sim.sharedState})
      ..send({'type': HostMsg.start});

    // Two snapshots so there is something to interpolate between.
    for (final t in const [0.0, 100.0]) {
      sim.step(1 / 60);
      loopback.peer.send({
        'type': HostMsg.state,
        'tick': (t / 16.6667).round(),
        't': t,
        'entities': [
          for (final e in sim.entities)
            EntityState(
              id: e.id,
              x: e.x,
              y: e.y,
              angle: e.angle,
              vx: e.vx,
              vy: e.vy,
            ).toJson(),
        ],
      });
    }

    final viewport = ViewportGame(session: session);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GameWidget(game: viewport))),
    );
    // Let the loopback microtasks land, then run a few frames.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return (session, viewport, loopback);
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

  testWidgets("the game's own view is built, loaded and handed frames",
      (tester) async {
    final (session, _, loopback) =
        await mountViewport(tester, phoneIndex: 0);

    // The client resolved the game id against its own catalog and built that
    // game's renderer — this is the half of the contract that runs on clients.
    expect(session.game, isNotNull);
    expect(session.manifest!.id, 'slingshot');
    expect(session.view, isNotNull);

    final frame = session.frameAt(16);
    expect(frame, isNotNull);
    expect(frame!.entities, isNotEmpty);
    expect(frame.entities.containsKey('bird'), isTrue);

    // Descriptors arrived with worldInit, so the view knows what each
    // transform *is* and not merely where it is.
    expect(frame.entities['bird']!.kind, 'bird');
    expect(frame.ofKind('target'), isNotEmpty);

    // The pouch is an ordinary entity on the same interpolated clock.
    expect(frame.byId('pouch'), isNotNull);
    expect(frame.sharedState['anchorX'], isNotNull);

    expect(tester.takeException(), isNull);
    await _teardown(tester, session, loopback);
  });

  testWidgets('a phone missing the game is turned away, not left blank',
      (tester) async {
    final loopback = LoopbackPair();
    final session = ClientSession(
      transport: loopback.transport,
      metrics: portraitPhone('me'),
    );
    await session.connect();

    loopback.peer
      ..send({'type': HostMsg.welcome, 'phoneId': 'p1'})
      ..send({'type': HostMsg.lobby, 'phase': 'lobby', 'phones': [],
        'game': 'a-game-from-the-future'});
    await tester.pump(const Duration(milliseconds: 16));

    expect(session.phase, ClientPhase.rejected);
    expect(session.message, contains('does not have the game'));

    session.dispose();
    await loopback.dispose();
    await tester.pump();
  });

  test('the catalog fingerprint is what the handshake compares', () {
    expect(GameCatalog.fingerprint, isNotEmpty);
    expect(GameCatalog.byId('slingshot'), isNotNull);
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
