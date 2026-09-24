import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/tandem/tandem_config.dart';
import 'package:multiscreen_slingshot/games/tandem/tandem_game.dart';
import 'package:multiscreen_slingshot/games/tandem/tandem_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A game with no physics and no entities, on a board that is one straight
/// line — the same shape of test as `test/hot_potato_test.dart`.
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

({TandemSim sim, BoardLayout board, Scoreboard scores}) start(
  int count, {
  math.Random? random,
}) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = TandemGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = TandemSim(board.contextFor(scores), random: random);
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

void tap(TandemSim sim, String phoneId) {
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: 0,
    worldY: 0,
    phase: TouchPhase.down,
  ));
}

/// Steps until a pair lights, then returns which two phones it is.
(String, String) waitForLight(TandemSim sim) {
  for (var i = 0; i < PlatformConfig.simHz * 5; i++) {
    sim.step(1 / PlatformConfig.simHz);
    final a = sim.sharedState['litA'] as String?;
    final b = sim.sharedState['litB'] as String?;
    if (a != null && b != null) return (a, b);
  }
  fail('no pair ever lit');
}

void main() {
  group('the column board', () {
    test('lines every phone up top to bottom, one straight column', () {
      final started = start(4);
      final centers = started.board.phones
          .map((p) => (x: p.worldCenterX, y: p.worldCenterY))
          .toList();
      // Every phone shares the same x — it is one line, not a block.
      for (final c in centers) {
        expect(c.x, closeTo(centers.first.x, 1e-6));
      }
      // And the y coordinates are strictly increasing top to bottom, which is
      // what makes consecutive board slices real neighbours.
      final ys = centers.map((c) => c.y).toList();
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]));
      }
    });

    test('needs at least two phones', () {
      expect(const TandemGame().manifest.smallestTable, 2);
      expect(const TandemGame().manifest.fits(1), isFalse);
      expect(const TandemGame().manifest.fits(2), isTrue);
    });
  });

  group('lighting a pair', () {
    test('nothing is lit before the opening delay has passed', () {
      final started = start(3, random: math.Random(1));
      final sim = started.sim;
      expect(sim.sharedState['litA'], isNull);
      expect(sim.sharedState['litB'], isNull);

      // Just short of the delay.
      final ticks =
          ((TandemConfig.initialDelaySeconds - 0.05) * PlatformConfig.simHz)
              .floor();
      for (var i = 0; i < ticks; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      expect(sim.sharedState['litA'], isNull);
    });

    test('the lit pair is always two phones actually next to each other', () {
      final started = start(5, random: math.Random(2));
      final board = started.board;
      final order = board.slices.map((s) => s.phoneId).toList();

      for (var round = 0; round < 6; round++) {
        started.sim.reset();
        final (a, b) = waitForLight(started.sim);
        final ia = order.indexOf(a);
        final ib = order.indexOf(b);
        expect((ia - ib).abs(), 1,
            reason: '$a and $b lit together but are not neighbours');
      }
    });
  });

  group('syncing a tap', () {
    test('one phone tapping alone scores nothing', () {
      final started = start(2, random: math.Random(3));
      final sim = started.sim;
      final (a, _) = waitForLight(sim);

      tap(sim, a);
      expect(sim.sharedState['successes'], 0);
      expect(started.scores[a], 0);
      // Still waiting on the other half.
      expect(sim.sharedState['litA'], isNotNull);
    });

    test('a touch from outside the lit pair changes nothing', () {
      final started = start(4, random: math.Random(4));
      final sim = started.sim;
      final (a, b) = waitForLight(sim);
      final bystander = started.board.slices
          .map((s) => s.phoneId)
          .firstWhere((id) => id != a && id != b);

      tap(sim, bystander);
      expect(sim.sharedState['litA'], a);
      expect(sim.sharedState['litB'], b);
      expect(sim.sharedState['tappedA'], isFalse);
      expect(sim.sharedState['tappedB'], isFalse);
    });

    test('both halves tapping in time scores for both and clears the pair', () {
      final started = start(2, random: math.Random(5));
      final sim = started.sim;
      final (a, b) = waitForLight(sim);

      tap(sim, a);
      tap(sim, b);

      expect(sim.sharedState['successes'], 1);
      expect(started.scores[a], TandemConfig.pointsPerSuccess);
      expect(started.scores[b], TandemConfig.pointsPerSuccess);
      expect(sim.sharedState['litA'], isNull);
      expect(sim.sharedState['litB'], isNull);
    });

    test('missing the window scores nothing and moves on', () {
      final started = start(2, random: math.Random(6));
      final sim = started.sim;
      final (a, _) = waitForLight(sim);
      tap(sim, a); // Only one half ever taps.

      // Past the window, but short of the cooldown ending and a fresh pair
      // lighting again — with two phones the only pair there is.
      final ticks =
          ((TandemConfig.windowSeconds + 0.1) * PlatformConfig.simHz).round();
      for (var i = 0; i < ticks; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }

      expect(sim.sharedState['successes'], 0);
      expect(sim.sharedState['litA'], isNull,
          reason: 'a missed attempt still clears, so a new one can start');
    });
  });

  group('ending the round', () {
    test('reaching the target wins it for the table', () {
      final started = start(2, random: math.Random(7));
      final sim = started.sim;

      for (var n = 0; n < TandemConfig.targetSuccesses; n++) {
        final (a, b) = waitForLight(sim);
        tap(sim, a);
        tap(sim, b);
      }

      expect(sim.sharedState['successes'], TandemConfig.targetSuccesses);
      final outcome = sim.outcome;
      expect(outcome, isNotNull);
      expect(outcome!.kind, OutcomeKind.shared);
      expect(outcome.won, isTrue);
      // Polled repeatedly, as the platform does — always the same verdict.
      expect(identical(sim.outcome, outcome), isTrue);
    });

    test('running out of time loses it, whatever the tally', () {
      final started = start(2, random: math.Random(8));
      final sim = started.sim;

      // A second past the boundary, not exactly on it — summing thousands of
      // 1/60 steps lands a hair short of the nominal total by itself.
      for (var i = 0;
          i < PlatformConfig.simHz * (TandemConfig.roundSeconds + 1);
          i++) {
        sim.step(1 / PlatformConfig.simHz);
      }

      expect(sim.outcome, isNotNull);
      expect(sim.outcome!.kind, OutcomeKind.shared);
      expect(sim.outcome!.won, isFalse);
      expect(sim.sharedState['successes'], lessThan(TandemConfig.targetSuccesses));
    });

    test('a replayed round does not reuse the last verdict', () {
      final started = start(2, random: math.Random(9));
      final sim = started.sim;
      for (var i = 0;
          i < PlatformConfig.simHz * (TandemConfig.roundSeconds + 1);
          i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      expect(sim.outcome, isNotNull);

      sim.reset();
      expect(sim.outcome, isNull);
      expect(sim.sharedState['successes'], 0);
      expect(sim.sharedState['litA'], isNull);
    });
  });
}
