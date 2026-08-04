import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_config.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_game.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_sim.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_view.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/view.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/world_rect.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

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

({PitchCarsSim sim, BoardLayout board, Scoreboard scores}) start(
  int count, {
  int seed = 1,
}) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  final plan = const PitchCarsGame().planBoard(lobby);
  final board = const BoardCompiler().compile(plan, lobby);
  final sim = PitchCarsSim(board.contextFor(scores), random: math.Random(seed));
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

/// Aims the current turn's car toward the forward tangent of its own
/// position on the track and releases a full pull, then runs the sim until
/// the turn advances (or the step budget runs out).
void _flickForward(PitchCarsSim sim) {
  final phoneId = sim.currentTurn;
  final car = sim.entities.firstWhere((e) => e.id == phoneId);
  final s = sim.track.progressAt(car.x, car.y);
  final tangent = sim.track.tangentAt(s);

  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: car.x,
    worldY: car.y,
    phase: TouchPhase.down,
  ));
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: car.x - tangent.x * PitchCarsConfig.maxPull,
    worldY: car.y - tangent.y * PitchCarsConfig.maxPull,
    phase: TouchPhase.move,
  ));
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: car.x - tangent.x * PitchCarsConfig.maxPull,
    worldY: car.y - tangent.y * PitchCarsConfig.maxPull,
    phase: TouchPhase.up,
  ));

  var steps = 0;
  while (sim.outcome == null &&
      sim.currentTurn == phoneId &&
      steps < PlatformConfig.simHz * 10) {
    sim.step(1 / PlatformConfig.simHz);
    steps++;
  }
}

/// Result of [_runGraceWindowScenario]: where the current-turn car ended up
/// after being pushed off the track, plus the two candidate reset
/// destinations so the test can tell which one the sim actually chose.
class _GraceWindowResult {
  _GraceWindowResult({
    required this.settled,
    required this.hold,
    required this.preTurn,
  });
  final Vector2 settled;
  final Vector2 hold;
  final Vector2 preTurn;
}

/// Deterministically engineers the exact scenario the hit-grace-window fix
/// is about: the current turn's car is hit by another car, stays on the
/// track for [holdTicks] more physics ticks, and is then pushed off the
/// track. Real Forge2D physics still drives the collision and the off-track
/// reset — only *positioning* is puppeted directly through [PitchCarsSim
/// .carOf] (a public accessor the sim itself uses) so the timing between the
/// hit and the exit is exact rather than hunted for via random seeds.
///
/// `holdTicks` is measured against `PitchCarsConfig.hitGraceWindow`, which
/// is exactly 15 ticks at the sim's 60 Hz (`PlatformConfig.simHz`).
_GraceWindowResult _runGraceWindowScenario({required int holdTicks}) {
  final started = start(2, seed: 1);
  final sim = started.sim;
  final dt = 1 / PlatformConfig.simHz;

  final p1 = sim.currentTurn;
  final p2 = sim.entities.firstWhere((e) => e.id != p1 && e.kind == 'car').id;

  final startCar = sim.entities.firstWhere((e) => e.id == p1);
  final preTurn = Vector2(startCar.x, startCar.y);

  // A tiny flick just to start the turn (sets `_moving` and starts the
  // sim's internal since-launch clock) — its direction/magnitude do not
  // matter, because every frame's position from here on is driven directly
  // below.
  sim.onTouch(TouchEvent(phoneId: p1, worldX: startCar.x, worldY: startCar.y, phase: TouchPhase.down));
  sim.onTouch(TouchEvent(
      phoneId: p1, worldX: startCar.x - 0.5, worldY: startCar.y, phase: TouchPhase.move));
  sim.onTouch(TouchEvent(
      phoneId: p1, worldX: startCar.x - 0.5, worldY: startCar.y, phase: TouchPhase.up));

  // A point on the centerline, away from the start line, to hold the car at
  // while "on track" — kept distinct from `preTurn` so the two possible
  // reset destinations below are distinguishable in the assertions.
  final holdArc = sim.track.length / 2;
  final holdWp = sim.track.pointAtArclength(holdArc);
  final tangent = sim.track.tangentAt(holdArc);
  final hold = Vector2(holdWp.x, holdWp.y);
  final normal = Vector2(-tangent.y, tangent.x);
  // p2 sits beside p1 along the tangent for the hit, overlapping it (0.9
  // world units apart, less than their combined radius of 1.0) so the hit
  // step's physics registers a real Forge2D contact between them.
  final p2Touching = Vector2(hold.x + tangent.x * 0.9, hold.y + tangent.y * 0.9);
  // Once the hit is recorded, p2 is moved well clear of p1 so it does not
  // keep pushing p1 around every subsequent step through overlap
  // resolution — everything from here on should be p1 sitting still.
  final p2Clear = Vector2(hold.x + tangent.x * 4.0, hold.y + tangent.y * 4.0);
  // Well outside the track's half-width (1.5 world units), along the normal.
  final offTrack = Vector2(
    hold.x + normal.x * PitchCarsConfig.trackWidthWorld,
    hold.y + normal.y * PitchCarsConfig.trackWidthWorld,
  );

  final car1 = sim.carOf(p1);
  final car2 = sim.carOf(p2);

  void place(Vector2 p1Pos, Vector2 p1Vel, Vector2 p2Pos) {
    car1
      ..setTransform(p1Pos, 0)
      ..linearVelocity = p1Vel
      ..angularVelocity = 0
      ..setAwake(true);
    car2
      ..setTransform(p2Pos, 0)
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0
      ..setAwake(true);
  }

  // The hit.
  place(hold, Vector2(0.5, 0), p2Touching);
  sim.step(dt);

  // Hold p1 on the track for `holdTicks` more frames — real elapsed
  // simulation time passes, so the sim's since-launch clock advances well
  // past the single tick the hit took.
  for (var i = 0; i < holdTicks; i++) {
    place(hold, Vector2.zero(), p2Clear);
    sim.step(dt);
  }

  // Now push p1 off the track and let the sim resolve it.
  place(offTrack, Vector2.zero(), p2Clear);
  sim.step(dt);

  final settled = sim.entities.firstWhere((e) => e.id == p1);
  return _GraceWindowResult(
    settled: Vector2(settled.x, settled.y),
    hold: hold,
    preTurn: preTurn,
  );
}

void main() {
  group('PitchCarsSim — turns and input', () {
    test('the first turn belongs to the first phone in join order', () {
      final started = start(2);
      expect(started.sim.currentTurn, 'p1');
    });

    test('a touch on the current car from ANY phone starts a drag', () {
      final started = start(2);
      final sim = started.sim;
      final car = sim.entities.firstWhere((e) => e.id == sim.currentTurn);

      // Touch arrives tagged 'p2' — a different phone than the current
      // turn's owner — but lands on p1's car. It must still be accepted,
      // because the car may physically sit under a different phone's
      // screen than the one its owner joined from.
      sim.onTouch(TouchEvent(
        phoneId: 'p2',
        worldX: car.x,
        worldY: car.y,
        phase: TouchPhase.down,
      ));
      sim.onTouch(TouchEvent(
        phoneId: 'p2',
        worldX: car.x - 1,
        worldY: car.y,
        phase: TouchPhase.move,
      ));

      final pulled = sim.entities.firstWhere((e) => e.id == sim.currentTurn);
      expect(pulled.x, closeTo(car.x - 1, 1e-6));
    });

    test('a touch far from the current car is ignored', () {
      final started = start(2);
      final sim = started.sim;
      final before = sim.entities.firstWhere((e) => e.id == sim.currentTurn);

      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: before.x + 100,
        worldY: before.y + 100,
        phase: TouchPhase.down,
      ));
      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: before.x + 90,
        worldY: before.y + 100,
        phase: TouchPhase.move,
      ));

      final after = sim.entities.firstWhere((e) => e.id == sim.currentTurn);
      expect(after.x, closeTo(before.x, 1e-6));
      expect(after.y, closeTo(before.y, 1e-6));
    });

    test('a real pull-and-release launches the car and eventually advances the turn', () {
      final started = start(2);
      final sim = started.sim;
      final firstTurn = sim.currentTurn;
      final car = sim.entities.firstWhere((e) => e.id == firstTurn);

      sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x,
        worldY: car.y,
        phase: TouchPhase.down,
      ));
      sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x - PitchCarsConfig.maxPull,
        worldY: car.y,
        phase: TouchPhase.move,
      ));
      sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x - PitchCarsConfig.maxPull,
        worldY: car.y,
        phase: TouchPhase.up,
      ));

      var steps = 0;
      while (sim.currentTurn == firstTurn && steps < PlatformConfig.simHz * 10) {
        sim.step(1 / PlatformConfig.simHz);
        steps++;
      }

      expect(sim.currentTurn, isNot(firstTurn),
          reason: 'the turn never advanced after the car settled');
    });

    test('a tap too small to count as a pull does not consume the turn', () {
      final started = start(2);
      final sim = started.sim;
      final firstTurn = sim.currentTurn;
      final car = sim.entities.firstWhere((e) => e.id == firstTurn);

      sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x,
        worldY: car.y,
        phase: TouchPhase.down,
      ));
      sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x + 0.01,
        worldY: car.y,
        phase: TouchPhase.up,
      ));

      sim.step(1 / PlatformConfig.simHz);
      expect(sim.currentTurn, firstTurn);
    });
  });

  group('PitchCarsSim — off track and winning', () {
    test('once a launched car settles, it is always back on the track', () {
      final started = start(2, seed: 5);
      final sim = started.sim;
      final firstTurn = sim.currentTurn;
      final car = sim.entities.firstWhere((e) => e.id == firstTurn);

      // Aim hard sideways, across the ribbon rather than along it — the
      // shot most likely to leave the track.
      final s = sim.track.progressAt(car.x, car.y);
      final tangent = sim.track.tangentAt(s);
      final sidewaysX = -tangent.y;
      final sidewaysY = tangent.x;

      sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x,
        worldY: car.y,
        phase: TouchPhase.down,
      ));
      sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x - sidewaysX * PitchCarsConfig.maxPull,
        worldY: car.y - sidewaysY * PitchCarsConfig.maxPull,
        phase: TouchPhase.move,
      ));
      sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x - sidewaysX * PitchCarsConfig.maxPull,
        worldY: car.y - sidewaysY * PitchCarsConfig.maxPull,
        phase: TouchPhase.up,
      ));

      var steps = 0;
      while (sim.currentTurn == firstTurn && steps < PlatformConfig.simHz * 10) {
        sim.step(1 / PlatformConfig.simHz);
        steps++;
      }

      final settled = sim.entities.firstWhere((e) => e.id == firstTurn);
      expect(sim.track.isOnTrack(settled.x, settled.y), isTrue,
          reason: 'a car that left the track must be reset back onto it');
    });

    test('repeated forward flicks eventually reach the finish and award a point', () {
      final started = start(2, seed: 7);
      final sim = started.sim;

      var turns = 0;
      while (sim.outcome == null && turns < 300) {
        _flickForward(sim);
        turns++;
      }

      expect(sim.outcome, isNotNull, reason: 'nobody finished the race');
      expect(sim.outcome!.won, isTrue);
      expect(started.scores.isUsed, isTrue);
      expect(started.scores.view.ranked.first.total, 1);
    });

    test('a fresh race is not already won', () {
      final started = start(2, seed: 9);
      for (var i = 0; i < 60; i++) {
        started.sim.step(1 / PlatformConfig.simHz);
      }
      expect(started.sim.outcome, isNull);
    });

    test(
        'a car hit shortly before leaving the track is treated as bumped, '
        'not self-fault', () {
      // 11 ticks (~183ms) between the hit and the exit — well inside the
      // 15-tick (250ms) hitGraceWindow.
      final result = _runGraceWindowScenario(holdTicks: 10);

      expect(result.settled.x, closeTo(result.hold.x, 1e-3));
      expect(result.settled.y, closeTo(result.hold.y, 1e-3));
      expect(
        (result.settled.x - result.preTurn.x).abs() > 1e-2 ||
            (result.settled.y - result.preTurn.y).abs() > 1e-2,
        isTrue,
        reason: 'a bumped car must not be reset all the way back to its '
            'pre-turn position',
      );
    });

    test(
        'a car hit well before leaving the track is treated as self-fault, '
        'despite the earlier hit', () {
      // 21 ticks (~350ms) between the hit and the exit — well outside the
      // 15-tick (250ms) hitGraceWindow.
      final result = _runGraceWindowScenario(holdTicks: 20);

      expect(result.settled.x, closeTo(result.preTurn.x, 1e-3));
      expect(result.settled.y, closeTo(result.preTurn.y, 1e-3));
      expect(
        (result.settled.x - result.hold.x).abs() > 1e-2 ||
            (result.settled.y - result.hold.y).abs() > 1e-2,
        isTrue,
        reason: 'a self-fault car reset to its last on-track point instead '
            'of its pre-turn position would defeat the grace window',
      );
    });
  });

  group('PitchCarsGame — board planning', () {
    test('createView returns a PitchCarsView', () {
      final view = const PitchCarsGame().createView(
          const ViewContext(phoneId: 'p1', board: WorldRect(0, 0, 1, 1)));
      expect(view, isA<PitchCarsView>());
    });

    test('with 2 or 3 phones it always plans a row, never a ring', () {
      for (final count in [2, 3]) {
        final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
        final plan = const PitchCarsGame().planBoard(lobby);
        expect(plan.allowGaps, isFalse);
      }
    });

    test('with 4 phones it can plan either a row or a ring', () {
      final lobby = LobbyInfo([for (var i = 0; i < 4; i++) phone('p${i + 1}')]);
      final seen = <bool>{};
      for (var i = 0; i < 40; i++) {
        seen.add(const PitchCarsGame().planBoard(lobby).allowGaps);
      }
      expect(seen, containsAll(<bool>{true, false}),
          reason: '40 trials at 4 phones should see both a row and a ring');
    });
  });
}
