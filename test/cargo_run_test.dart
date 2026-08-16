import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/cargo_run/cargo_run_config.dart';
import 'package:multiscreen_slingshot/games/cargo_run/cargo_run_game.dart';
import 'package:multiscreen_slingshot/games/cargo_run/cargo_run_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/entity.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// Cargo Run, driven entirely through the SDK contract — no host, no sockets,
/// no rendering.
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

({CargoRunSim sim, BoardLayout board, Scoreboard scores}) start(
  int phoneCount, {
  int seed = 7,
}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++) phone('p${i + 1}'),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = CargoRunGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = CargoRunSim(
    board.contextFor(scores),
    random: math.Random(seed),
  );
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

const _tick = 1 / PlatformConfig.simHz;

void run(CargoRunSim sim, double seconds) {
  final steps = (seconds * PlatformConfig.simHz).round();
  for (var i = 0; i < steps; i++) {
    sim.step(_tick);
  }
}

Entity? firstWhereOrNull(Iterable<Entity> es, bool Function(Entity) test) {
  for (final e in es) {
    if (test(e)) return e;
  }
  return null;
}

/// A tap on the crate itself, always within its own reach.
void tap(CargoRunSim sim, String phoneId, Entity crate) {
  sim.onTouch(
    TouchEvent(
      phoneId: phoneId,
      worldX: crate.x,
      worldY: crate.y,
      phase: TouchPhase.down,
    ),
  );
}

/// How many crates newly appear over the next [seconds] — a rising edge in
/// the live set on some tick, counted rather than matched by id, because
/// pooled ids are reused: the same string coming back **is** a new spawn, the
/// same rule Subway Skater's bursts and Guac-a-Mole's moles both rely on.
int countSpawns(CargoRunSim sim, double seconds) {
  var prev = sim.entities.map((e) => e.id).toSet();
  var count = 0;
  final steps = (seconds * PlatformConfig.simHz).round();
  for (var i = 0; i < steps; i++) {
    sim.step(_tick);
    final now = sim.entities.map((e) => e.id).toSet();
    count += now.difference(prev).length;
    prev = now;
  }
  return count;
}

void main() {
  group('the belt', () {
    test('is one long runway down the row of phones', () {
      final started = start(4);
      expect(
        started.board.board.width,
        greaterThan(started.board.board.height * 4),
      );
    });

    test('the manifest accepts two to eight, any parity', () {
      const game = CargoRunGame();
      for (final n in [2, 3, 4, 5, 6, 7, 8]) {
        expect(game.manifest.fits(n), isTrue, reason: '$n phones should fit');
      }
      expect(game.manifest.fits(1), isFalse);
    });
  });

  group('spawning', () {
    test('a crate starts off the left edge of the board and rolls right', () {
      final started = start(2);
      final sim = started.sim;
      run(sim, CargoRunConfig.spawnGapStart + 0.05);

      final crate = sim.entities.first;
      expect(crate.x, lessThan(started.board.board.left));
      expect(crate.y, closeTo(started.board.board.centerY, 1e-9));

      final before = crate.x;
      sim.step(_tick);
      final after = sim.entities.firstWhere((e) => e.id == crate.id);
      expect(
        after.x,
        closeTo(before + CargoRunConfig.crateSpeed * _tick, 1e-9),
      );
    });

    test('spawns come faster later in the round', () {
      final early = start(2, seed: 11).sim;
      final earlyCount = countSpawns(early, 5);

      final late = start(2, seed: 11).sim;
      run(late, CargoRunConfig.roundSeconds * CargoRunConfig.rampFraction + 1);
      final lateCount = countSpawns(late, 5);

      expect(lateCount, greaterThan(earlyCount));
    });
  });

  group('catching a crate', () {
    test('a tap far from any crate does nothing', () {
      final started = start(2);
      final sim = started.sim;
      run(sim, CargoRunConfig.spawnGapStart + 0.05);

      sim.onTouch(
        TouchEvent(
          phoneId: 'p1',
          worldX: started.board.board.right + 50,
          worldY: started.board.board.centerY,
          phase: TouchPhase.down,
        ),
      );
      expect(started.scores.isUsed, isFalse);
    });

    test('a move phase is not a tap', () {
      final started = start(2);
      final sim = started.sim;
      run(sim, CargoRunConfig.spawnGapStart + 0.05);
      final crate = sim.entities.first;

      sim.onTouch(
        TouchEvent(
          phoneId: 'p1',
          worldX: crate.x,
          worldY: crate.y,
          phase: TouchPhase.move,
        ),
      );
      expect(sim.entities.where((e) => e.id == crate.id), isNotEmpty);
      expect(started.scores.isUsed, isFalse);
    });

    test('a connecting tap on a green crate scores the tapper a point', () {
      final started = start(3);
      final sim = started.sim;

      Entity? good;
      for (var i = 0; i < PlatformConfig.simHz * 20 && good == null; i++) {
        sim.step(_tick);
        good = firstWhereOrNull(sim.entities, (e) => e.props['good'] == true);
      }
      expect(good, isNotNull, reason: 'no green crate spawned in 20 seconds');

      final caught = good!;
      tap(sim, 'p2', caught);
      expect(started.scores['p2'], CargoRunConfig.pointsGood);
      expect(started.scores['p1'], 0);
      expect(sim.entities.where((e) => e.id == caught.id), isEmpty);
    });

    test('a connecting tap on a red crate costs the tapper a point', () {
      final started = start(3);
      final sim = started.sim;

      Entity? bad;
      for (var i = 0; i < PlatformConfig.simHz * 20 && bad == null; i++) {
        sim.step(_tick);
        bad = firstWhereOrNull(sim.entities, (e) => e.props['good'] == false);
      }
      expect(bad, isNotNull, reason: 'no red crate spawned in 20 seconds');

      tap(sim, 'p1', bad!);
      expect(started.scores['p1'], -CargoRunConfig.pointsBadPenalty);
    });

    test('a crate nobody reaches just rolls off the far end, no penalty', () {
      final started = start(2);
      final sim = started.sim;
      run(sim, CargoRunConfig.spawnGapStart + 0.05);
      final crate = sim.entities.first;

      final crossSeconds =
          (started.board.board.width + CargoRunConfig.crateRadius * 6) /
          CargoRunConfig.crateSpeed;
      run(sim, crossSeconds);

      expect(sim.entities.where((e) => e.id == crate.id), isEmpty);
      expect(started.scores.isUsed, isFalse);
    });
  });

  group('crossing the seam', () {
    test(
      'a crate sweeps continuously across the real gap between two phones',
      () {
        final started = start(2);
        final sim = started.sim;
        final board = started.board;
        final context = board.contextFor(started.scores);

        final p1 = board.slices[0].viewport;
        final p2 = board.slices[1].viewport;
        expect(p1.right, lessThan(p2.left), reason: 'expected a real gap');

        run(sim, CargoRunConfig.spawnGapStart + 0.05);
        final id = sim.entities.first.id;

        var sawPhoneOne = false;
        var sawGap = false;
        var sawPhoneTwo = false;
        double? lastX;

        for (var i = 0; i < PlatformConfig.simHz * 15; i++) {
          sim.step(_tick);
          final e = firstWhereOrNull(sim.entities, (e) => e.id == id);
          if (e == null) break; // rolled off the far end

          if (lastX != null) {
            // Never a jump: exactly one tick of the belt's constant speed.
            expect(
              e.x - lastX,
              closeTo(CargoRunConfig.crateSpeed * _tick, 1e-9),
            );
          }
          lastX = e.x;

          final owner = context.phoneAt(e.x, e.y);
          if (owner == 'p1') sawPhoneOne = true;
          if (owner == 'p2') sawPhoneTwo = true;
          if (owner == null && e.x > p1.right && e.x < p2.left) sawGap = true;

          if (sawPhoneOne && sawGap && sawPhoneTwo) break;
        }

        expect(sawPhoneOne, isTrue, reason: 'never observed on the first phone');
        expect(sawGap, isTrue, reason: 'never observed genuinely in the gap');
        expect(
          sawPhoneTwo,
          isTrue,
          reason: 'never swept onto the second phone',
        );
      },
    );
  });

  group('ending the round', () {
    test('nobody scoring ends the round in a draw', () {
      final started = start(2);
      run(started.sim, CargoRunConfig.roundSeconds + 0.1);

      final outcome = started.sim.outcome;
      expect(outcome, isNotNull);
      expect(outcome!.kind, OutcomeKind.draw);
    });

    test('the highest scorer wins a contest, and it is latched', () {
      final started = start(3);
      final sim = started.sim;

      Entity? good;
      for (var i = 0; i < PlatformConfig.simHz * 20 && good == null; i++) {
        sim.step(_tick);
        good = firstWhereOrNull(sim.entities, (e) => e.props['good'] == true);
      }
      tap(sim, 'p3', good!);

      run(sim, CargoRunConfig.roundSeconds);
      final outcome = sim.outcome;
      expect(outcome, isNotNull);
      expect(outcome!.kind, OutcomeKind.contest);
      expect(outcome.winners, {'p3'});

      // Polled several times a tick, so it has to be the same object each time.
      expect(sim.outcome, same(outcome));
    });

    test('scoring stops once the round is over', () {
      final started = start(2);
      final sim = started.sim;
      run(sim, CargoRunConfig.roundSeconds + 0.1);
      expect(sim.outcome, isNotNull);

      sim.onTouch(
        TouchEvent(
          phoneId: 'p1',
          worldX: started.board.board.centerX,
          worldY: started.board.board.centerY,
          phase: TouchPhase.down,
        ),
      );
      expect(started.scores.isUsed, isFalse);
    });
  });

  test('reset clears every crate and the latched outcome', () {
    final started = start(2);
    final sim = started.sim;
    run(sim, CargoRunConfig.roundSeconds + 0.1);
    expect(sim.outcome, isNotNull);

    sim.reset();
    expect(sim.outcome, isNull);
    expect(sim.entities, isEmpty);
    expect(sim.sharedState['secondsLeft'], CargoRunConfig.roundSeconds.round());
  });
}
