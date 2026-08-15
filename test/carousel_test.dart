import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/carousel/carousel_config.dart';
import 'package:multiscreen_slingshot/games/carousel/carousel_game.dart';
import 'package:multiscreen_slingshot/games/carousel/carousel_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A game with no physics engine and no randomness: one angle, one angular
/// speed, decelerating at a constant rate, so every test outcome here is
/// reproducible from the taps that produced it.
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

({CarouselSim sim, BoardLayout board, Scoreboard scores}) start(int count) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = CarouselGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = CarouselSim(board.contextFor(scores));
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

void tapOnce(CarouselSim sim, String phoneId) {
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: 0,
    worldY: 0,
    phase: TouchPhase.down,
  ));
}

void stepSeconds(CarouselSim sim, double seconds) {
  final ticks = (seconds * PlatformConfig.simHz).round();
  for (var i = 0; i < ticks; i++) {
    sim.step(1 / PlatformConfig.simHz);
  }
}

/// Steps until a landing is recorded, or gives up after a generous ceiling —
/// the marker always eventually stops on its own, so a stall means a bug.
int stepsToLand(CarouselSim sim) {
  const ceiling = PlatformConfig.simHz * 10;
  var steps = 0;
  while (_landingCount(sim) == 0 && steps < ceiling) {
    sim.step(1 / PlatformConfig.simHz);
    steps++;
  }
  return steps;
}

int _landingCount(CarouselSim sim) {
  final landings = sim.sharedState['landings'] as Map;
  return landings.values.fold<int>(0, (a, b) => a + (b as int));
}

void main() {
  group('the table', () {
    test('needs at least three phones', () {
      expect(const CarouselGame().manifest.smallestTable, 3);
      expect(const CarouselGame().manifest.fits(2), isFalse);
      expect(const CarouselGame().manifest.fits(3), isTrue);
    });
  });

  group('starting a round', () {
    test('is idle, with nobody having landed yet', () {
      final started = start(4);
      final sim = started.sim;

      expect(sim.sharedState['moving'], isFalse);
      expect(sim.sharedState['settling'], isFalse);
      expect((sim.sharedState['landings'] as Map), isEmpty);
      expect(sim.sharedState['secondsLeft'], CarouselConfig.roundSeconds.ceil());
      expect(sim.outcome, isNull);

      // The marker starts somewhere on the ring, owned by a real seat.
      final owner = sim.sharedState['owner'];
      expect(started.board.slices.map((s) => s.phoneId), contains(owner));
    });
  });

  group('tapping', () {
    test('a touch-down starts it spinning', () {
      final started = start(4);
      final sim = started.sim;
      final phoneId = started.board.slices.first.phoneId;

      tapOnce(sim, phoneId);
      expect(sim.sharedState['moving'], isTrue);
    });

    test('a touch-up does nothing — only a down counts as a tap', () {
      final started = start(4);
      final sim = started.sim;
      final phoneId = started.board.slices.first.phoneId;

      sim.onTouch(TouchEvent(
        phoneId: phoneId,
        worldX: 0,
        worldY: 0,
        phase: TouchPhase.up,
      ));
      expect(sim.sharedState['moving'], isFalse);
    });

    test('two taps from the same phone with no time between count once', () {
      final withOne = start(4);
      final withTwo = start(4);
      final phoneId = withOne.board.slices.first.phoneId;

      tapOnce(withOne.sim, phoneId);

      // Both calls land in the same instant — no step() runs between them —
      // so the second is inside the rate-limit window and should be dropped.
      tapOnce(withTwo.sim, phoneId);
      tapOnce(withTwo.sim, phoneId);

      final stepsOne = stepsToLand(withOne.sim);
      final stepsTwo = stepsToLand(withTwo.sim);
      expect(stepsTwo, stepsOne,
          reason: 'a second immediate tap should not have added more spin');
    });

    test('a second tap after the cooldown adds real spin on top', () {
      final started = start(4);
      final sim = started.sim;
      final phoneId = started.board.slices.first.phoneId;

      tapOnce(sim, phoneId);
      stepSeconds(sim, CarouselConfig.tapCooldown * 2);
      tapOnce(sim, phoneId);

      final withOne = start(4);
      tapOnce(withOne.sim, withOne.board.slices.first.phoneId);

      final stepsTwoTaps = stepsToLand(sim);
      final stepsOneTap = stepsToLand(withOne.sim);
      expect(stepsTwoTaps, greaterThan(stepsOneTap),
          reason: 'more accumulated spin should take longer to die down');
    });

    test('however many times you tap, the marker never spins past the cap', () {
      final capped = start(4);
      final overCapped = start(4);
      final phoneA = capped.board.slices.first.phoneId;
      final phoneB = overCapped.board.slices.first.phoneId;

      // Each gap between taps is just past the rate limit, so every tap
      // registers and bleeds off a little speed before the next one lands.
      // That settles into a steady speed after a handful of taps — eight is
      // already past that point, so eight and twenty must land the same way.
      final gap = CarouselConfig.tapCooldown + 0.01;
      for (var i = 0; i < 8; i++) {
        tapOnce(capped.sim, phoneA);
        stepSeconds(capped.sim, gap);
      }
      for (var i = 0; i < 20; i++) {
        tapOnce(overCapped.sim, phoneB);
        stepSeconds(overCapped.sim, gap);
      }

      final stepsCapped = stepsToLand(capped.sim);
      final stepsOverCapped = stepsToLand(overCapped.sim);
      expect(
        stepsOverCapped,
        closeTo(stepsCapped, PlatformConfig.simHz * 0.15),
        reason: 'both should have converged to the same capped speed',
      );
    });

    test('taps are ignored while the round is over', () {
      final started = start(4);
      final sim = started.sim;
      final phoneId = started.board.slices.first.phoneId;

      // Nobody ever taps, so the round times out with the marker still idle.
      stepSeconds(sim, CarouselConfig.roundSeconds + 1);
      expect(sim.outcome, isNotNull);

      tapOnce(sim, phoneId);
      expect(sim.sharedState['moving'], isFalse);
    });
  });

  group('landing', () {
    test('scores the phone whose zone it stopped in, exactly once', () {
      final started = start(4);
      final sim = started.sim;
      final phoneId = started.board.slices.first.phoneId;

      tapOnce(sim, phoneId);
      final steps = stepsToLand(sim);
      expect(steps, lessThan(PlatformConfig.simHz * 10),
          reason: 'the marker must eventually settle on its own');

      final landings = (sim.sharedState['landings'] as Map).cast<String, int>();
      expect(landings.values.fold<int>(0, (a, b) => a + b), 1);

      final winner = landings.keys.single;
      expect(started.scores[winner], CarouselConfig.pointsPerLanding);

      // Nobody else was paid.
      for (final id in started.board.slices.map((s) => s.phoneId)) {
        if (id != winner) expect(started.scores[id], 0);
      }
    });

    test('holds taps off for a moment after settling', () {
      final started = start(4);
      final sim = started.sim;
      final phoneId = started.board.slices.first.phoneId;

      tapOnce(sim, phoneId);
      stepsToLand(sim);
      expect(sim.sharedState['settling'], isTrue);

      tapOnce(sim, phoneId);
      expect(sim.sharedState['moving'], isFalse,
          reason: 'a tap during the settle window should be ignored');

      stepSeconds(sim, CarouselConfig.settleSeconds + 0.1);
      expect(sim.sharedState['settling'], isFalse);

      tapOnce(sim, phoneId);
      expect(sim.sharedState['moving'], isTrue,
          reason: 'once settling is over, taps work again');
    });
  });

  group('ending the round', () {
    test('nobody tapping runs out the clock in a draw', () {
      final started = start(4);
      final sim = started.sim;

      stepSeconds(sim, CarouselConfig.roundSeconds + 1);
      final outcome = sim.outcome;

      expect(outcome, isNotNull);
      expect(outcome!.kind, OutcomeKind.draw);
      // Polled repeatedly, as the platform does — always the same verdict.
      expect(identical(sim.outcome, outcome), isTrue);
    });

    test(
      'landings end the round early once someone reaches the target, or the '
      'clock ends it as a contest matching the standings either way',
      () {
        final started = start(4);
        final sim = started.sim;
        final phoneId = started.board.slices.first.phoneId;

        var guard = 0;
        final ceiling = PlatformConfig.simHz * (CarouselConfig.roundSeconds + 2);
        while (sim.outcome == null && guard < ceiling) {
          if (sim.sharedState['moving'] != true &&
              sim.sharedState['settling'] != true) {
            tapOnce(sim, phoneId);
          }
          sim.step(1 / PlatformConfig.simHz);
          guard++;
        }

        final outcome = sim.outcome;
        expect(outcome, isNotNull);
        expect(outcome!.kind, OutcomeKind.contest);

        final landings =
            (sim.sharedState['landings'] as Map).cast<String, int>();
        final total = landings.values.fold<int>(0, (a, b) => a + b);
        expect(total, greaterThan(0));

        final top = landings.values.reduce(math.max);
        final expectedWinners = {
          for (final e in landings.entries)
            if (e.value == top) e.key,
        };
        expect(outcome.winners, expectedWinners);

        // If the clock had not run out, the only other way the round can have
        // ended is that somebody actually reached the target.
        final secondsLeft = sim.sharedState['secondsLeft'] as int;
        if (secondsLeft > 0) {
          expect(top, greaterThanOrEqualTo(CarouselConfig.targetLandings));
        }

        for (final entry in landings.entries) {
          expect(started.scores[entry.key],
              entry.value * CarouselConfig.pointsPerLanding);
        }
      },
    );
  });

  test('reset puts the marker back to its opening position', () {
    final started = start(4);
    final sim = started.sim;
    final phoneId = started.board.slices.first.phoneId;

    tapOnce(sim, phoneId);
    stepsToLand(sim);
    expect((sim.sharedState['landings'] as Map), isNotEmpty);

    sim.reset();

    expect(sim.outcome, isNull);
    expect(sim.sharedState['moving'], isFalse);
    expect(sim.sharedState['settling'], isFalse);
    expect((sim.sharedState['landings'] as Map), isEmpty);
    expect(sim.sharedState['secondsLeft'], CarouselConfig.roundSeconds.ceil());
  });
}
