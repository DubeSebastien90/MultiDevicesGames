import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/plummet/plummet_config.dart';
import 'package:multiscreen_slingshot/games/plummet/plummet_game.dart';
import 'package:multiscreen_slingshot/games/plummet/plummet_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A ball falls under real gravity down a `Layouts.column` shaft, dodging
/// wall spikes that jut in from alternating sides at every phone after the
/// first. Driven through the SDK contract — no host, no sockets, no
/// rendering.
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

({PlummetSim sim, BoardLayout board, Scoreboard scores}) start(int count) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = PlummetGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = PlummetSim(board.contextFor(scores));
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

({double x, double y, double vy}) ball(PlummetSim sim) {
  final e = sim.entities.firstWhere((e) => e.kind == 'ball');
  return (x: e.x, y: e.y, vy: e.vy);
}

/// Taps just to one side of the ball's current position — close enough to be
/// reach-gated in, far enough to have a clear left/right sign.
void nudge(PlummetSim sim, String phoneId, {required bool pushRight}) {
  final b = ball(sim);
  final tapX = b.x + (pushRight ? -0.2 : 0.2);
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: tapX,
    worldY: b.y,
    phase: TouchPhase.down,
  ));
}

void main() {
  group('the table', () {
    test('takes two to eight and nothing else', () {
      const game = PlummetGame();
      for (final n in [2, 3, 4, 5, 6, 7, 8]) {
        expect(game.manifest.fits(n), isTrue, reason: '$n should play');
      }
      expect(game.manifest.fits(1), isFalse);
      expect(game.manifest.fits(9), isFalse);
    });

    test('every size it accepts stacks into a column and runs', () {
      for (final count in [2, 3, 4, 8]) {
        final started = start(count);
        expect(started.board.slices, hasLength(count));
        started.sim.step(dt);
        expect(started.sim.outcome, isNull);
      }
    });
  });

  group('gravity', () {
    test('an untouched ball keeps falling, faster over time', () {
      final started = start(4);
      final sim = started.sim;
      final before = ball(sim);
      for (var i = 0; i < 30; i++) {
        sim.step(dt);
      }
      final after = ball(sim);
      expect(after.y, greaterThan(before.y));
      expect(after.vy, greaterThan(0));
    });

    test('the ball starts at the top of the shaft, dead centre', () {
      final started = start(3);
      final b = ball(started.sim);
      expect(b.x, closeTo(started.board.board.centerX, 1e-6));
      expect(b.y, lessThan(started.board.board.top + 5));
    });
  });

  group('spikes', () {
    test('an unsteered ball runs straight into the first spike and the '
        'round is lost, latched', () {
      final started = start(2);
      final sim = started.sim;

      var ticks = 0;
      const maxTicks = PlatformConfig.simHz * 20;
      while (sim.outcome == null && ticks < maxTicks) {
        sim.step(dt);
        ticks++;
      }

      final outcome = sim.outcome;
      expect(outcome, isNotNull, reason: 'nobody steered — it should crash');
      expect(outcome!.kind, OutcomeKind.shared);
      expect(outcome.won, isFalse);
      expect(identical(sim.outcome, outcome), isTrue);
    });

    test('steering clear of the one spike a two-phone table has lets the '
        'ball reach the bottom and win', () {
      final started = start(2);
      final sim = started.sim;

      var ticks = 0;
      const maxTicks = PlatformConfig.simHz * 20;
      while (sim.outcome == null && ticks < maxTicks) {
        // The single spike on a two-phone table juts from the left, so the
        // ball is steered right, clear of it, on every tap that connects.
        nudge(sim, 'p1', pushRight: true);
        sim.step(dt);
        ticks++;
      }

      final outcome = sim.outcome;
      expect(outcome, isNotNull);
      expect(outcome!.kind, OutcomeKind.shared);
      expect(outcome.won, isTrue);
      for (final id in ['p1', 'p2']) {
        expect(started.scores[id], PlummetConfig.bonusPerPhone);
      }
    });
  });

  group('touch', () {
    test('a tap too far from the ball does nothing', () {
      final started = start(3);
      final sim = started.sim;
      final before = ball(sim);
      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: before.x + PlummetConfig.reachRadius + 5,
        worldY: before.y,
        phase: TouchPhase.down,
      ));
      expect(ball(sim).x, closeTo(before.x, 1e-9));
    });

    test('a move or up phase is not a tap', () {
      final started = start(3);
      final sim = started.sim;
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
      expect(ball(sim).x, closeTo(b.x, 1e-9));
    });

    test('a connecting tap sets the ball moving away from where the finger '
        'landed', () {
      final started = start(3);
      final sim = started.sim;
      nudge(sim, 'p1', pushRight: true);
      final e = sim.entities.firstWhere((e) => e.kind == 'ball');
      expect(e.vx, greaterThan(0));
    });

    test('a second tap inside the cooldown does not add another push', () {
      final started = start(3);
      final sim = started.sim;
      nudge(sim, 'p1', pushRight: true);
      final onceVx = sim.entities.firstWhere((e) => e.kind == 'ball').vx;

      // Immediately try to shove it back the other way — the cooldown must
      // block it, same tick, no time passed.
      nudge(sim, 'p1', pushRight: false);
      final stillVx = sim.entities.firstWhere((e) => e.kind == 'ball').vx;
      expect(stillVx, closeTo(onceVx, 1e-9));
    });
  });

  test(
    'the ball sweeps continuously across the boundary between two phones, '
    'never jumping a slice',
    () {
      final started = start(4);
      final sim = started.sim;
      final slices = List.of(started.board.slices)
        ..sort((a, b) => a.viewport.centerY.compareTo(b.viewport.centerY));

      int? sliceIndexOf(double y) {
        for (var i = 0; i < slices.length; i++) {
          final v = slices[i].viewport;
          if (y >= v.top && y <= v.bottom) return i;
        }
        return null;
      }

      final visited = <int>{};
      var lastIndex = sliceIndexOf(ball(sim).y);
      if (lastIndex != null) visited.add(lastIndex);

      var ticks = 0;
      const maxTicks = PlatformConfig.simHz * 10;
      while (visited.length < 2 && sim.outcome == null && ticks < maxTicks) {
        sim.step(dt);
        final idx = sliceIndexOf(ball(sim).y);
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

  test('reset puts the ball back at the top with the clock zeroed', () {
    final started = start(2);
    final sim = started.sim;
    var ticks = 0;
    const maxTicks = PlatformConfig.simHz * 20;
    while (sim.outcome == null && ticks < maxTicks) {
      sim.step(dt);
      ticks++;
    }
    expect(sim.outcome, isNotNull);

    sim.reset();

    expect(sim.outcome, isNull);
    final b = ball(sim);
    expect(b.x, closeTo(started.board.board.centerX, 1e-6));
    expect(b.vy, 0);
  });
}
