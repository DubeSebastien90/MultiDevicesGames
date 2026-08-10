import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_config.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_game.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/layouts.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A game with no physics at all, on a board that is no kind of rectangle.
PhoneSpec phone(String id) => PhoneSpec(
  phoneId: id,
  label: 'phone $id',
  widthMm: 68.58,
  heightMm: 152.4,
  bezelMm: 3,
  dpi: 400,
  devicePixelRatio: 3,
  activePxWidth: 1080,
  activePxHeight: 2400,
);

({HotPotatoSim sim, BoardLayout board, Scoreboard scores}) start(int count) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = HotPotatoGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = HotPotatoSim(board.contextFor(scores), random: math.Random(4));
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

/// A swipe up or down [phoneId]'s **own screen**, as a player's thumb makes it.
///
/// The gesture the game reads: the phones lie with their long edge along the
/// rim, so a screen's top points along the ring and up and down are the two
/// ways round it. Built here the way the platform builds a real one — a screen
/// direction turned into the world by that phone's own angle — so the test
/// swipes what a thumb swipes.
void swipeAlongScreen(
  HotPotatoSim sim,
  BoardLayout board,
  String phoneId, {
  required bool up,
}) {
  final me = board.forPhone(phoneId)!;
  final turn = me.turnRadians;
  // Screen space has y growing downward, so the top is (0, -1).
  final sy = up ? -1.0 : 1.0;
  final wx = -sy * math.sin(turn);
  final wy = sy * math.cos(turn);

  final reach = HotPotatoConfig.minSwipeWorld * 3;
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: me.worldCenterX,
    worldY: me.worldCenterY,
    phase: TouchPhase.down,
  ));
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: me.worldCenterX + wx * reach,
    worldY: me.worldCenterY + wy * reach,
    phase: TouchPhase.up,
  ));
}

/// The seats in the order they sit round the ring, by angle.
///
/// Deliberately *not* the order the compiled board hands them over: that is
/// reading order, top to bottom and left to right, which on a ring puts phones
/// from opposite sides of the table next to each other in the list.
List<String> ringOrder(BoardLayout board) {
  final cx = board.board.centerX;
  final cy = board.board.centerY;
  final seats = List.of(board.slices)
    ..sort((a, b) => math
        .atan2(a.screen.centerY - cy, a.screen.centerX - cx)
        .compareTo(math.atan2(b.screen.centerY - cy, b.screen.centerX - cx)));
  return [for (final s in seats) s.phoneId];
}

/// Which way round the ring a swipe up this phone's screen sends it.
int upStep(BoardLayout board, String phoneId) {
  final ring = ringOrder(board);
  final here = ring.indexOf(phoneId);
  final me = board.forPhone(phoneId)!;
  final turn = me.turnRadians;
  final upX = math.sin(turn), upY = -math.cos(turn);

  double towardSeat(int step) {
    final other = board.forPhone(ring[(here + step + ring.length) % ring.length])!;
    final dx = other.worldCenterX - me.worldCenterX;
    final dy = other.worldCenterY - me.worldCenterY;
    final len = math.sqrt(dx * dx + dy * dy);
    return (dx / len) * upX + (dy / len) * upY;
  }

  return towardSeat(1) > towardSeat(-1) ? 1 : -1;
}

void main() {
  group('the circle layout', () {
    test('needs at least three phones', () {
      final two = LobbyInfo([phone('p1'), phone('p2')]);
      expect(() => Layouts.circle(two.phones), throwsA(isA<BoardPlanError>()));
      expect(const HotPotatoGame().manifest.smallestTable, 3);
      expect(const HotPotatoGame().manifest.fits(2), isFalse);
    });

    test('spaces phones evenly around a ring', () {
      final started = start(5);
      final centers = [
        for (final p in started.board.phones)
          (x: p.worldCenterX, y: p.worldCenterY),
      ];
      // The ring's middle is the mean of the seats. The board's bounding box
      // is not the same point: each phone is turned differently, so each one
      // contributes a differently-shaped box to the union.
      final midX =
          centers.map((c) => c.x).reduce((a, b) => a + b) / centers.length;
      final midY =
          centers.map((c) => c.y).reduce((a, b) => a + b) / centers.length;

      // Every phone the same distance from the middle.
      final radii = [
        for (final c in centers)
          math.sqrt(math.pow(c.x - midX, 2) + math.pow(c.y - midY, 2)),
      ];
      for (final r in radii) {
        expect(r, closeTo(radii.first, 1e-6));
      }
      expect(radii.first, greaterThan(0));
    });

    test(
      'lays each long edge along the rim, at angles no quarter turn allows',
      () {
        final started = start(5);
        final phones = started.board.phones;
        final midX =
            phones.map((p) => p.worldCenterX).reduce((a, b) => a + b) /
            phones.length;
        final midY =
            phones.map((p) => p.worldCenterY).reduce((a, b) => a + b) /
            phones.length;

        for (final p in phones) {
          // A phone's long axis runs along its own "up", which is (sin t, -cos t)
          // once turned t clockwise. Tangential means that axis is square to the
          // radius — so the dot product with the outward direction is zero.
          final longAxis = (
            x: math.sin(p.turnRadians),
            y: -math.cos(p.turnRadians),
          );
          final outward = (x: p.worldCenterX - midX, y: p.worldCenterY - midY);
          final len = math.sqrt(outward.x * outward.x + outward.y * outward.y);
          final dot = (longAxis.x * outward.x + longAxis.y * outward.y) / len;
          expect(
            dot,
            closeTo(0, 1e-6),
            reason: 'phone ${p.phoneId} points its long edge at the middle',
          );
        }

        // Five phones sit 72° apart — not expressible as quarter turns.
        final turns = started.board.phones.map((p) => p.turnRadians).toList();
        expect(turns.any((t) => (t % (math.pi / 2)).abs() > 1e-6), isTrue);
      },
    );

    test('radial facing is still available, and points long edges inward', () {
      final lobby = LobbyInfo([
        for (var i = 0; i < 5; i++) phone('p$i'),
      ]);
      final board = const BoardCompiler().compile(
        Layouts.circle(lobby.phones, facing: RingFacing.radial),
        lobby,
      );
      final phones = board.phones;
      final midX =
          phones.map((p) => p.worldCenterX).reduce((a, b) => a + b) /
          phones.length;
      final midY =
          phones.map((p) => p.worldCenterY).reduce((a, b) => a + b) /
          phones.length;

      for (final p in phones) {
        final longAxis = (
          x: math.sin(p.turnRadians),
          y: -math.cos(p.turnRadians),
        );
        final outward = (x: p.worldCenterX - midX, y: p.worldCenterY - midY);
        final len = math.sqrt(outward.x * outward.x + outward.y * outward.y);
        final dot = (longAxis.x * outward.x + longAxis.y * outward.y) / len;
        expect(dot.abs(), closeTo(1, 1e-6));
      }
    });

    test('a tangential ring fits more phones in the same rim', () {
      final lobby = LobbyInfo([
        for (var i = 0; i < 6; i++) phone('p$i'),
      ]);
      double radiusOf(RingFacing facing) {
        final board = const BoardCompiler().compile(
          Layouts.circle(lobby.phones, facing: facing),
          lobby,
        );
        final phones = board.phones;
        final midX =
            phones.map((p) => p.worldCenterX).reduce((a, b) => a + b) /
            phones.length;
        final midY =
            phones.map((p) => p.worldCenterY).reduce((a, b) => a + b) /
            phones.length;
        final p = phones.first;
        return math.sqrt(
          math.pow(p.worldCenterX - midX, 2) +
              math.pow(p.worldCenterY - midY, 2),
        );
      }

      // Long edges along the rim need a wider ring for the same count — the
      // trade for a circle that reads as one rather than as spokes.
      expect(
        radiusOf(RingFacing.tangential),
        greaterThan(radiusOf(RingFacing.radial)),
      );
    });

    test('screens do not touch, and that is deliberate', () {
      final started = start(4);
      // No seams: the screens never meet, so there is no shared edge.
      expect(started.board.coverage.seamRects(), isEmpty);

      // And the compiler did not treat the space as a broken plan.
      expect(started.board.phones, hasLength(4));
    });

    test('the transforms stay exact inverses at odd angles', () {
      final started = start(5);
      for (final p in started.board.phones) {
        for (final px in const [0.0, 250.0, 1080.0]) {
          final world = p.physicalPxToWorld(px, px * 2);
          final back = p.worldToPhysicalPx(world.x, world.y);
          expect(back.x, closeTo(px, 1e-6));
          expect(back.y, closeTo(px * 2, 1e-6));
        }
      }
    });

    test('a point on one screen belongs to exactly that phone', () {
      final started = start(5);
      final context = started.board.contextFor(Scoreboard());
      for (final p in started.board.phones) {
        expect(context.phoneAt(p.worldCenterX, p.worldCenterY), p.phoneId);
      }
    });
  });

  group('the fuse', () {
    test('burns on sim time and explodes at zero', () {
      final started = start(3);
      final sim = started.sim;

      expect(sim.sharedState['exploded'], isFalse);
      expect(sim.outcome, isNull);

      // Just short of the fuse.
      for (var i = 0; i < PlatformConfig.simHz * 14; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      expect(sim.sharedState['exploded'], isFalse);
      expect(started.scores.isUsed, isFalse);

      for (var i = 0; i < PlatformConfig.simHz * 2; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      expect(sim.sharedState['exploded'], isTrue);
      expect(sim.outcome, isNotNull);
    });

    test('the holder loses and everybody else wins', () {
      final started = start(3);
      final sim = started.sim;

      for (var i = 0; i < PlatformConfig.simHz * 20; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      final victim = sim.holder;
      final outcome = sim.outcome!;

      // The whole point of the game. It used to report a win for the table,
      // so the player left holding it was congratulated along with everyone
      // who had successfully got rid of it.
      expect(outcome.kind, OutcomeKind.contest);
      expect(outcome.winners, isNot(contains(victim)));
      expect(outcome.winners, hasLength(2));
      expect(outcome.lines![victim], isNotNull,
          reason: 'the loser is told why');

      // Polled repeatedly, as the platform does — always the same verdict.
      expect(identical(sim.outcome, outcome), isTrue);
    });

    test('a replayed round does not reuse the last verdict', () {
      final started = start(3);
      final sim = started.sim;
      for (var i = 0; i < PlatformConfig.simHz * 20; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      expect(sim.outcome, isNotNull);

      sim.reset();

      // Latching the outcome is required — it is polled several times a tick —
      // which makes clearing it on reset required too.
      expect(sim.outcome, isNull);
    });

    test('costs the holder ten points, once', () {
      final started = start(3);
      final sim = started.sim;
      final victim = sim.holder;

      for (var i = 0; i < PlatformConfig.simHz * 20; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }

      expect(started.scores[victim], -HotPotatoConfig.explosionPenalty);
      // Kept stepping well past the bang; it must not keep charging.
      for (var i = 0; i < PlatformConfig.simHz * 5; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      expect(started.scores[victim], -HotPotatoConfig.explosionPenalty);

      // Nobody else paid for it.
      final others = started.scores.view.ranked
          .where((e) => e.phoneId != victim)
          .map((e) => e.total);
      expect(others.every((t) => t == 0), isTrue);
    });

    test('counts down identically for everyone, off one clock', () {
      final started = start(4);
      for (var i = 0; i < PlatformConfig.simHz * 5; i++) {
        started.sim.step(1 / PlatformConfig.simHz);
      }
      final left = started.sim.sharedState['secondsLeft']! as double;
      expect(left, closeTo(HotPotatoConfig.fuseSeconds - 5, 0.05));
    });
  });

  group('passing it on', () {
    test('a swipe up the screen sends it one way round the ring', () {
      final started = start(5);
      final sim = started.sim;
      final board = started.board;

      final from = sim.holder;
      final ring = ringOrder(board);
      final step = upStep(board, from);
      final expected =
          ring[(ring.indexOf(from) + step + ring.length) % ring.length];

      swipeAlongScreen(sim, board, from, up: true);
      expect(sim.holder, expected);
    });

    test('and a swipe down sends it the other way', () {
      final started = start(5);
      final sim = started.sim;
      final board = started.board;

      final from = sim.holder;
      final ring = ringOrder(board);
      final step = -upStep(board, from);
      final expected =
          ring[(ring.indexOf(from) + step + ring.length) % ring.length];

      swipeAlongScreen(sim, board, from, up: false);
      expect(sim.holder, expected);
    });

    test('it only ever goes to a phone actually sitting next to you', () {
      // The fault this pins. The compiled board is sorted into reading order,
      // and passing to "the next one in that list" threw the potato clean
      // across the table: on four phones, two entries next to each other in
      // the list sit opposite each other on the ring. Three players hid it
      // completely, because in a triangle everybody is everybody's neighbour.
      for (final count in [3, 4, 5, 6]) {
        final started = start(count);
        final sim = started.sim;
        final board = started.board;
        final ring = ringOrder(board);

        for (var pass = 0; pass < count * 3; pass++) {
          final from = sim.holder;
          swipeAlongScreen(sim, board, from, up: pass.isEven);

          final was = ring.indexOf(from);
          final now = ring.indexOf(sim.holder);
          final hop = (now - was + count) % count;
          expect(hop == 1 || hop == count - 1, isTrue,
              reason: '$count players: the potato went from $from to '
                  '${sim.holder}, which is $hop seats away round the ring');
        }
      }
    });

    test('every seat passes it the same way, whoever is holding it', () {
      // In a ring no two phones agree on which way "up" points in the world,
      // and none of them needs to: the gesture is read against each phone's own
      // screen, so the same thumb movement means the same thing at every seat.
      for (final count in [3, 4, 5, 6]) {
        final started = start(count);
        final sim = started.sim;
        final board = started.board;
        final ring = ringOrder(board);

        // Walk right round the ring with the same gesture every time.
        final visited = <String>{sim.holder};
        for (var i = 0; i < count - 1; i++) {
          final from = sim.holder;
          final step = upStep(board, from);
          swipeAlongScreen(sim, board, from, up: true);

          final expected =
              ring[(ring.indexOf(from) + step + count) % count];
          expect(sim.holder, expected,
              reason: '$count players, from $from');
          visited.add(sim.holder);
        }
        expect(visited, hasLength(count),
            reason: '$count players: swiping up never reached everybody');
      }
    });

    test('only the holder can throw it', () {
      final started = start(4);
      final sim = started.sim;
      final board = started.board;
      final notHolder = board.phones
          .map((p) => p.phoneId)
          .firstWhere((id) => id != sim.holder);
      final before = sim.holder;

      swipeAlongScreen(sim, board, notHolder, up: true);
      expect(sim.holder, before);
    });

    test('a tap is not a throw', () {
      final started = start(4);
      final sim = started.sim;
      final me = started.board.forPhone(sim.holder)!;
      final before = sim.holder;

      sim.onTouch(
        TouchEvent(
          phoneId: before,
          worldX: me.worldCenterX,
          worldY: me.worldCenterY,
          phase: TouchPhase.down,
        ),
      );
      sim.onTouch(
        TouchEvent(
          phoneId: before,
          // Barely moved.
          worldX: me.worldCenterX + 0.2,
          worldY: me.worldCenterY,
          phase: TouchPhase.up,
        ),
      );
      expect(sim.holder, before);
    });

    test('once it has gone off, nobody can pass it', () {
      final started = start(3);
      final sim = started.sim;
      for (var i = 0; i < PlatformConfig.simHz * 20; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      final victim = sim.holder;

      swipeAlongScreen(sim, started.board, victim, up: true);

      expect(sim.holder, victim, reason: 'no passing the blame after the bang');
    });
  });

  group('the potato itself', () {
    test('is an entity, so it slides between screens on the shared clock', () {
      final started = start(4);
      final sim = started.sim;
      final board = started.board;

      final ring = ringOrder(board);
      final from = sim.holder;
      final step = upStep(board, from);
      final next = ring[(ring.indexOf(from) + step + ring.length) % ring.length];
      final target = board.forPhone(next)!;

      final startPos = sim.entities.single;
      swipeAlongScreen(sim, board, from, up: true);

      // One step is not a teleport — it is on its way.
      sim.step(1 / PlatformConfig.simHz);
      final moving = sim.entities.single;
      final movedX = (moving.x - startPos.x).abs();
      expect(movedX + (moving.y - startPos.y).abs(), greaterThan(0));

      // Given time, it arrives at the new holder's screen.
      for (var i = 0; i < PlatformConfig.simHz; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      final arrived = sim.entities.single;
      expect(arrived.x, closeTo(target.worldCenterX, 0.01));
      expect(arrived.y, closeTo(target.worldCenterY, 0.01));
    });

    test('swells and changes kind when it goes off', () {
      final started = start(3);
      final sim = started.sim;

      final calm = sim.entities.single;
      expect(calm.kind, 'potato');

      for (var i = 0; i < PlatformConfig.simHz * 20; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      final blast = sim.entities.single;
      expect(blast.kind, 'blast');
      expect(
        (blast.props['r']! as num).toDouble(),
        greaterThan((calm.props['r']! as num).toDouble()),
      );
    });
  });

  test('reset puts the fuse back and clears the bang', () {
    final started = start(3);
    final sim = started.sim;
    for (var i = 0; i < PlatformConfig.simHz * 20; i++) {
      sim.step(1 / PlatformConfig.simHz);
    }
    expect(sim.outcome, isNotNull);

    sim.reset();
    expect(sim.outcome, isNull);
    expect(sim.sharedState['exploded'], isFalse);
    expect(
      sim.sharedState['secondsLeft'],
      closeTo(HotPotatoConfig.fuseSeconds, 1e-9),
    );
  });
}
