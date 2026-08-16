import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/photo_finish/photo_finish_config.dart';
import 'package:multiscreen_slingshot/games/photo_finish/photo_finish_game.dart';
import 'package:multiscreen_slingshot/games/photo_finish/photo_finish_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A plain, mid-size phone — the same numbers `hot_potato_test.dart` uses, so
/// the two boards are comparable.
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

({PhotoFinishSim sim, BoardLayout board, Scoreboard scores}) start(int count) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = PhotoFinishGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = PhotoFinishSim(board.contextFor(scores));
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

/// A finger touching down and lifting on [phoneId]'s own glass, at an
/// arbitrary point that is deliberately *not* where that phone's runner is —
/// ownership here is "your phone, your runner", never "whoever is nearest".
void tap(PhotoFinishSim sim, {required String phoneId, double x = 0, double y = 0}) {
  sim.onTouch(TouchEvent(phoneId: phoneId, worldX: x, worldY: y, phase: TouchPhase.down));
  sim.onTouch(TouchEvent(phoneId: phoneId, worldX: x, worldY: y, phase: TouchPhase.up));
}

void main() {
  group('the start of the race', () {
    test('every phone gets exactly one runner, on its own lane, at the line', () {
      final started = start(4);
      final sim = started.sim;
      final board = started.board;
      final startX = board.board.left + PhotoFinishConfig.startInset;

      expect(sim.entities, hasLength(4));
      final lanes = <double>{};
      for (final e in sim.entities) {
        expect(e.x, closeTo(startX, 1e-9));
        expect(board.board.top <= e.y && e.y <= board.board.bottom, isTrue);
        lanes.add(e.y);
      }
      // Four distinct lanes, nobody stacked on anybody else.
      expect(lanes, hasLength(4));
    });
  });

  group('tapping your own screen', () {
    test('boosts only that phone\'s runner, wherever the tap lands', () {
      final started = start(3);
      final sim = started.sim;

      // Tap p2 nowhere near its own runner — position-blindness is the point.
      tap(sim, phoneId: 'p2', x: 999, y: 999);
      sim.step(1 / PlatformConfig.simHz);

      final byId = {for (final e in sim.entities) e.id: e};
      final startX = started.board.board.left + PhotoFinishConfig.startInset;
      expect(byId['runner_p2']!.x, greaterThan(startX));
      expect(byId['runner_p1']!.x, closeTo(startX, 1e-9));
      expect(byId['runner_p3']!.x, closeTo(startX, 1e-9));
    });

    test('a move or a lift is not a tap', () {
      final started = start(2);
      final sim = started.sim;
      sim.onTouch(TouchEvent(phoneId: 'p1', worldX: 0, worldY: 0, phase: TouchPhase.move));
      sim.onTouch(TouchEvent(phoneId: 'p1', worldX: 0, worldY: 0, phase: TouchPhase.up));
      sim.step(1 / PlatformConfig.simHz);

      final startX = started.board.board.left + PhotoFinishConfig.startInset;
      final runner = sim.entities.firstWhere((e) => e.id == 'runner_p1');
      expect(runner.x, closeTo(startX, 1e-9));
    });

    test('friction bleeds an unspent boost off, so a runner coasts to a stop', () {
      final started = start(2);
      final sim = started.sim;
      tap(sim, phoneId: 'p1');

      for (var i = 0; i < PlatformConfig.simHz * 3; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      final settled = sim.entities.firstWhere((e) => e.id == 'runner_p1').x;

      for (var i = 0; i < PlatformConfig.simHz; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      final later = sim.entities.firstWhere((e) => e.id == 'runner_p1').x;

      // A single tap's boost decays well within three seconds at this
      // friction, so a further second of untapped stepping moves it no
      // further.
      expect(later, closeTo(settled, 1e-6));
    });
  });

  group('crossing the seam', () {
    test('a runner sweeps continuously from one phone\'s bounds into the next\'s', () {
      final started = start(3);
      final sim = started.sim;
      final board = started.board;
      final p1 = board.forPhone('p1')!;
      final p2 = board.forPhone('p2')!;
      final context = board.contextFor(started.scores);

      // Confirm the board actually has a seam to cross before asserting
      // anything crossed it.
      expect(p1.viewport.right, lessThanOrEqualTo(p2.viewport.left));

      double xOf() => sim.entities.firstWhere((e) => e.id == 'runner_p1').x;

      // Keep tapping until the runner has left p1's screen.
      var guard = 0;
      while (xOf() < p1.viewport.right && guard < 10000) {
        tap(sim, phoneId: 'p1');
        sim.step(1 / PlatformConfig.simHz);
        guard++;
      }
      expect(guard, lessThan(10000), reason: 'never left p1\'s screen');
      final justLeft = xOf();
      expect(context.phoneAt(justLeft, p1.worldCenterY), isNot('p1'));

      // The step that carried it past the edge did not teleport it: it moved
      // at most one tick's worth of the fastest a runner can ever go.
      final maxStepDistance =
          PhotoFinishConfig.maxSpeed / PlatformConfig.simHz + 1e-6;
      // justLeft is already past the boundary; the position just before this
      // loop's last step was within maxStepDistance of it by construction of
      // the per-tick integration, so the gap itself was crossed in one step,
      // not skipped over in a jump larger than physics allows.
      expect(justLeft - p1.viewport.right, lessThan(maxStepDistance));

      // Keep going: it lands on p2's screen for real, not just past p1's.
      while (xOf() < p2.viewport.left && guard < 20000) {
        tap(sim, phoneId: 'p1');
        sim.step(1 / PlatformConfig.simHz);
        guard++;
      }
      final onP2 = xOf();
      expect(context.phoneAt(onP2, p1.worldCenterY), 'p2');
      expect(onP2, greaterThan(p1.viewport.right));
    });
  });

  group('finishing the race', () {
    test('first across the line wins the contest and banks the bonus, once', () {
      final started = start(3);
      final sim = started.sim;
      final scores = started.scores;

      // p1 sprints hard; nobody else taps at all.
      for (var i = 0; i < PlatformConfig.simHz * 60; i++) {
        tap(sim, phoneId: 'p1');
        sim.step(1 / PlatformConfig.simHz);
        if (sim.outcome != null) break;
      }

      final outcome = sim.outcome;
      expect(outcome, isNotNull);
      expect(outcome!.kind, OutcomeKind.contest);
      expect(outcome.winners, {'p1'});
      expect(scores['p1'], PhotoFinishConfig.winBonus);
      expect(scores['p2'], 0);
      expect(scores['p3'], 0);

      // Polled repeatedly, as the platform does — always the same verdict,
      // and the bonus is not paid out again.
      expect(identical(sim.outcome, outcome), isTrue);
      sim.step(1 / PlatformConfig.simHz);
      expect(scores['p1'], PhotoFinishConfig.winBonus);
    });

    test('nobody sprinting for long enough ends the round in a draw', () {
      final started = start(2);
      final sim = started.sim;

      // One tick past the backstop, so summing 1/60 repeatedly cannot leave
      // the elapsed total a hair short of the threshold by float error.
      final ticks = (PlatformConfig.simHz * PhotoFinishConfig.backstopSeconds).round() + 1;
      for (var i = 0; i < ticks; i++) {
        sim.step(1 / PlatformConfig.simHz);
      }
      final outcome = sim.outcome;
      expect(outcome, isNotNull);
      expect(outcome!.kind, OutcomeKind.draw);
      expect(started.scores.isUsed, isFalse);
    });

    test('reset puts every runner back on the line with the verdict cleared', () {
      final started = start(2);
      final sim = started.sim;
      for (var i = 0; i < PlatformConfig.simHz * 60; i++) {
        tap(sim, phoneId: 'p1');
        sim.step(1 / PlatformConfig.simHz);
        if (sim.outcome != null) break;
      }
      expect(sim.outcome, isNotNull);

      sim.reset();
      expect(sim.outcome, isNull);
      final startX = started.board.board.left + PhotoFinishConfig.startInset;
      for (final e in sim.entities) {
        expect(e.x, closeTo(startX, 1e-9));
      }
    });
  });
}
