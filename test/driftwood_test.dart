import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/driftwood/driftwood_config.dart';
import 'package:multiscreen_slingshot/games/driftwood/driftwood_game.dart';
import 'package:multiscreen_slingshot/games/driftwood/driftwood_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A log with nothing to integrate but "constant forward speed plus whatever
/// the taps have added vertically" — no physics engine, driven headlessly the
/// way `hot_potato_test.dart` drives a sim with no host, no sockets and no
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

({DriftwoodSim sim, BoardLayout board, Scoreboard scores}) start(
  int count, {
  int? hazardCount,
}) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = DriftwoodGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = DriftwoodSim(board.contextFor(scores), hazardCount: hazardCount);
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

const _dt = 1 / PlatformConfig.simHz;

void main() {
  group('the table', () {
    test('is 2 to 8 phones, any count — a co-operative crew, not teams', () {
      const game = DriftwoodGame();
      expect(game.manifest.fits(1), isFalse);
      expect(game.manifest.fits(2), isTrue);
      expect(game.manifest.fits(3), isTrue);
      expect(game.manifest.fits(8), isTrue);
      expect(game.manifest.fits(9), isFalse);
    });

    test('planBoard lays a row, and the compiler accepts it up to 8 phones', () {
      for (final count in [2, 3, 5, 8]) {
        final started = start(count);
        expect(started.board.phones, hasLength(count));
      }
    });
  });

  group('the opening position', () {
    test('the log starts near the left edge, mid-lane, at rest', () {
      final started = start(3);
      final board = started.board.board;
      final log = started.sim.entities.firstWhere((e) => e.kind == 'log');

      expect(log.x, closeTo(board.left + board.width * DriftwoodConfig.startMarginFraction, 1e-9));
      expect(log.y, closeTo(board.centerY, 1e-9));
    });

    test('reset puts it back there and clears the verdict', () {
      final started = start(3);
      final sim = started.sim;
      for (var i = 0; i < PlatformConfig.simHz * 5; i++) {
        sim.step(_dt);
      }
      sim.reset();

      expect(sim.outcome, isNull);
      final log = sim.entities.firstWhere((e) => e.kind == 'log');
      final board = started.board.board;
      expect(log.x, closeTo(board.left + board.width * DriftwoodConfig.startMarginFraction, 1e-9));
      expect(log.y, closeTo(board.centerY, 1e-9));
      expect(sim.sharedState['crashed'], isFalse);
      expect(sim.sharedState['won'], isFalse);
    });
  });

  group('the rocks', () {
    test('sit between the configured fractions, zigzagging across the centreline', () {
      final started = start(3);
      final board = started.board.board;
      final rocks = started.sim.entities.where((e) => e.kind == 'rock').toList()
        ..sort((a, b) => a.x.compareTo(b.x));

      expect(rocks, hasLength(DriftwoodConfig.hazardCount));
      final startX = board.left + board.width * DriftwoodConfig.hazardStartFraction;
      final endX = board.left + board.width * DriftwoodConfig.hazardEndFraction;
      for (final r in rocks) {
        expect(r.x, greaterThanOrEqualTo(startX - 1e-6));
        expect(r.x, lessThanOrEqualTo(endX + 1e-6));
      }
      for (var i = 0; i < rocks.length; i++) {
        final side = (rocks[i].y - board.centerY).sign;
        expect(side, i.isEven ? 1.0 : -1.0);
      }
    });

    test('hazardCount:0 leaves an open lane, for isolating steering in a test', () {
      final started = start(3, hazardCount: 0);
      expect(started.sim.entities.where((e) => e.kind == 'rock'), isEmpty);
    });
  });

  group('steering', () {
    test('a tap too far from the log does nothing', () {
      final started = start(3, hazardCount: 0);
      final sim = started.sim;
      final before = sim.entities.firstWhere((e) => e.kind == 'log');

      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: before.x + DriftwoodConfig.reachWorld * 3,
        worldY: before.y + DriftwoodConfig.reachWorld * 3,
        phase: TouchPhase.down,
      ));
      sim.step(_dt);

      final after = sim.entities.firstWhere((e) => e.kind == 'log');
      expect(after.y, closeTo(before.y, 1e-9));
    });

    test('a lifted finger does not steer — only a down touch does', () {
      final started = start(3, hazardCount: 0);
      final sim = started.sim;
      final before = sim.entities.firstWhere((e) => e.kind == 'log');

      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: before.x,
        worldY: before.y + 2,
        phase: TouchPhase.up,
      ));
      sim.step(_dt);

      final after = sim.entities.firstWhere((e) => e.kind == 'log');
      expect(after.y, closeTo(before.y, 1e-9));
    });

    test('a tap near the log steers it toward wherever the tap landed', () {
      final started = start(3, hazardCount: 0);
      final sim = started.sim;
      final before = sim.entities.firstWhere((e) => e.kind == 'log');

      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: before.x,
        worldY: before.y + 2, // below the log, on its own screen
        phase: TouchPhase.down,
      ));
      for (var i = 0; i < 10; i++) {
        sim.step(_dt);
      }

      final after = sim.entities.firstWhere((e) => e.kind == 'log');
      expect(after.y, greaterThan(before.y));
    });
  });

  group('running aground', () {
    test('with nobody steering, the log drifts straight into the first rock', () {
      final started = start(3);
      final sim = started.sim;

      var ticks = 0;
      while (sim.outcome == null && ticks < PlatformConfig.simHz * 60) {
        sim.step(_dt);
        ticks++;
      }

      final outcome = sim.outcome;
      expect(outcome, isNotNull, reason: 'never reached a verdict');
      expect(outcome!.kind, OutcomeKind.shared);
      expect(outcome.won, isFalse);
      expect(outcome.summary, contains('aground'));
      expect(started.scores.isUsed, isFalse, reason: 'a crash pays nobody');
      // Latched — polled repeatedly, as the platform does.
      expect(identical(sim.outcome, outcome), isTrue);
    });

    test('once crashed, further steps and touches change nothing', () {
      final started = start(3);
      final sim = started.sim;
      var ticks = 0;
      while (sim.outcome == null && ticks < PlatformConfig.simHz * 60) {
        sim.step(_dt);
        ticks++;
      }
      final crashedAt = sim.entities.firstWhere((e) => e.kind == 'log');

      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: crashedAt.x,
        worldY: crashedAt.y - 3,
        phase: TouchPhase.down,
      ));
      for (var i = 0; i < 30; i++) {
        sim.step(_dt);
      }

      final after = sim.entities.firstWhere((e) => e.kind == 'log');
      expect(after.x, closeTo(crashedAt.x, 1e-9));
      expect(after.y, closeTo(crashedAt.y, 1e-9));
    });
  });

  group('reaching the far bank', () {
    test('steering clear of the one rock in its way wins the round for everyone', () {
      final started = start(3, hazardCount: 1);
      final sim = started.sim;
      final board = started.board.board;
      final rock = sim.entities.firstWhere((e) => e.kind == 'rock');
      // Steer to the side of the lane the rock is not on.
      final away = (rock.y - board.centerY) >= 0 ? -1.0 : 1.0;

      var ticks = 0;
      while (sim.outcome == null && ticks < PlatformConfig.simHz * 60) {
        final log = sim.entities.firstWhere((e) => e.kind == 'log');
        sim.onTouch(TouchEvent(
          phoneId: 'p1',
          worldX: log.x,
          worldY: log.y + away,
          phase: TouchPhase.down,
        ));
        sim.step(_dt);
        ticks++;
      }

      final outcome = sim.outcome;
      expect(outcome, isNotNull, reason: 'never reached a verdict');
      expect(outcome!.won, isTrue);
      expect(outcome.summary, contains('far bank'));
      for (final p in started.board.phones) {
        expect(started.scores[p.phoneId], DriftwoodConfig.winBonus);
      }
    });

    test('the bonus is paid once, even stepping well past the win', () {
      final started = start(2, hazardCount: 0); // open lane, nothing to dodge
      final sim = started.sim;

      var ticks = 0;
      while (sim.outcome == null && ticks < PlatformConfig.simHz * 60) {
        sim.step(_dt);
        ticks++;
      }
      expect(sim.outcome, isNotNull);
      final phoneId = started.board.phones.first.phoneId;
      final paidOnce = started.scores[phoneId];

      for (var i = 0; i < PlatformConfig.simHz * 5; i++) {
        sim.step(_dt);
      }
      expect(started.scores[phoneId], paidOnce);
    });
  });

  group('the seam', () {
    test(
      'the log sweeps continuously across the boundary between two phones, '
      'never jumping — the whole point of the platform',
      () {
        final started = start(2); // seam at 50% of the board's width.
        final sim = started.sim;

        final byX = List.of(started.board.slices)
          ..sort((a, b) => a.screen.centerX.compareTo(b.screen.centerX));
        final firstBounds = byX[0].screen.bounds;
        final secondBounds = byX[1].screen.bounds;

        // The real gap between two casings — a few bezel-widths of table the
        // log has to cross with nothing under it. Physics runs there too (see
        // README: "the world is continuous... including the dead millimetres
        // between two phones"), so the log must sweep through it, not skip it.
        expect(secondBounds.left, greaterThan(firstBounds.right));

        // Hazards start at 60% of the board — this stretch is guaranteed clear,
        // by construction (see DriftwoodConfig.hazardStartFraction).
        expect(
          secondBounds.left,
          lessThan(started.board.board.left +
              started.board.board.width * DriftwoodConfig.hazardStartFraction),
        );

        double? lastX;
        var sawFirstSlice = false;
        var sawGap = false;
        var landedOnSecond = false;
        var ticks = 0;
        while (!landedOnSecond && ticks < PlatformConfig.simHz * 30) {
          sim.step(_dt);
          final log = sim.entities.firstWhere((e) => e.kind == 'log');

          if (lastX != null) {
            // Continuous motion: no tick ever moves it further than the
            // current can carry it in that tick, on either side of the seam.
            final delta = log.x - lastX;
            expect(delta, lessThan(DriftwoodConfig.currentSpeed * _dt * 1.5));
            expect(delta, greaterThan(0));
          }
          lastX = log.x;

          if (firstBounds.contains(log.x, log.y)) sawFirstSlice = true;
          if (log.x > firstBounds.right && log.x < secondBounds.left) {
            sawGap = true;
          }
          if (secondBounds.contains(log.x, log.y)) landedOnSecond = true;
          ticks++;
        }

        expect(sawFirstSlice, isTrue, reason: 'never observed on the first phone');
        expect(sawGap, isTrue, reason: 'skipped over the real gap between the casings');
        expect(landedOnSecond, isTrue,
            reason: 'never landed on the second phone within the time budget');
        // Nothing crashed on the way — this stretch has no rocks in it.
        expect(sim.outcome, isNull);
      },
    );
  });
}
