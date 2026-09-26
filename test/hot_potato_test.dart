import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Canvas;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_config.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_game.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_sim.dart';
import 'package:multiscreen_slingshot/sdk/audio/game_audio.dart';
import 'package:multiscreen_slingshot/sdk/audio/sound_cue.dart';
import 'package:multiscreen_slingshot/sdk/audio/tone.dart';
import 'package:multiscreen_slingshot/sdk/contract/entity.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/view.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/layouts.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
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
  sim.onTouch(
    TouchEvent(
      phoneId: phoneId,
      worldX: me.worldCenterX,
      worldY: me.worldCenterY,
      phase: TouchPhase.down,
    ),
  );
  sim.onTouch(
    TouchEvent(
      phoneId: phoneId,
      worldX: me.worldCenterX + wx * reach,
      worldY: me.worldCenterY + wy * reach,
      phase: TouchPhase.up,
    ),
  );
}

/// A swipe, then long enough for the potato to land in a hand and go.
///
/// A swipe only *queues* the throw — it leaves at the next catch — so the
/// holder changes up to one hop later, not on the spot.
void pass(
  HotPotatoSim sim,
  BoardLayout board,
  String phoneId, {
  required bool up,
}) {
  swipeAlongScreen(sim, board, phoneId, up: up);
  for (var i = 0; i < PlatformConfig.simHz && sim.holder == phoneId; i++) {
    sim.step(1 / PlatformConfig.simHz);
  }
}

Entity potatoOf(HotPotatoSim sim) =>
    sim.entities.firstWhere((e) => e.kind == 'potato');

/// The seats in the order they sit round the ring, by angle.
///
/// Deliberately *not* the order the compiled board hands them over: that is
/// reading order, top to bottom and left to right, which on a ring puts phones
/// from opposite sides of the table next to each other in the list.
List<String> ringOrder(BoardLayout board) {
  final cx = board.board.centerX;
  final cy = board.board.centerY;
  final seats = List.of(board.slices)
    ..sort(
      (a, b) => math
          .atan2(a.screen.centerY - cy, a.screen.centerX - cx)
          .compareTo(math.atan2(b.screen.centerY - cy, b.screen.centerX - cx)),
    );
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
    final other = board.forPhone(
      ring[(here + step + ring.length) % ring.length],
    )!;
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
      final lobby = LobbyInfo([for (var i = 0; i < 5; i++) phone('p$i')]);
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
      final lobby = LobbyInfo([for (var i = 0; i < 6; i++) phone('p$i')]);
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

      for (var i = 0; i < PlatformConfig.simHz * 4; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      expect(sim.sharedState['exploded'], isTrue);
      expect(sim.outcome, isNotNull);
    });

    test('lets the bang play before calling the round', () {
      final started = start(3);
      final sim = started.sim;
      final victim = sim.holder;

      // Just past the fuse: it has gone off, and it has already been paid…
      final fuseTicks =
          (HotPotatoConfig.fuseSeconds * PlatformConfig.simHz).ceil() + 1;
      for (var i = 0; i < fuseTicks; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      expect(sim.sharedState['exploded'], isTrue);
      expect(started.scores.isUsed, isTrue);
      expect(started.scores[victim], 0);
      // …but the results wait.
      expect(sim.outcome, isNull);

      final holdTicks =
          (HotPotatoConfig.blastHoldSeconds * PlatformConfig.simHz).ceil() - 2;
      for (var i = 0; i < holdTicks; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      expect(sim.outcome, isNull, reason: 'called before the hold was up');

      for (var i = 0; i < 4; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
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
      expect(
        outcome.lines![victim],
        isNotNull,
        reason: 'the loser is told why',
      );

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

    test('at three phones only the holder goes without, once', () {
      final started = start(3);
      final sim = started.sim;

      for (var i = 0; i < PlatformConfig.simHz * 20; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      final victim = sim.holder;

      Map<String, int> totals() => {
        for (final e in started.scores.view.ranked) e.phoneId: e.total,
      };
      final paid = totals();
      expect(paid[victim], 0);
      for (final e in paid.entries.where((e) => e.key != victim)) {
        expect(
          e.value,
          HotPotatoConfig.clearOfBlastPoints,
          reason: 'both neighbours are everyone else at three phones',
        );
      }

      // Kept stepping well past the bang; it must not pay twice.
      for (var i = 0; i < PlatformConfig.simHz * 5; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      expect(totals(), paid);
    });

    test('from four phones the blast catches both neighbours', () {
      for (final n in [4, 6, 8]) {
        final started = start(n);
        final sim = started.sim;

        for (var i = 0; i < PlatformConfig.simHz * 20; i++) {
          sim.step(1 / PlatformConfig.simHz);
        }
        final victim = sim.holder;
        final outcome = sim.outcome!;

        final caught = [
          for (final e in started.scores.view.ranked)
            if (e.total == HotPotatoConfig.caughtInBlastPoints) e.phoneId,
        ];
        expect(caught, hasLength(2), reason: 'at $n phones');
        expect(started.scores[victim], 0);
        final clear = started.scores.view.ranked.where(
          (e) => e.total == HotPotatoConfig.clearOfBlastPoints,
        );
        expect(clear, hasLength(n - 3));

        expect(
          outcome.winners,
          hasLength(n - 3),
          reason: 'only those clear of the blast won',
        );
        for (final id in caught) {
          expect(outcome.winners, isNot(contains(id)));
          expect(outcome.lines![id], contains('Caught in the blast'));
        }
      }
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

      pass(sim, board, from, up: true);
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

      pass(sim, board, from, up: false);
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

        for (var hop = 0; hop < count * 3; hop++) {
          final from = sim.holder;
          pass(sim, board, from, up: hop.isEven);

          final was = ring.indexOf(from);
          final now = ring.indexOf(sim.holder);
          final seats = (now - was + count) % count;
          expect(
            seats == 1 || seats == count - 1,
            isTrue,
            reason:
                '$count players: the potato went from $from to '
                '${sim.holder}, which is $seats seats away round the ring',
          );
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
          pass(sim, board, from, up: true);

          final expected = ring[(ring.indexOf(from) + step + count) % count];
          expect(sim.holder, expected, reason: '$count players, from $from');
          visited.add(sim.holder);
        }
        expect(
          visited,
          hasLength(count),
          reason: '$count players: swiping up never reached everybody',
        );
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

      pass(sim, board, notHolder, up: true);
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

      pass(sim, started.board, victim, up: true);

      expect(sim.holder, victim, reason: 'no passing the blame after the bang');
    });

    test('a swipe waits for the potato to land in a hand', () {
      final started = start(4);
      final sim = started.sim;
      final from = sim.holder;

      // Mid-hop: in the air between the two hands.
      for (var i = 0; i < PlatformConfig.simHz ~/ 6; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      swipeAlongScreen(sim, started.board, from, up: true);
      expect(sim.holder, from, reason: 'nobody can throw what is in the air');
      expect(sim.passPending, isTrue);

      // It goes at the catch — within one hop, never later.
      final hopTicks = (HotPotatoConfig.hopSecondsCalm * PlatformConfig.simHz)
          .ceil();
      for (var i = 0; i < hopTicks && sim.holder == from; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      expect(sim.holder, isNot(from));
      expect(sim.passPending, isFalse);
    });

    test('a swipe made while it is flying goes straight back out', () {
      final started = start(5);
      final sim = started.sim;
      final board = started.board;

      final first = sim.holder;
      pass(sim, board, first, up: true);
      final second = sim.holder;

      // Swiped by the catcher before it has arrived: queued, then thrown the
      // moment it lands.
      swipeAlongScreen(sim, board, second, up: true);
      expect(sim.passPending, isTrue);
      for (var i = 0; i < PlatformConfig.simHz && sim.holder == second; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      expect(sim.holder, isNot(second));
    });
  });

  group('the potato itself', () {
    test('is an entity, so it flies between screens on the shared clock', () {
      final started = start(4);
      final sim = started.sim;
      final board = started.board;

      final ring = ringOrder(board);
      final from = sim.holder;
      final step = upStep(board, from);
      final next =
          ring[(ring.indexOf(from) + step + ring.length) % ring.length];
      final target = started.board.contextFor(Scoreboard());

      pass(sim, board, from, up: true);
      final thrown = potatoOf(sim);

      // One step is not a teleport — it is on its way.
      sim.step(1 / PlatformConfig.simHz);
      final moving = potatoOf(sim);
      expect(
        (moving.x - thrown.x).abs() + (moving.y - thrown.y).abs(),
        greaterThan(0),
      );

      // Given time, it lands on the new holder's screen, in one of their hands.
      for (var i = 0; i < PlatformConfig.simHz; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      final shadow = sim.entities.firstWhere((e) => e.kind == 'shadow');
      expect(target.phoneAt(shadow.x, shadow.y), next);
    });

    test('is juggled from hand to hand while it is held', () {
      final started = start(3);
      final sim = started.sim;
      final context = started.board.contextFor(Scoreboard());
      final holder = sim.holder;

      final seen = <double>[];
      for (var i = 0; i < PlatformConfig.simHz * 2; i++) {
        sim.step(1 / PlatformConfig.simHz);
        final p = potatoOf(sim);
        seen.add(p.x + p.y);
        // Never leaves the holder's screen.
        expect(context.phoneAt(p.x, p.y), holder);
      }
      // And it does not sit still.
      final spread = seen.reduce(math.max) - seen.reduce(math.min);
      expect(spread, greaterThan(1));
    });

    test('spins faster as the fuse burns down', () {
      final started = start(3);
      final sim = started.sim;

      double spinOver(int ticks) {
        final before = potatoOf(sim).angle;
        for (var i = 0; i < ticks; i++) {
          sim.step(1 / PlatformConfig.simHz);
        }
        return potatoOf(sim).angle - before;
      }

      final early = spinOver(PlatformConfig.simHz);
      for (var i = 0; i < PlatformConfig.simHz * 12; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      final late = spinOver(PlatformConfig.simHz);
      expect(late, greaterThan(early * 3));
    });

    test('every seat has two arms', () {
      final started = start(5);
      final arms = started.sim.entities.where((e) => e.kind == 'arm');
      expect(arms, hasLength(10));
    });

    test(
      "each seat's arms are one left and one right, on the correct sides",
      () {
        final started = start(5);
        final board = started.board.coverage.board;
        final arms = started.sim.entities
            .where((e) => e.kind == 'arm')
            .toList();
        for (final phone in started.board.phones) {
          final mine = arms.where((e) => e.props['seat'] == phone.phoneId);
          final left = mine.singleWhere((e) => e.props['left'] == true);
          final right = mine.singleWhere((e) => e.props['left'] == false);
          // The player sits outside the ring facing in. Their right is a
          // clockwise quarter turn from that, in y-down world space.
          final inX = board.centerX - phone.worldCenterX;
          final inY = board.centerY - phone.worldCenterY;
          final rightX = -inY;
          final rightY = inX;
          final side =
              (right.x - left.x) * rightX + (right.y - left.y) * rightY;
          expect(side, greaterThan(0), reason: phone.phoneId);
        }
      },
    );

    test('goes off as a blast of its own', () {
      final started = start(3);
      final sim = started.sim;

      final calm = potatoOf(sim);

      for (var i = 0; i < PlatformConfig.simHz * 20; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      // A new entity rather than the potato changing kind: descriptors are
      // only sent when an entity first appears, so a change of kind would
      // never reach the other screens.
      expect(sim.entities.where((e) => e.kind == 'potato'), isEmpty);
      final blast = sim.entities.firstWhere((e) => e.kind == 'blast');
      expect(blast.id, isNot(calm.id));
      expect(
        (blast.props['r']! as num).toDouble(),
        greaterThan((calm.props['r']! as num).toDouble()),
      );
    });
  });

  test('draws on every screen, from what actually crosses the wire', () {
    final started = start(5);
    final sim = started.sim;
    final board = started.board;

    void drawEverywhere() {
      // Descriptors and shared state as a client receives them: JSON.
      final state = (jsonDecode(jsonEncode(sim.sharedState)) as Map)
          .cast<String, Object?>();
      final entities = {
        for (final e in sim.entities)
          e.id: RenderEntity(
            descriptor: EntityDescriptor.fromJson(
              (jsonDecode(jsonEncode(e.descriptor.toJson())) as Map)
                  .cast<String, dynamic>(),
            ),
            x: e.x,
            y: e.y,
            angle: e.angle,
          ),
      };
      for (final phone in board.phones) {
        final view = const HotPotatoGame().createView(
          ViewContext(phoneId: phone.phoneId, board: board.coverage.board),
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (var i = 0; i < 3; i++) {
          view.render(
            canvas,
            Frame(
              entities: entities,
              sharedState: state,
              scores: ScoreView.empty,
              timeMs: i * 16.0,
              dt: 1 / 60,
              me: phone,
              board: board.coverage.board,
              coverage: board.coverage,
            ),
          );
        }
        recorder.endRecording();
      }
    }

    drawEverywhere(); // Fresh.
    for (var i = 0; i < PlatformConfig.simHz * 12; i++) {
      sim.step(1 / PlatformConfig.simHz);
    }
    drawEverywhere(); // Hot and smoking.
    pass(sim, board, sim.holder, up: true);
    drawEverywhere(); // In flight.
    for (var i = 0; i < PlatformConfig.simHz * 5; i++) {
      sim.step(1 / PlatformConfig.simHz);
    }
    drawEverywhere(); // Gone off.
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

  group('sound', () {
    ({HotPotatoSim sim, BoardLayout board, _HeardAudio audio}) heard(
      int count,
    ) {
      final lobby = LobbyInfo([
        for (var i = 0; i < count; i++) phone('p${i + 1}'),
      ]);
      final scores = Scoreboard();
      for (final p in lobby.phones) {
        scores.register(p.phoneId, p.label);
      }
      const game = HotPotatoGame();
      final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
      final audio = _HeardAudio();
      final context = BoardContext(
        board: board.board,
        coverage: board.coverage,
        scores: scores,
        slices: board.slices,
        roster: Roster([
          for (var i = 0; i < count; i++)
            Player(phoneId: 'p${i + 1}', color: PlayerPalette.all[i]),
        ]),
        audio: audio,
      );
      final sim = HotPotatoSim(context, random: math.Random(4));
      scores.beginRound();
      return (sim: sim, board: board, audio: audio);
    }

    void run(HotPotatoSim sim, double seconds) {
      for (var i = 0; i < (seconds * PlatformConfig.simHz).round(); i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
    }

    test('the kettle is one tone, gliding low to high over the whole fuse, '
        'on the holder\'s phone', () {
      final h = heard(4);
      run(h.sim, 0.02);

      final kettle = h.audio.tones.single;
      expect(kettle.phoneId, h.sim.holder);
      expect(kettle.tone.fromHz, closeTo(HotPotatoConfig.kettleLowHz, 2));
      expect(kettle.tone.toHz, HotPotatoConfig.kettleHighHz);
      expect(
        kettle.tone.glide.inMilliseconds,
        closeTo(HotPotatoConfig.fuseSeconds * 1000, 50),
        reason: 'it should reach the top exactly at the bang',
      );
      expect(kettle.tone.toVolume, greaterThan(kettle.tone.volume));
    });

    test('left on one phone, the kettle is never restarted', () {
      final h = heard(3);
      run(h.sim, 5);
      expect(h.audio.tones, hasLength(1), reason: 'the phone glides it');
    });

    test('left alone, it boings in the holder\'s hands and nowhere else', () {
      final h = heard(4);
      run(h.sim, 2);

      final boings = h.audio.plays.where((p) => p.cue == HotPotatoConfig.boing);
      expect(boings.length, greaterThan(2));
      expect(boings.every((p) => p.phoneId == h.sim.holder), isTrue);
      expect(
        h.audio.plays.where((p) => p.cue == HotPotatoConfig.woosh),
        isEmpty,
      );
    });

    test('a pass wooshes from the thrower, then boings at the catcher', () {
      final h = heard(4);
      final from = h.sim.holder;
      pass(h.sim, h.board, from, up: true);
      final to = h.sim.holder;
      run(h.sim, 1);

      final hits = [
        for (final p in h.audio.plays)
          if (p.cue == HotPotatoConfig.woosh || p.cue == HotPotatoConfig.boing)
            p,
      ];
      final woosh = hits.indexWhere((p) => p.cue == HotPotatoConfig.woosh);
      expect(hits[woosh].phoneId, from);
      expect(hits[woosh + 1].cue, HotPotatoConfig.boing);
      expect(hits[woosh + 1].phoneId, to, reason: 'the catch is a landing');
    });

    test('the kettle is the holder\'s alone: silent in the air, back on the '
        'catcher\'s phone', () {
      final h = heard(4);
      final from = h.sim.holder;
      run(h.sim, 0.02);
      // [pass] stops on the throw itself: the potato has just left.
      pass(h.sim, h.board, from, up: true);
      final to = h.sim.holder;

      final thrower = h.audio.tones.single;
      expect(thrower.phoneId, from);
      expect(
        h.audio.stopped,
        contains(thrower.handle),
        reason: 'the throw silences the thrower',
      );

      run(h.sim, 1); // Well past the catch.
      final kettles = h.audio.tones;
      expect(kettles, hasLength(2), reason: 'nothing plays while it flies');
      expect(kettles.last.phoneId, to);
      expect(h.audio.stopped, isNot(contains(kettles.last.handle)));

      // The catcher picks the glide up where the fuse has got to: the same
      // curve, reaching the same top at the same moment.
      final first = kettles.first.tone;
      final last = kettles.last.tone;
      final handoverMs = first.glide.inMilliseconds - last.glide.inMilliseconds;
      expect(last.fromHz, closeTo(first.hzAt(handoverMs.toDouble()), 1));
      expect(last.toHz, first.toHz);
    });

    test('a fuse that runs out mid-throw waits for the catch', () {
      final h = heard(4);
      run(h.sim, HotPotatoConfig.fuseSeconds - 1.2);

      // Pass it on and on through the last second: every catcher swipes while
      // it is still coming, so it goes straight back out, and it is in the air
      // almost the whole time — including when the fuse runs out.
      var waitedInTheAir = false;
      for (var i = 0; i < PlatformConfig.simHz * 3; i++) {
        if (!h.sim.passPending) {
          swipeAlongScreen(h.sim, h.board, h.sim.holder, up: true);
        }
        h.sim.step(1 / PlatformConfig.simHz);
        if (h.sim.sharedState['exploded'] == true) break;
        if (h.sim.sharedState['secondsLeft'] == 0) waitedInTheAir = true;
      }

      expect(waitedInTheAir, isTrue, reason: 'it went off in the air');
      expect(h.sim.sharedState['exploded'], isTrue);

      // It went off on landing, in the catcher's hand: on their phone, and
      // theirs is the loss.
      final bang = h.audio.plays.last;
      expect(bang.cue, HotPotatoConfig.explosion);
      expect(bang.phoneId, h.sim.holder);
      final landings = h.audio.plays
          .where(
            (p) =>
                p.cue == HotPotatoConfig.woosh || p.cue == HotPotatoConfig.boing,
          )
          .toList();
      expect(
        landings.last.cue,
        HotPotatoConfig.woosh,
        reason: 'the catch that would have been a woosh was the bang instead',
      );
      run(h.sim, HotPotatoConfig.blastHoldSeconds + 0.1);
      expect(h.sim.outcome!.winners, isNot(contains(h.sim.holder)));
    });

    test('in the holder\'s hands it goes off on time, even mid-juggle', () {
      final h = heard(3);
      run(h.sim, HotPotatoConfig.fuseSeconds - 0.01);
      expect(h.sim.sharedState['exploded'], isFalse);
      run(h.sim, 0.05);
      expect(h.sim.sharedState['exploded'], isTrue);
    });

    test('the kettle stops dead for the bang', () {
      final h = heard(3);
      run(h.sim, HotPotatoConfig.fuseSeconds + 1);

      final kettle = h.audio.tones.single;
      expect(h.audio.stopped, contains(kettle.handle));

      final bang = h.audio.plays.last;
      expect(bang.cue, HotPotatoConfig.explosion);
      expect(bang.phoneId, h.sim.holder);
      expect(
        h.audio.plays.where((p) => p.cue == HotPotatoConfig.explosion),
        hasLength(1),
        reason: 'the bang goes off once, however long the blast is held',
      );
    });
  });
}

class _Tone {
  _Tone(this.handle, this.phoneId, this.tone);
  final SoundHandle handle;
  final String phoneId;
  final Tone tone;
}

class _Play {
  _Play(this.handle, this.phoneId, this.cue, this.loop, this.volume);
  final SoundHandle handle;
  final String phoneId;
  final SoundCue cue;
  final bool loop;
  final double volume;
}

/// Hears what the sim asks for, without a network or a speaker.
class _HeardAudio implements GameAudio {
  final plays = <_Play>[];
  final tones = <_Tone>[];
  final stopped = <SoundHandle>[];
  var _next = 1;

  @override
  SoundHandle playGeneral(
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
  }) => throw StateError('Hot Potato only ever plays on a phone');

  @override
  SoundHandle playOnPhone(
    Player player,
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
  }) {
    final handle = SoundHandle(_next++);
    plays.add(_Play(handle, player.phoneId, cue, loop, volume));
    return handle;
  }

  @override
  SoundHandle playToneOnPhone(
    Player player,
    Tone tone, {
    bool persist = false,
  }) {
    final handle = SoundHandle(_next++);
    tones.add(_Tone(handle, player.phoneId, tone));
    return handle;
  }

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) {
    if (handle != SoundHandle.none) stopped.add(handle);
  }

  @override
  void stopRoundSounds() {}
}
