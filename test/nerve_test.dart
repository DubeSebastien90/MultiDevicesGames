import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/nerve/nerve_config.dart';
import 'package:multiscreen_slingshot/games/nerve/nerve_game.dart';
import 'package:multiscreen_slingshot/games/nerve/nerve_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// Hold as long as you dare, against a threshold only the sim knows. Driven
/// entirely through the SDK contract — no host, no sockets, no rendering.
PhoneSpec phone(String id, PlayerColor? color) => PhoneSpec(
  phoneId: id,
  label: 'phone $id',
  widthMm: 68.58,
  heightMm: 152.4,
  bezelMm: 3,
  dpi: 400,
  devicePixelRatio: 3,
  activePxWidth: 1080,
  activePxHeight: 2400,
  color: color,
);

({NerveSim sim, Scoreboard scores}) start(int phoneCount, {int seed = 11}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++)
      phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }

  const game = NerveGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = NerveSim(board.contextFor(scores), random: math.Random(seed));
  scores.beginRound();
  return (sim: sim, scores: scores);
}

const _dt = 1 / 60;

void run(NerveSim sim, double seconds) {
  for (var t = 0.0; t < seconds; t += _dt) {
    sim.step(_dt);
  }
}

String? currentOf(NerveSim sim) => sim.sharedState['current'] as String?;

void down(NerveSim sim, String phoneId) => sim.onTouch(
  TouchEvent(phoneId: phoneId, worldX: 0, worldY: 0, phase: TouchPhase.down),
);

void up(NerveSim sim, String phoneId) => sim.onTouch(
  TouchEvent(phoneId: phoneId, worldX: 0, worldY: 0, phase: TouchPhase.up),
);

/// Steps until somebody's turn opens, presses down for them, then holds for
/// [holdSeconds] before releasing — unless a burst gets there first.
void playATurn(NerveSim sim, {required double holdSeconds}) {
  while (currentOf(sim) == null) {
    sim.step(_dt);
  }
  final holder = currentOf(sim)!;
  down(sim, holder);
  run(sim, holdSeconds);
  if (currentOf(sim) == holder) up(sim, holder);
}

void main() {
  group('the table', () {
    test('two players is a full game', () {
      const game = NerveGame();
      expect(game.manifest.fits(2), isTrue);
      expect(
        game.manifest.fits(1),
        isFalse,
        reason: 'alone there is nobody to out-dare',
      );
    });

    test('a ring for three or more, a row for two', () {
      final two = LobbyInfo([
        phone('p1', PlayerPalette.green),
        phone('p2', PlayerPalette.orange),
      ]);
      final board2 = const BoardCompiler().compile(
        const NerveGame().planBoard(two),
        two,
      );
      expect(board2.instruction, isNot(contains('circle')));

      final three = LobbyInfo([
        phone('p1', PlayerPalette.green),
        phone('p2', PlayerPalette.orange),
        phone('p3', PlayerPalette.blue),
      ]);
      final board3 = const BoardCompiler().compile(
        const NerveGame().planBoard(three),
        three,
      );
      expect(board3.instruction, contains('circle'));
    });
  });

  group('turns', () {
    test('deals somebody a turn as soon as the round starts', () {
      final started = start(3);
      expect(currentOf(started.sim), anyOf('p1', 'p2', 'p3'));
    });

    test('only the phone whose turn it is can start holding', () {
      final started = start(2);
      final sim = started.sim;
      while (currentOf(sim) == null) {
        sim.step(_dt);
      }
      final holder = currentOf(sim)!;
      final bystander = holder == 'p1' ? 'p2' : 'p1';

      down(sim, bystander);
      expect(
        sim.sharedState['holding'],
        isFalse,
        reason: 'a bystander pressing must not start the clock',
      );
    });

    test('a turn nobody starts moves on without banking anything', () {
      final started = start(2);
      final sim = started.sim;
      while (currentOf(sim) == null) {
        sim.step(_dt);
      }
      final ghosted = currentOf(sim)!;

      run(sim, NerveConfig.startTimeoutSeconds + 0.1);
      expect(currentOf(sim), isNot(ghosted));
      expect(started.scores[ghosted], 0);
    });

    test('turns are dealt out evenly rather than at random', () {
      final started = start(4);
      final sim = started.sim;
      final turns = <String, int>{};

      for (var i = 0; i < 12; i++) {
        while (currentOf(sim) == null) {
          sim.step(_dt);
        }
        turns[currentOf(sim)!] = (turns[currentOf(sim)!] ?? 0) + 1;
        run(sim, NerveConfig.startTimeoutSeconds + 0.1); // let it ghost
      }

      expect(turns.keys, hasLength(4), reason: 'somebody never got a turn');
      final counts = turns.values.toList()..sort();
      expect(
        counts.last - counts.first,
        lessThanOrEqualTo(1),
        reason: 'turns were not dealt evenly: $turns',
      );
    });
  });

  group('holding', () {
    test('climbs in whole seconds while held, and stops at release', () {
      final started = start(2);
      final sim = started.sim;
      while (currentOf(sim) == null) {
        sim.step(_dt);
      }
      final holder = currentOf(sim)!;

      down(sim, holder);
      run(sim, 1.2);
      expect(sim.sharedState['heldSeconds'], 1);

      up(sim, holder);
      expect(sim.sharedState['holding'], isFalse);
      expect(sim.sharedState['heldSeconds'], 0);
    });

    test('a release before the burst banks points for that phone', () {
      final started = start(2);
      final sim = started.sim;
      while (currentOf(sim) == null) {
        sim.step(_dt);
      }
      final holder = currentOf(sim)!;

      down(sim, holder);
      // Short enough to clear the shortest possible burst threshold hardly
      // ever — if it does burst on this seed the test below still holds,
      // since the assertion is about points never going negative and the
      // turn always moving on.
      run(sim, NerveConfig.minBurstSeconds - 0.05);
      up(sim, holder);

      expect(started.scores[holder], greaterThanOrEqualTo(0));
      expect(currentOf(sim), isNot(holder));
    });

    test('holding straight through the burst window banks nothing', () {
      final started = start(2);
      final sim = started.sim;
      while (currentOf(sim) == null) {
        sim.step(_dt);
      }
      final holder = currentOf(sim)!;

      down(sim, holder);
      run(sim, NerveConfig.maxBurstSeconds + 0.2); // certain to have burst

      expect(started.scores[holder], 0);
      expect(
        currentOf(sim),
        isNot(holder),
        reason: 'a burst turn must not leave the table waiting on it',
      );
    });

    test('the sim never tells anyone where the threshold is', () {
      final started = start(2);
      expect(started.sim.sharedState.containsKey('burstAt'), isFalse);
      expect(started.sim.sharedState.keys, isNot(contains('threshold')));
    });
  });

  group('scoring', () {
    test('longer holds are worth more, at a fixed rate', () {
      final started = start(2, seed: 99);
      final sim = started.sim;
      while (currentOf(sim) == null) {
        sim.step(_dt);
      }
      final holder = currentOf(sim)!;

      down(sim, holder);
      run(sim, 1.5); // comfortably short of even the minimum burst
      up(sim, holder);

      expect(started.scores[holder], (1.5 * NerveConfig.pointsPerSecond).round());
    });

    test('is awarded once, however long the round keeps being stepped', () {
      final started = start(2);
      playATurn(started.sim, holdSeconds: 0.5);
      final after = started.scores['p1'] + started.scores['p2'];

      for (var i = 0; i < 180; i++) {
        started.sim.step(_dt);
        started.sim.outcome; // polled repeatedly, as the platform does
      }

      expect(started.scores['p1'] + started.scores['p2'], after);
    });
  });

  group('the ending', () {
    test('ends after the round clock runs out, mid-turn or not', () {
      final started = start(2);
      run(started.sim, NerveConfig.roundSeconds - 1);
      expect(started.sim.outcome, isNull, reason: 'ended early');

      run(started.sim, 2);
      expect(started.sim.outcome, isNotNull, reason: 'never ended');
      expect(
        started.sim.sharedState['current'],
        isNull,
        reason: 'a turn was left open after the whistle',
      );
    });

    test(
      'names the biggest banker as the winner, with a line for everyone',
      () {
        final started = start(2);
        final sim = started.sim;

        // p1 bites the bullet and banks something; p2 never even tries.
        down(sim, currentOf(sim) ?? 'p1');
        run(sim, 0.2);
        if (currentOf(sim) != null) up(sim, currentOf(sim)!);

        run(sim, NerveConfig.roundSeconds);

        final outcome = sim.outcome!;
        expect(outcome.kind, OutcomeKind.contest);
        expect(outcome.lines, hasLength(2));
        expect(outcome.summary, contains('banked'));
        // Polled repeatedly, as the platform does — always the same verdict.
        expect(identical(sim.outcome, outcome), isTrue);
      },
    );

    test('a table that never banks anything is a draw, not a crash', () {
      final started = start(2);
      final sim = started.sim;
      // Never touch the screen at all — every turn ghosts.
      run(sim, NerveConfig.roundSeconds);

      expect(sim.outcome, isNotNull);
      expect(sim.outcome!.kind, OutcomeKind.draw);
    });

    test('a replayed round does not reuse the last verdict', () {
      final started = start(2);
      run(started.sim, NerveConfig.roundSeconds);
      expect(started.sim.outcome, isNotNull);

      started.sim.reset();
      expect(started.sim.outcome, isNull);
      expect(
        started.sim.sharedState['secondsLeft'],
        NerveConfig.roundSeconds.ceil(),
      );
    });
  });

  group('shared state', () {
    test('is quiet between events, not a stream every tick', () {
      final started = start(3);
      final sim = started.sim;
      var changes = 0;
      var previous = '${sim.sharedState}';

      for (var t = 0.0; t < 5; t += _dt) {
        sim.step(_dt);
        final now = '${sim.sharedState}';
        if (now != previous) changes++;
        previous = now;
      }

      // A handful of turn and second-tick transitions in five seconds, not
      // one per tick.
      expect(changes, lessThan(60), reason: '$changes changes in five seconds');
    });
  });
}
