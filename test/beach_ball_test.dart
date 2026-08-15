import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/beach_ball/beach_ball_config.dart';
import 'package:multiscreen_slingshot/games/beach_ball/beach_ball_game.dart';
import 'package:multiscreen_slingshot/games/beach_ball/beach_ball_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A ball, gravity, and a row of phones. Driven through the SDK contract — no
/// host, no sockets, no rendering.
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

({BeachBallSim sim, BoardLayout board, Scoreboard scores}) start(int count) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = BeachBallGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = BeachBallSim(board.contextFor(scores));
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

const _dt = 1 / 60;

({double x, double y, double vy}) ball(BeachBallSim sim) {
  final e = sim.entities.firstWhere((e) => e.kind == 'ball');
  return (x: e.x, y: e.y, vy: e.vy);
}

/// Taps exactly on the ball's current position — a player who never misses,
/// so a round with one of these attached should never end in a loss.
void perfectTap(BeachBallSim sim, String phoneId) {
  final b = ball(sim);
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: b.x,
    worldY: b.y,
    phase: TouchPhase.down,
  ));
}

void main() {
  group('the table', () {
    test('takes two to six and nothing else', () {
      const game = BeachBallGame();
      for (final n in [2, 3, 4, 5, 6]) {
        expect(game.manifest.fits(n), isTrue, reason: '$n should play');
      }
      expect(game.manifest.fits(1), isFalse);
      expect(game.manifest.fits(7), isFalse);
    });

    test('every size it accepts lays out and runs', () {
      for (final count in [2, 3, 4, 6]) {
        final started = start(count);
        expect(started.board.slices, hasLength(count));
        started.sim.step(_dt);
        expect(started.sim.outcome, isNull);
      }
    });
  });

  group('gravity', () {
    test('an untouched ball keeps falling', () {
      final started = start(2);
      final sim = started.sim;
      final before = ball(sim);
      for (var i = 0; i < 30; i++) {
        sim.step(_dt);
      }
      final after = ball(sim);
      expect(after.y, greaterThan(before.y));
      expect(after.vy, greaterThan(0));
    });

    test('left alone long enough, it hits the ground and the round is lost',
        () {
      final started = start(2);
      final sim = started.sim;
      for (var i = 0; i < 60 * 10 && sim.outcome == null; i++) {
        sim.step(_dt);
      }
      final outcome = sim.outcome;
      expect(outcome, isNotNull);
      expect(outcome!.kind, OutcomeKind.shared);
      expect(outcome.won, isFalse);

      // Polled repeatedly, as the platform does — always the same verdict.
      expect(identical(sim.outcome, outcome), isTrue);
    });
  });

  group('bumping it', () {
    test('a tap that lands on the falling ball sends it back up and scores',
        () {
      final started = start(2);
      final sim = started.sim;
      // Let it start falling.
      for (var i = 0; i < 10; i++) {
        sim.step(_dt);
      }
      expect(ball(sim).vy, greaterThan(BeachBallConfig.mustBeFallingVy));

      perfectTap(sim, 'p1');

      expect(ball(sim).vy, lessThan(0));
      expect(sim.saves, 1);
      expect(started.scores['p1'], 1);
    });

    test('a tap too far from the ball does nothing', () {
      final started = start(2);
      final sim = started.sim;
      for (var i = 0; i < 10; i++) {
        sim.step(_dt);
      }
      final b = ball(sim);
      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: b.x + BeachBallConfig.reachRadius + 5,
        worldY: b.y,
        phase: TouchPhase.down,
      ));

      expect(sim.saves, 0);
      expect(started.scores['p1'], 0);
      expect(ball(sim).vy, greaterThan(0));
    });

    test('a rising ball cannot be bumped again — no spamming it into a hover',
        () {
      final started = start(2);
      final sim = started.sim;
      for (var i = 0; i < 10; i++) {
        sim.step(_dt);
      }
      perfectTap(sim, 'p1');
      expect(sim.saves, 1);

      // Same instant, still rising: a second tap must not connect.
      perfectTap(sim, 'p1');
      expect(sim.saves, 1);
      expect(started.scores['p1'], 1);
    });

    test('a move or up phase is not a tap', () {
      final started = start(2);
      final sim = started.sim;
      for (var i = 0; i < 10; i++) {
        sim.step(_dt);
      }
      final b = ball(sim);
      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: b.x,
        worldY: b.y,
        phase: TouchPhase.move,
      ));
      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: b.x,
        worldY: b.y,
        phase: TouchPhase.up,
      ));
      expect(sim.saves, 0);
    });
  });

  group('a table that never misses', () {
    test('keeps it up for the full 25 seconds and wins, saves tallied', () {
      final started = start(3);
      final sim = started.sim;

      final steps = (BeachBallConfig.targetSeconds / _dt).ceil() + 1;
      for (var i = 0; i < steps && sim.outcome == null; i++) {
        perfectTap(sim, 'p1');
        sim.step(_dt);
      }

      final outcome = sim.outcome;
      expect(outcome, isNotNull);
      expect(outcome!.kind, OutcomeKind.shared);
      expect(outcome.won, isTrue);
      expect(sim.saves, greaterThan(0));
      expect(started.scores['p1'], sim.saves);
    });
  });

  test('reset puts the ball back at the top with the clock and score zeroed',
      () {
    final started = start(2);
    final sim = started.sim;
    for (var i = 0; i < 60 * 10 && sim.outcome == null; i++) {
      sim.step(_dt);
    }
    expect(sim.outcome, isNotNull);

    sim.reset();

    expect(sim.outcome, isNull);
    expect(sim.saves, 0);
    expect(sim.elapsed, 0);
    expect(ball(sim).vy, 0);
  });
}
