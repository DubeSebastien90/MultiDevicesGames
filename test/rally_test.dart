import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/rally/rally_config.dart';
import 'package:multiscreen_slingshot/games/rally/rally_game.dart';
import 'package:multiscreen_slingshot/games/rally/rally_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A physics ball rallied back and forth on `Layouts.row` — the layout's own
/// doc names "pong" as one of the arrangements it exists for, and this is the
/// first game to actually play it: a rally that resets to the middle after
/// every point, rather than Push of War's single accumulating push to one
/// static line.
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

const dt = 1 / PlatformConfig.simHz;

({
  RallySim sim,
  BoardLayout board,
  Scoreboard scores,
  Set<String> teamA,
  Set<String> teamB,
})
start(int count) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = RallyGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = RallySim(board.contextFor(scores));
  scores.beginRound();

  // The same left/right split the sim derives internally, from where the
  // phones physically ended up.
  final sorted = List.of(board.slices)
    ..sort((a, b) => a.viewport.centerX.compareTo(b.viewport.centerX));
  final half = sorted.length ~/ 2;
  final teamA = {for (final s in sorted.take(half)) s.phoneId};
  final teamB = {for (final s in sorted.skip(half)) s.phoneId};

  return (sim: sim, board: board, scores: scores, teamA: teamA, teamB: teamB);
}

void tapAt(RallySim sim, String phoneId, double x, double y) {
  sim.onTouch(
    TouchEvent(phoneId: phoneId, worldX: x, worldY: y, phase: TouchPhase.down),
  );
}

void main() {
  test('two equal teams for every even table the manifest allows', () {
    const manifest = RallyGame();
    for (final count in [2, 4, 6, 8]) {
      expect(manifest.manifest.fits(count), isTrue);
      final started = start(count);
      expect(started.teamA, hasLength(count ~/ 2));
      expect(started.teamB, hasLength(count ~/ 2));
      expect(started.teamA.intersection(started.teamB), isEmpty);
    }
    expect(manifest.manifest.fits(3), isFalse, reason: 'teams must be even');
  });

  test('the ball serves from the centre of the lane, already moving', () {
    final started = start(4);
    final ball = started.sim.entities.single;
    expect(ball.kind, 'ball');
    expect(ball.x, closeTo(started.board.board.centerX, 1e-6));
    expect(ball.y, closeTo(started.board.board.centerY, 1e-6));
    expect(ball.vx.abs(), greaterThan(0));
  });

  test('a touch from nobody seated does not touch the ball', () {
    final started = start(4);
    final ball = started.sim.entities.single;
    final before = ball.vx;
    tapAt(started.sim, 'ghost', ball.x, ball.y);
    expect(started.sim.entities.single.vx, closeTo(before, 1e-9));
  });

  test('a tap far from the ball does nothing', () {
    final started = start(4);
    final before = started.sim.entities.single.vx;
    final farCorner = started.board.board.left;
    tapAt(started.sim, started.teamA.first, farCorner, started.board.board.top);
    expect(started.sim.entities.single.vx, closeTo(before, 1e-9));
  });

  test('a tap that lands near the ball reverses its direction', () {
    final started = start(4);
    final sim = started.sim;
    final before = sim.entities.single;
    final wasMovingRight = before.vx > 0;

    tapAt(sim, started.teamA.first, before.x, before.y);

    final after = sim.entities.single;
    expect(after.vx > 0, isNot(wasMovingRight));
    expect(after.vx.abs(), greaterThan(before.vx.abs()));
  });

  test('a second tap inside the cooldown does not add another return', () {
    final started = start(4);
    final sim = started.sim;
    final ball = sim.entities.single;

    tapAt(sim, started.teamA.first, ball.x, ball.y);
    final onceReturned = sim.entities.single.vx;

    tapAt(sim, started.teamB.first, ball.x, ball.y);
    expect(sim.entities.single.vx, closeTo(onceReturned, 1e-9));
  });

  test(
    'the ball sweeps continuously across the boundary between two phones, '
    'never jumping a slice',
    () {
      final started = start(4);
      final sim = started.sim;
      final slices = List.of(started.board.slices)
        ..sort((a, b) => a.viewport.centerX.compareTo(b.viewport.centerX));

      int? sliceIndexOf(double x) {
        for (var i = 0; i < slices.length; i++) {
          final v = slices[i].viewport;
          if (x >= v.left && x <= v.right) return i;
        }
        return null;
      }

      final visited = <int>{};
      var lastIndex = sliceIndexOf(sim.entities.single.x);
      if (lastIndex != null) visited.add(lastIndex);

      var ticks = 0;
      const maxTicks = PlatformConfig.simHz * 30;
      while (visited.length < 2 && sim.outcome == null && ticks < maxTicks) {
        sim.step(dt);
        final idx = sliceIndexOf(sim.entities.single.x);
        if (idx != null) {
          visited.add(idx);
          if (lastIndex != null) {
            expect(
              (idx - lastIndex).abs(),
              lessThanOrEqualTo(1),
              reason:
                  'the ball jumped from slice $lastIndex straight to slice '
                  '$idx without sweeping through the seam between them',
            );
          }
          lastIndex = idx;
        }
        ticks++;
      }

      expect(
        visited.length,
        greaterThan(1),
        reason:
            "the ball never crossed onto a neighbouring phone's screen — it "
            'stayed on the one it started on',
      );
    },
  );

  test('an unreturned rally concedes a point and re-serves from the centre', () {
    final started = start(4);
    final sim = started.sim;

    var ticks = 0;
    const maxTicks = PlatformConfig.simHz * 30;
    while ((sim.sharedState['pointsA'] as int) == 0 &&
        (sim.sharedState['pointsB'] as int) == 0 &&
        ticks < maxTicks) {
      sim.step(dt);
      ticks++;
    }

    final pointsA = sim.sharedState['pointsA'] as int;
    final pointsB = sim.sharedState['pointsB'] as int;
    expect(pointsA + pointsB, 1, reason: 'exactly one point should be in');
    expect(sim.outcome, isNull, reason: 'one point is not the match');

    final winners = pointsA == 1 ? started.teamA : started.teamB;
    final losers = pointsA == 1 ? started.teamB : started.teamA;
    for (final id in winners) {
      expect(started.scores[id], RallyConfig.pointValue);
    }
    for (final id in losers) {
      expect(started.scores[id], 0);
    }

    final ball = sim.entities.single;
    expect(ball.x, closeTo(started.board.board.centerX, 1e-6));
    expect(ball.y, closeTo(started.board.board.centerY, 1e-6));
  });

  test(
    'a team that always defends its own baseline racks up points until it '
    'wins',
    () {
      final started = start(4);
      final sim = started.sim;
      final defender = started.teamA.first;

      var ticks = 0;
      const maxTicks = PlatformConfig.simHz * 180;
      while (sim.outcome == null && ticks < maxTicks) {
        final ball = sim.entities.single;
        // Only ever defends the left baseline — the right side is left wide
        // open, so every point goes the same way.
        if (ball.vx < 0) {
          tapAt(sim, defender, ball.x, ball.y);
        }
        sim.step(dt);
        ticks++;
      }

      final outcome = sim.outcome;
      expect(outcome, isNotNull, reason: 'nobody ever reached the target');
      expect(outcome!.kind, OutcomeKind.contest);
      expect(outcome.winners, started.teamA);
      for (final id in started.teamA) {
        expect(started.scores[id], greaterThanOrEqualTo(RallyConfig.targetPoints));
      }
    },
  );

  test('a rally nobody ever touches times out to a draw when tied', () {
    final started = start(4);
    final sim = started.sim;
    const maxTicks = PlatformConfig.simHz * RallyConfig.maxRoundSeconds;
    for (var i = 0; i < maxTicks + 1 && sim.outcome == null; i++) {
      sim.step(dt);
    }
    final outcome = sim.outcome;
    expect(outcome, isNotNull);
    // With nobody ever returning it, serves alternate ends and points
    // alternate teams — an even points-race times out level.
    if ((sim.sharedState['pointsA'] as int) ==
        (sim.sharedState['pointsB'] as int)) {
      expect(outcome!.kind, OutcomeKind.draw);
    } else {
      expect(outcome!.kind, OutcomeKind.contest);
    }
  });

  test('reset puts the ball and the score back', () {
    final started = start(4);
    final sim = started.sim;
    final defender = started.teamA.first;

    var ticks = 0;
    const maxTicks = PlatformConfig.simHz * 180;
    while (sim.outcome == null && ticks < maxTicks) {
      final ball = sim.entities.single;
      if (ball.vx < 0) tapAt(sim, defender, ball.x, ball.y);
      sim.step(dt);
      ticks++;
    }
    expect(sim.outcome, isNotNull);

    sim.reset();

    expect(sim.outcome, isNull);
    expect(sim.sharedState['pointsA'], 0);
    expect(sim.sharedState['pointsB'], 0);
    final ball = sim.entities.single;
    expect(ball.x, closeTo(started.board.board.centerX, 1e-6));
    expect(ball.y, closeTo(started.board.board.centerY, 1e-6));
  });
}
