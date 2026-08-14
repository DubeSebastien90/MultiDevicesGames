import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/chronometer/chronometer_config.dart';
import 'package:multiscreen_slingshot/games/chronometer/chronometer_game.dart';
import 'package:multiscreen_slingshot/games/chronometer/chronometer_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A number, a blank screen, and a press. Driven entirely through the SDK
/// contract — no host, no sockets, no rendering.
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

({ChronometerSim sim, Scoreboard scores}) start(int phoneCount, {int seed = 3}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++)
      phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }

  const game = ChronometerGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = ChronometerSim(board.contextFor(scores), random: math.Random(seed));
  scores.beginRound();
  return (sim: sim, scores: scores);
}

const _dt = 1 / 60;

/// An angle folded into (-pi, pi], for comparing two bearings that may be a
/// whole turn apart and still be the same direction.
double _wrapPi(double a) {
  var x = a % (2 * math.pi);
  if (x > math.pi) x -= 2 * math.pi;
  if (x <= -math.pi) x += 2 * math.pi;
  return x;
}

void run(ChronometerSim sim, double seconds) {
  for (var t = 0.0; t < seconds; t += _dt) {
    sim.step(_dt);
  }
}

String phaseOf(ChronometerSim sim) => sim.sharedState['phase'] as String;

/// Step until the clock is actually running — past the reveal and the 3-2-1.
void runToStart(ChronometerSim sim) {
  while (phaseOf(sim) != ChronoPhase.running) {
    sim.step(_dt);
  }
}

/// Press [phoneId]'s screen. There is nothing to aim at, so the coordinates
/// are only there to satisfy the contract.
void press(ChronometerSim sim, String phoneId) {
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: 0,
    worldY: 0,
    phase: TouchPhase.down,
  ));
}

/// Run the clock to [at] seconds and press. Assumes the clock is running.
void pressAt(ChronometerSim sim, String phoneId, double at) {
  run(sim, at);
  press(sim, phoneId);
}

/// A snapshot that will not change under you.
///
/// `sharedState` hands back the sim's own list for the guesses, so holding the
/// map alone captures a *reference*: the next press mutates the thing you were
/// about to compare against, and a diff that should have fired looks quiet. The
/// host serialises before it compares, so it never sees that; a test that skips
/// the copy is testing an aliasing bug of its own making.
Map<String, Object?> snapshot(Map<String, Object?> state) => {
      for (final e in state.entries)
        e.key: e.value is List ? List<Object?>.from(e.value as List) : e.value,
    };

/// Exactly how the host decides whether shared state is worth sending: value
/// by value, with `==`.
bool sameShared(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final x = a[entry.key];
    final y = b[entry.key];
    if (x is List && y is List) {
      if (x.length != y.length) return false;
      for (var i = 0; i < x.length; i++) {
        if (x[i] != y[i]) return false;
      }
      continue;
    }
    if (x != y) return false;
  }
  return true;
}

void main() {
  group('the table', () {
    test('two players is a full game', () {
      const game = ChronometerGame();
      expect(game.manifest.fits(2), isTrue);
      expect(game.manifest.fits(1), isFalse,
          reason: 'alone there is nobody to be closer than');
      expect(game.manifest.fits(PlayerPalette.size), isTrue);
      expect(game.manifest.fits(PlayerPalette.size + 1), isFalse,
          reason: 'a guess is announced by its owner colour');
    });

    test('three or more make a star, every phone pointing at the middle', () {
      // Radial, not tangential: each phone's long axis runs along its own
      // radius, so three players make a three-armed star and each screen is
      // upright in its owner's hand rather than lying on its side like a tile.
      const game = ChronometerGame();
      for (var n = 3; n <= PlayerPalette.size; n++) {
        final lobby = LobbyInfo([
          for (var i = 0; i < n; i++) phone('p${i + 1}', PlayerPalette.all[i]),
        ]);
        final board =
            const BoardCompiler().compile(game.planBoard(lobby), lobby);

        // The middle of the *ring*, which is the mean of the phone centres —
        // not `board.centerX/Y`, which is the middle of the bounding box. The
        // two differ by a few millimetres because the turned footprints do not
        // tile the box symmetrically, and that gap is enough to make a
        // correctly aimed phone look several degrees out.
        var cx = 0.0;
        var cy = 0.0;
        for (final p in board.phones) {
          cx += p.worldCenterX;
          cy += p.worldCenterY;
        }
        cx /= board.phones.length;
        cy /= board.phones.length;

        for (final p in board.phones) {
          // The angle from the middle of the ring out to this phone, and the
          // way the phone itself is turned, have to be the same bearing. That
          // is what "pointing at the centre" means, and it is the difference
          // between a star and a wheel of tiles.
          final outward = math.atan2(p.worldCenterY - cy, p.worldCenterX - cx);
          // A radial phone's own 'up' points inward, so its turn is the
          // outward bearing plus a quarter.
          final expected = outward + math.pi / 2;
          final delta = _wrapPi(p.turnRadians - expected);
          expect(delta.abs(), lessThan(0.02),
              reason: '${p.phoneId} of $n is not aimed at the middle');
        }
      }
    });

    test('the turns are real, and the host is not the only upright one', () {
      // The bug this replaces was invisible on the host, which sorts first and
      // therefore sat at zero degrees. What is pinned is that the layout still
      // *asks* for turns — the fix belongs in the view, which counter-rotates
      // its own drawing, not in the layout, which is what the placement screen
      // draws and what people follow when they put phones on a table.
      const game = ChronometerGame();
      final lobby = LobbyInfo([
        for (var i = 0; i < 3; i++) phone('p${i + 1}', PlayerPalette.all[i]),
      ]);
      final turns = [
        for (final p in game.planBoard(lobby).placements) p.turnDeg,
      ];
      expect(turns.toSet(), hasLength(3),
          reason: 'a star turns each arm differently');
    });

    test('a ring puts every phone somewhere different', () {
      const game = ChronometerGame();
      final lobby = LobbyInfo([
        for (var i = 0; i < 5; i++) phone('p${i + 1}', PlayerPalette.all[i]),
      ]);
      final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);

      final centres = [
        for (final p in board.phones) (p.worldCenterX, p.worldCenterY),
      ];
      expect(centres.toSet(), hasLength(5));
    });

    test('three or more sit in a ring, two sit across from each other', () {
      const game = ChronometerGame();
      final pair = LobbyInfo([
        phone('p1', PlayerPalette.green),
        phone('p2', PlayerPalette.orange),
      ]);
      final table = LobbyInfo([
        for (var i = 0; i < 4; i++) phone('p${i + 1}', PlayerPalette.all[i]),
      ]);

      // Both compile to a real board — the point is that neither arrangement
      // is refused, not the exact millimetres.
      expect(
        const BoardCompiler().compile(game.planBoard(pair), pair).slices.length,
        2,
      );
      expect(
        const BoardCompiler()
            .compile(game.planBoard(table), table)
            .slices
            .length,
        4,
      );
    });
  });

  group('the target', () {
    test('is a whole number of seconds inside the advertised range', () {
      // Every seed, not one: the range is the promise the reveal screen makes.
      for (var seed = 0; seed < 40; seed++) {
        final sim = start(2, seed: seed).sim;
        final t = sim.targetSeconds;
        expect(t, greaterThanOrEqualTo(
            ChronometerConfig.minTargetSeconds.toDouble()));
        expect(t, lessThanOrEqualTo(
            ChronometerConfig.maxTargetSeconds.toDouble()));
        expect(t, t.roundToDouble(), reason: 'shown as a whole number');
      }
    });

    test('a fresh one each round, or the second round is a memory test', () {
      // Reset enough times that drawing the same number every time would show.
      final sim = start(2, seed: 11).sim;
      final seen = <double>{sim.targetSeconds};
      for (var i = 0; i < 30; i++) {
        sim.reset();
        seen.add(sim.targetSeconds);
      }
      expect(seen.length, greaterThan(1));
    });
  });

  group('the phases', () {
    test('reveal, then 3-2-1, then a blank screen', () {
      final sim = start(2).sim;
      expect(phaseOf(sim), ChronoPhase.reveal);

      run(sim, ChronometerConfig.revealSeconds + _dt);
      expect(phaseOf(sim), ChronoPhase.countdown);

      // The digits actually count down, and reach 1 before handing over.
      final seen = <int>{};
      while (phaseOf(sim) == ChronoPhase.countdown) {
        seen.add(sim.sharedState['countIn'] as int);
        sim.step(_dt);
      }
      expect(seen.containsAll({3, 2, 1}), isTrue);
      expect(phaseOf(sim), ChronoPhase.running);
    });

    test('the clock starts at zero when the countdown ends', () {
      final sim = start(2).sim;
      runToStart(sim);

      // A press on the very first tick of the running phase reads as ~0, not
      // as the reveal and countdown that came before it.
      press(sim, 'p1');
      expect(sim.guessOf('p1')!, lessThan(0.1));
    });

    test('presses before the clock starts are ignored', () {
      final sim = start(2).sim;

      press(sim, 'p1');
      run(sim, ChronometerConfig.revealSeconds + 0.5);
      press(sim, 'p1');

      expect(sim.guessOf('p1'), isNull,
          reason: 'you cannot guess before the game has started');

      // And the real press still lands.
      runToStart(sim);
      pressAt(sim, 'p1', 1.0);
      expect(sim.guessOf('p1'), isNotNull);
    });
  });

  group('guessing', () {
    test('a press is measured from the start of the clock', () {
      final sim = start(2).sim;
      runToStart(sim);

      pressAt(sim, 'p1', 4.0);
      expect(sim.guessOf('p1')!, closeTo(4.0, 0.05));
    });

    test('one guess each — a second press is not a correction', () {
      final sim = start(2).sim;
      runToStart(sim);

      pressAt(sim, 'p1', 2.0);
      final first = sim.guessOf('p1')!;
      pressAt(sim, 'p1', 1.0);

      expect(sim.guessOf('p1'), first,
          reason: 'hammering the glass must not be the winning strategy');
    });

    test('the error is the distance from the target, early or late', () {
      final sim = start(2).sim;
      final target = sim.targetSeconds;
      runToStart(sim);

      pressAt(sim, 'p1', target - 1.0);
      run(sim, 2.0);
      press(sim, 'p2');

      expect(sim.errorOf('p1'), closeTo(1.0, 0.05));
      expect(sim.errorOf('p2'), closeTo(1.0, 0.05),
          reason: 'a second late is exactly as wrong as a second early');
    });
  });

  group('ending the round', () {
    test('the last press ends the guessing immediately', () {
      final sim = start(3).sim;
      runToStart(sim);

      pressAt(sim, 'p1', 1.0);
      press(sim, 'p2');
      expect(phaseOf(sim), ChronoPhase.running,
          reason: 'p3 has not guessed yet');

      press(sim, 'p3');
      expect(phaseOf(sim), ChronoPhase.results);
    });

    test('the clock does not stop when the target elapses', () {
      // The whole point of the grace window: guessing a beat late is playing
      // the game, not missing it.
      final sim = start(2).sim;
      final target = sim.targetSeconds;
      runToStart(sim);

      run(sim, target + 1.0);
      expect(phaseOf(sim), ChronoPhase.running);

      press(sim, 'p1');
      expect(sim.guessOf('p1')!, greaterThan(target),
          reason: 'a late guess still registers');
    });

    test('the grace window is at least the advertised five seconds', () {
      final sim = start(2).sim;
      final target = sim.targetSeconds;
      runToStart(sim);

      run(sim, target + ChronometerConfig.graceSeconds - 0.2);
      expect(phaseOf(sim), ChronoPhase.running);
      expect(ChronometerConfig.graceSeconds, greaterThanOrEqualTo(5.0));

      run(sim, 0.4);
      expect(phaseOf(sim), ChronoPhase.results,
          reason: 'one player staring at the ceiling cannot stall the table');
    });

    test('somebody who never presses is scored at the grace window', () {
      final sim = start(2).sim;
      runToStart(sim);
      pressAt(sim, 'p1', sim.targetSeconds);

      run(sim, ChronometerConfig.graceSeconds + 1);
      expect(sim.guessOf('p2'), isNull);
      expect(sim.errorOf('p2'), ChronometerConfig.noGuessErrorSeconds);
    });

    test('the results outlast the winner flying to the middle', () {
      // The flight from the rim to the centre is what explains the result. If
      // the platform tears the screen down while the disc is still in the air,
      // it is worse than not animating at all.
      expect(
        ChronometerConfig.resultsSeconds * 1000,
        greaterThan(ChronometerConfig.winnerFlightMs + 1000),
        reason: 'the winner has to land, and then be readable',
      );
    });

    test('the results stay up before the platform is told', () {
      final sim = start(2).sim;
      runToStart(sim);
      pressAt(sim, 'p1', 1.0);
      press(sim, 'p2');

      expect(phaseOf(sim), ChronoPhase.results);
      expect(sim.outcome, isNull,
          reason: 'the marks have to be readable before the screen changes');

      run(sim, ChronometerConfig.resultsSeconds + _dt);
      expect(sim.outcome, isNotNull);
    });
  });

  group('who won', () {
    test('the closest guess takes it', () {
      final started = start(3);
      final sim = started.sim;
      final target = sim.targetSeconds;
      runToStart(sim);

      pressAt(sim, 'p1', target - 2.0);
      press(sim, 'p2'); // same instant, also 2 s early
      run(sim, 1.8);
      press(sim, 'p3'); // 0.2 s early — closest

      run(sim, ChronometerConfig.resultsSeconds + 1);
      final outcome = sim.outcome!;
      expect(outcome.kind, OutcomeKind.contest);
      expect(outcome.winners, {'p3'});
    });

    test('everybody level is a draw, not a contest everyone wins', () {
      final sim = start(2).sim;
      runToStart(sim);

      pressAt(sim, 'p1', 2.0);
      press(sim, 'p2');

      run(sim, ChronometerConfig.resultsSeconds + 1);
      expect(sim.outcome!.kind, OutcomeKind.draw);
    });

    test('nobody pressing is a draw, and nobody scores', () {
      final started = start(2);
      final sim = started.sim;
      runToStart(sim);
      run(sim, sim.targetSeconds + ChronometerConfig.graceSeconds +
          ChronometerConfig.resultsSeconds + 1);

      expect(sim.outcome!.kind, OutcomeKind.draw);
      expect(started.scores.view['p1'], 0);
      expect(started.scores.view['p2'], 0);
    });

    test('every phone is told what it did', () {
      final sim = start(3).sim;
      final target = sim.targetSeconds;
      runToStart(sim);

      pressAt(sim, 'p1', target); // spot on
      run(sim, 1.0);
      press(sim, 'p2'); // a second late
      // p3 never presses, so the window has to run out on its own — and then
      // the results have to sit there long enough to be read.
      run(sim, ChronometerConfig.graceSeconds +
          ChronometerConfig.resultsSeconds + 1);

      final lines = sim.outcome!.lines!;
      expect(lines['p1'], contains('spot on'));
      expect(lines['p2'], contains('late'));
      expect(lines['p3'], 'You never pressed',
          reason: 'a phone that sat it out gets a line too');
    });

    test('an early guess is reported as early', () {
      final sim = start(2).sim;
      runToStart(sim);
      pressAt(sim, 'p1', sim.targetSeconds - 1.5);
      press(sim, 'p2');
      run(sim, ChronometerConfig.resultsSeconds + 1);

      expect(sim.outcome!.lines!['p1'], contains('early'));
    });
  });

  group('points', () {
    test('the closest scores the most, the furthest scores nothing', () {
      final started = start(3);
      final sim = started.sim;
      final target = sim.targetSeconds;
      runToStart(sim);

      pressAt(sim, 'p1', target - 2.5);
      run(sim, 1.5);
      press(sim, 'p2'); // 1 s early
      run(sim, 0.9);
      press(sim, 'p3'); // 0.1 s early — bullseye

      final view = started.scores.view;
      expect(view['p3'], greaterThan(view['p2']));
      expect(view['p2'], greaterThan(view['p1']));
      expect(view['p1'], 0, reason: 'the furthest guess is the bottom of the curve');
    });

    test('a bullseye is worth a bonus on top', () {
      final started = start(2);
      final sim = started.sim;
      final target = sim.targetSeconds;
      runToStart(sim);

      pressAt(sim, 'p1', target); // inside the bullseye
      run(sim, 2.0);
      press(sim, 'p2');

      expect(
        started.scores.view['p1'],
        ChronometerConfig.bestScore + ChronometerConfig.bullseyeBonus,
      );
    });

    test('a phone that never pressed scores nothing', () {
      final started = start(2);
      final sim = started.sim;
      runToStart(sim);
      pressAt(sim, 'p1', 2.0);
      run(sim, ChronometerConfig.graceSeconds + ChronometerConfig.maxTargetSeconds);

      expect(started.scores.view['p1'], greaterThan(0));
      expect(started.scores.view['p2'], 0);
    });

    test('points are awarded exactly once', () {
      final started = start(2);
      final sim = started.sim;
      runToStart(sim);
      pressAt(sim, 'p1', 2.0);
      press(sim, 'p2');

      final afterFirst = started.scores.view['p1'];
      // Poll the outcome repeatedly, which is what the platform does.
      run(sim, ChronometerConfig.resultsSeconds + 2);
      for (var i = 0; i < 20; i++) {
        sim.outcome;
        sim.step(_dt);
      }
      expect(started.scores.view['p1'], afterFirst);
    });

    test('tied guesses share the better position', () {
      final started = start(3);
      final sim = started.sim;
      final target = sim.targetSeconds;
      runToStart(sim);

      pressAt(sim, 'p1', target - 1.0);
      press(sim, 'p2'); // dead level with p1
      run(sim, 3.0);
      press(sim, 'p3');

      expect(started.scores.view['p1'], started.scores.view['p2'],
          reason: 'losing a tie-break you did not lose is worse than the tie');
      expect(started.scores.view['p1'], greaterThan(started.scores.view['p3']));
    });
  });

  group('the wire', () {
    test('the running clock never crosses it', () {
      // The one secret the game has. If the elapsed time were published, any
      // phone could render the answer.
      final sim = start(2).sim;
      runToStart(sim);
      run(sim, 2.0);

      for (final entry in sim.sharedState.entries) {
        final v = entry.value;
        if (v is! num) continue;
        // The target and the sweep are public by design; nothing else numeric
        // may track the clock.
        if (entry.key == 'target' || entry.key == 'sweep') continue;
        expect(v, isNot(closeTo(2.0, 0.5)),
            reason: '${entry.key} looks like a live clock');
      }
      expect(sim.sharedState.containsKey('clock'), isFalse);
      expect(sim.sharedState.containsKey('elapsed'), isFalse);
    });

    test('a quiet phase sends nothing', () {
      // Shared state is diffed value by value; a value that always differs is
      // a packet every tick for a game in which nothing moves.
      final sim = start(2).sim;
      runToStart(sim);

      final before = snapshot(sim.sharedState);
      run(sim, 1.0);
      expect(sameShared(before, sim.sharedState), isTrue);
    });

    test('a guess changes it exactly once', () {
      final sim = start(3).sim;
      runToStart(sim);
      run(sim, 1.0);

      final before = snapshot(sim.sharedState);
      press(sim, 'p1');
      expect(sameShared(before, sim.sharedState), isFalse);

      final after = snapshot(sim.sharedState);
      run(sim, 1.0);
      expect(sameShared(after, sim.sharedState), isTrue);
    });

    test('the seating is published from the first frame', () {
      // The view paints each phone in its own player's colour, from frame one
      // — before any pip exists to carry a colour. `PhoneLayout` has none, so
      // this is the only way a phone knows what it is.
      final sim = start(3).sim;
      expect(phaseOf(sim), ChronoPhase.reveal);

      // Board order, not join order — a ring seats people around the table —
      // so what is pinned is the pairing, which is the part the view reads.
      final seating = (sim.sharedState['seating'] as List).cast<String>();
      expect(seating, hasLength(3));
      expect(seating.toSet(), {
        'p1:${PlayerPalette.green.id}',
        'p2:${PlayerPalette.orange.id}',
        'p3:${PlayerPalette.blue.id}',
      });
    });

    test('the seating is the same list every tick', () {
      // Rebuilding it per frame would be a packet per frame for something that
      // cannot change mid-round.
      final sim = start(2).sim;
      final first = sim.sharedState['seating'];
      run(sim, 1.0);
      expect(identical(first, sim.sharedState['seating']), isTrue);
    });

    test('a guess carries the colour of whoever made it', () {
      final sim = start(2).sim;
      runToStart(sim);
      press(sim, 'p1');

      final rows = sim.sharedState['guesses'] as List;
      expect(rows.single, startsWith('p1:${PlayerPalette.green.id}:'));
    });

    test('results are withheld until nobody can act on them', () {
      final sim = start(2).sim;
      runToStart(sim);
      pressAt(sim, 'p1', 1.0);

      expect(sim.sharedState['results'], isEmpty,
          reason: 'p2 is still guessing');

      press(sim, 'p2');
      expect(sim.sharedState['results'], hasLength(2));
    });

    test('results arrive sorted closest first', () {
      final sim = start(3).sim;
      final target = sim.targetSeconds;
      runToStart(sim);

      pressAt(sim, 'p1', target - 2.0);
      run(sim, 1.0);
      press(sim, 'p2'); // 1 s early
      run(sim, 0.9);
      press(sim, 'p3'); // 0.1 s early

      final rows = (sim.sharedState['results'] as List).cast<String>();
      expect(rows.map((r) => r.split(':').first).toList(),
          ['p3', 'p2', 'p1']);
    });
  });

  group('reset', () {
    test('puts the round back to its opening position', () {
      final started = start(2);
      final sim = started.sim;
      runToStart(sim);
      pressAt(sim, 'p1', 2.0);
      press(sim, 'p2');
      run(sim, ChronometerConfig.resultsSeconds + 1);
      expect(sim.outcome, isNotNull);

      sim.reset();

      expect(phaseOf(sim), ChronoPhase.reveal);
      expect(sim.outcome, isNull, reason: 'the verdict belonged to the last round');
      expect(sim.guessOf('p1'), isNull);
      expect(sim.sharedState['guesses'], isEmpty);
      expect(sim.sharedState['results'], isEmpty);

      // And it plays again from the top.
      runToStart(sim);
      pressAt(sim, 'p1', 1.0);
      expect(sim.guessOf('p1'), isNotNull);
    });

    test('scores from the last round survive it', () {
      final started = start(2);
      final sim = started.sim;
      runToStart(sim);
      pressAt(sim, 'p1', sim.targetSeconds);
      press(sim, 'p2');
      final earned = started.scores.view['p1'];
      expect(earned, greaterThan(0));

      sim.reset();
      expect(started.scores.view['p1'], earned);
    });
  });
}
