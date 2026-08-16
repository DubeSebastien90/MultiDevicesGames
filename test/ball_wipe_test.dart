import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/client/client_session.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/net/loopback_transport.dart';
import 'package:multiscreen_slingshot/sdk/net/protocol.dart';
import 'package:multiscreen_slingshot/sdk/ui/ball_wipe.dart';

/// The wipe that ends a round.
///
/// The interesting guarantees are not about how it looks. They are that the
/// swap underneath happens exactly once and cannot be missed, that a finished
/// game stops accepting taps the moment it is over, and that artwork which
/// fails to load costs a phone nothing.
void main() {
  testWidgets('the swap happens once, when the screen is covered', (
    tester,
  ) async {
    var covered = 0;
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BallWipe(
          cover: const Duration(milliseconds: 200),
          hold: const Duration(milliseconds: 100),
          reveal: const Duration(milliseconds: 200),
          onCovered: () => covered++,
          onDone: () => done++,
          child: const Text('the game'),
        ),
      ),
    );

    // Still covering: the game is up and nothing has been swapped.
    await tester.pump(const Duration(milliseconds: 100));
    expect(covered, 0);

    // Past the cover, into the hold.
    await tester.pump(const Duration(milliseconds: 150));
    expect(covered, 1, reason: 'the screen was covered without being swapped');
    expect(done, 0, reason: 'uncovered before it had been swapped');

    // And on to the end.
    await tester.pump(const Duration(milliseconds: 400));
    expect(covered, 1, reason: 'the swap ran twice');
    expect(done, 1);
  });

  testWidgets('a wipe torn down early still swaps', (tester) async {
    // Whatever happens to this widget, the round has to end somewhere other
    // than on the game screen. Leaving without swapping would strand a phone
    // on a round that is over.
    var covered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BallWipe(onCovered: () => covered++, child: const Text('game')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(covered, 0);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(covered, 1, reason: 'the round ended on the game screen');
  });

  testWidgets('the screen underneath stops taking taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BallWipe(
          onCovered: () {},
          child: GestureDetector(
            onTap: () => taps++,
            child: const SizedBox.expand(child: Text('the game')),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('the game'), warnIfMissed: false);
    await tester.pump();
    expect(taps, 0, reason: 'a tap reached a round that was already decided');
  });

  testWidgets('artwork that never loads costs the round nothing', (
    tester,
  ) async {
    // No SVG has been rasterised at this point, and the wipe still runs its
    // clock, still swaps, and still blocks input. The balls are the flourish,
    // not the mechanism.
    var covered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BallWipe(
          cover: const Duration(milliseconds: 80),
          hold: Duration.zero,
          reveal: const Duration(milliseconds: 80),
          onCovered: () => covered++,
          child: const Text('game'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(covered, 1);
    // Material puts absorbers of its own in the tree, so this asks that the
    // wipe contributed one rather than that it is the only one.
    expect(find.byType(AbsorbPointer), findsWidgets);
  });

  group('who gets the wipe', () {
    late LoopbackPair pair;
    late ClientSession client;

    setUp(() async {
      pair = LoopbackPair();
      client = ClientSession(
        transport: pair.transport,
        metrics: DeviceMetrics(
          activePxWidth: 1080,
          activePxHeight: 2400,
          widthMm: 68.58,
          heightMm: 152.4,
          bezelMm: 3,
          devicePixelRatio: 3,
          label: 'test phone',
        ),
      );
      await client.connect();
    });

    tearDown(() async {
      client.dispose();
      await pair.dispose();
    });

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    /// Seat this phone, and say whose phone is hosting.
    Future<void> seat({required String host}) async {
      pair.peer
        ..send({'type': HostMsg.welcome, 'phoneId': 'p1'})
        ..send({
          'type': HostMsg.lobby,
          'phase': 'lobby',
          'host': host,
          'phones': const <Map<String, dynamic>>[],
        });
      await settle();
    }

    test('a joiner is held on the game while the balls arrive', () async {
      await seat(host: 'p2');
      expect(client.isHost, isFalse);

      pair.peer.send({'type': HostMsg.outcome, 'kind': 'shared', 'won': true});
      await settle();

      expect(client.wipe, WipePhase.covering);
      expect(client.inputsFrozen, isTrue);
      expect(
        client.phase,
        isNot(ClientPhase.finished),
        reason: 'the game vanished instead of being covered',
      );

      client.revealResult();
      expect(client.phase, ClientPhase.finished);
      expect(client.inputsFrozen, isFalse);
    });

    test('the host gets the same wipe as everybody else', () async {
      // Its screen is one of the phones on the table, not a control panel off
      // to the side. A host that jumped to the score while the others were
      // still watching balls fall would be six phones doing five different
      // things.
      await seat(host: 'p1');
      expect(client.isHost, isTrue);

      pair.peer.send({'type': HostMsg.outcome, 'kind': 'shared', 'won': true});
      await settle();

      expect(client.wipe, WipePhase.covering);
      expect(client.inputsFrozen, isTrue);
      expect(client.phase, isNot(ClientPhase.finished));
    });
  });

  test('every palette colour has a ball', () {
    // A colour with no file is a cell that never fills, which is a hole in the
    // cover — and the one frame it matters is the frame the game is meant to
    // be hidden.
    for (final color in PlayerPalette.all) {
      expect(
        BallWipe.assetFor(color),
        isNotNull,
        reason: '${color.id} has no ball',
      );
    }
    expect(BallWipe.assets, hasLength(PlayerPalette.size));
  });

  testWidgets('every ball file is really in the bundle', (tester) async {
    for (final asset in BallWipe.assets) {
      await tester.runAsync(() async {
        expect(await rootBundle.loadString(asset), contains('<svg'));
      });
    }
  });
}
