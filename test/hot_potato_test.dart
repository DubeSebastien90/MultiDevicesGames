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

/// A swipe from the middle of [phoneId]'s screen toward a world point.
void swipeToward(
  HotPotatoSim sim,
  BoardLayout board,
  String phoneId,
  double towardX,
  double towardY,
) {
  final me = board.forPhone(phoneId)!;
  final cx = me.worldCenterX;
  final cy = me.worldCenterY;
  final dx = towardX - cx;
  final dy = towardY - cy;
  final len = math.sqrt(dx * dx + dy * dy);
  final reach = HotPotatoConfig.minSwipeWorld * 3;

  sim.onTouch(
    TouchEvent(
      phoneId: phoneId,
      worldX: cx,
      worldY: cy,
      phase: TouchPhase.down,
    ),
  );
  sim.onTouch(
    TouchEvent(
      phoneId: phoneId,
      worldX: cx + dx / len * reach,
      worldY: cy + dy / len * reach,
      phase: TouchPhase.up,
    ),
  );
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
    test('a swipe toward a neighbour hands it over', () {
      final started = start(5);
      final sim = started.sim;
      final board = started.board;

      final from = sim.holder;
      final order = board.phones.map((p) => p.phoneId).toList();
      final next = order[(order.indexOf(from) + 1) % order.length];
      final target = board.forPhone(next)!;

      swipeToward(sim, board, from, target.worldCenterX, target.worldCenterY);
      expect(sim.holder, next);
    });

    test('and the other way, for the other neighbour', () {
      final started = start(5);
      final sim = started.sim;
      final board = started.board;

      final from = sim.holder;
      final order = board.phones.map((p) => p.phoneId).toList();
      final prev =
          order[(order.indexOf(from) - 1 + order.length) % order.length];
      final target = board.forPhone(prev)!;

      swipeToward(sim, board, from, target.worldCenterX, target.worldCenterY);
      expect(sim.holder, prev);
    });

    test('direction is read in world space, so every seat works', () {
      // The point of the tangent test: in a ring no two phones agree on which
      // way "right" is, and none of them needs to.
      for (var seat = 0; seat < 5; seat++) {
        final started = start(5);
        final sim = started.sim;
        final board = started.board;
        final order = board.phones.map((p) => p.phoneId).toList();

        // Walk it around to the seat under test.
        while (sim.holder != order[seat]) {
          final here = order.indexOf(sim.holder);
          final next = order[(here + 1) % order.length];
          final t = board.forPhone(next)!;
          swipeToward(sim, board, sim.holder, t.worldCenterX, t.worldCenterY);
        }
        expect(sim.holder, order[seat]);
      }
    });

    test('only the holder can throw it', () {
      final started = start(4);
      final sim = started.sim;
      final board = started.board;
      final order = board.phones.map((p) => p.phoneId).toList();
      final notHolder = order.firstWhere((id) => id != sim.holder);
      final before = sim.holder;

      final target = board.forPhone(before)!;
      swipeToward(
        sim,
        board,
        notHolder,
        target.worldCenterX,
        target.worldCenterY,
      );
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

      final order = started.board.phones.map((p) => p.phoneId).toList();
      final next = order[(order.indexOf(victim) + 1) % order.length];
      final t = started.board.forPhone(next)!;
      swipeToward(sim, started.board, victim, t.worldCenterX, t.worldCenterY);

      expect(sim.holder, victim, reason: 'no passing the blame after the bang');
    });
  });

  group('the potato itself', () {
    test('is an entity, so it slides between screens on the shared clock', () {
      final started = start(4);
      final sim = started.sim;
      final board = started.board;

      final order = board.phones.map((p) => p.phoneId).toList();
      final from = sim.holder;
      final next = order[(order.indexOf(from) + 1) % order.length];
      final target = board.forPhone(next)!;

      final startPos = sim.entities.single;
      swipeToward(sim, board, from, target.worldCenterX, target.worldCenterY);

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
