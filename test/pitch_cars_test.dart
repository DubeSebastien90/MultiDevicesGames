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

/// Same as [start], but keeps re-rolling the board plan until it comes back a
/// ring rather than a row.
///
/// `PitchCarsGame.planBoard` flips its own unseeded coin, so the ring path
/// cannot be reached by choosing a seed. Re-rolling is not probabilistic in
/// any way that matters: at 4 phones each roll is an even coin, so the loop
/// below fails only if 200 consecutive flips come up heads. The *sim* is still
/// seeded, so the track it generates for that ring is fully deterministic.
({PitchCarsSim sim, BoardLayout board, Scoreboard scores}) startRing(
  int count, {
  int seed = 1,
}) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  var plan = const PitchCarsGame().planBoard(lobby);
  for (var tries = 0; !plan.allowGaps && tries < 200; tries++) {
    plan = const PitchCarsGame().planBoard(lobby);
  }
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
    required this.sim,
    required this.settled,
    required this.hold,
    required this.preTurn,
  });
  final PitchCarsSim sim;
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
    sim: sim,
    settled: Vector2(settled.x, settled.y),
    hold: hold,
    preTurn: preTurn,
  );
}

/// Result of [_runCrossTurnGraceScenario].
class _CrossTurnResult {
  _CrossTurnResult({
    required this.sim,
    required this.settled,
    required this.hold,
    required this.preTurn,
  });
  final PitchCarsSim sim;
  final Vector2 settled;
  final Vector2 hold;
  final Vector2 preTurn;
}

/// The cross-turn variant of [_runGraceWindowScenario]: the collision happens
/// in the **idle window** between one turn ending and the next one launching,
/// so its timestamp is taken from the previous turn's flight clock — which
/// `_launch` then resets to zero. Left unhandled that makes the sim's
/// "how long since the hit" arithmetic negative, and a negative delta compares
/// as "well inside the grace window" for the whole of the following turn,
/// re-opening the clip-anything-then-drive-off-for-free exploit.
///
/// The car that gets hit here is the one whose turn is *about to start*, and
/// it is then driven off the track entirely under its own power. That must be
/// judged self-fault.
_CrossTurnResult _runCrossTurnGraceScenario() {
  final started = start(2, seed: 1);
  final sim = started.sim;
  final dt = 1 / PlatformConfig.simHz;

  final first = sim.currentTurn;

  // Turn one: a real (tiny) flick, run to completion so the sim's
  // since-launch clock ends up well advanced and the turn hands over.
  final firstCar = sim.entities.firstWhere((e) => e.id == first);
  sim.onTouch(TouchEvent(
      phoneId: first, worldX: firstCar.x, worldY: firstCar.y, phase: TouchPhase.down));
  sim.onTouch(TouchEvent(
      phoneId: first, worldX: firstCar.x - 0.5, worldY: firstCar.y, phase: TouchPhase.move));
  sim.onTouch(TouchEvent(
      phoneId: first, worldX: firstCar.x - 0.5, worldY: firstCar.y, phase: TouchPhase.up));
  var guard = 0;
  while (sim.currentTurn == first && guard < PlatformConfig.simHz * 10) {
    sim.step(dt);
    guard++;
  }

  final second = sim.currentTurn;
  final secondCar = sim.carOf(second);
  final other = sim.carOf(first);
  // The sim captured this as the new turn's pre-turn position when the turn
  // advanced; the assertions below are written against it.
  final preTurn = secondCar.position.clone();

  // The idle-window hit: nothing has been launched, `_moving` is false, and
  // the since-launch clock is frozen at the previous turn's final value. Park
  // the other car overlapping this one and step once so Forge2D reports a
  // real contact.
  other
    ..setTransform(Vector2(preTurn.x + 0.9, preTurn.y), 0)
    ..linearVelocity = Vector2.zero()
    ..setAwake(true);
  sim.step(dt);

  // Clear the other car well away, and undo any shove the overlap gave this
  // one, so the turn starts from exactly where the sim thinks it does.
  other
    ..setTransform(Vector2(preTurn.x + 12, preTurn.y + 12), 0)
    ..linearVelocity = Vector2.zero();
  secondCar
    ..setTransform(preTurn.clone(), 0)
    ..linearVelocity = Vector2.zero()
    ..angularVelocity = 0;

  // Now launch this car's turn for real. `_launch` zeroes the since-launch
  // clock — the moment the stale timestamp turns into a negative delta.
  sim.onTouch(TouchEvent(
      phoneId: second, worldX: preTurn.x, worldY: preTurn.y, phase: TouchPhase.down));
  sim.onTouch(TouchEvent(
      phoneId: second, worldX: preTurn.x - 0.5, worldY: preTurn.y, phase: TouchPhase.move));
  sim.onTouch(TouchEvent(
      phoneId: second, worldX: preTurn.x - 0.5, worldY: preTurn.y, phase: TouchPhase.up));

  // Drive it up the track under its own power, then off the edge — the
  // "clip a neighbour, then go wherever you like" move.
  final holdArc = sim.track.length / 2;
  final holdWp = sim.track.pointAtArclength(holdArc);
  final hold = Vector2(holdWp.x, holdWp.y);
  final tangent = sim.track.tangentAt(holdArc);
  final normal = Vector2(-tangent.y, tangent.x);
  final offTrack = Vector2(
    hold.x + normal.x * PitchCarsConfig.trackWidthWorld,
    hold.y + normal.y * PitchCarsConfig.trackWidthWorld,
  );

  for (var i = 0; i < 3; i++) {
    secondCar
      ..setTransform(hold.clone(), 0)
      ..linearVelocity = Vector2.zero()
      ..setAwake(true);
    sim.step(dt);
  }
  secondCar
    ..setTransform(offTrack, 0)
    ..linearVelocity = Vector2.zero()
    ..setAwake(true);
  sim.step(dt);

  final settled = sim.carOf(second).position;
  return _CrossTurnResult(
    sim: sim,
    settled: settled.clone(),
    hold: hold,
    preTurn: preTurn,
  );
}

/// Where the sim now sends a car it resets: the centerline point at
/// [reference]'s arclength, not [reference] itself.
Vector2 _centerlineAt(PitchCarsSim sim, Vector2 reference) {
  final wp = sim.track
      .pointAtArclength(sim.track.progressAt(reference.x, reference.y));
  return Vector2(wp.x, wp.y);
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

      // The car itself never moves during the pull (pool cue, not
      // slingshot) — the drag being accepted shows up in sharedState's
      // aim point instead.
      final pulled = sim.entities.firstWhere((e) => e.id == sim.currentTurn);
      expect(pulled.x, closeTo(car.x, 1e-6));
      expect(pulled.y, closeTo(car.y, 1e-6));
      // sharedState rounds to 3 decimals to avoid rebroadcasting float noise.
      expect(sim.sharedState['pullX'], closeTo(car.x - 1, 1e-3));
      expect(sim.sharedState['pullY'], closeTo(car.y, 1e-3));
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

    test('a car that spins without ever really translating still ends its turn', () {
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

      // Forces the pathological case directly: velocity that stays above
      // restSpeed forever (so the ordinary rest-delay check never fires) by
      // flipping direction every tick, plus heavy spin — but net
      // translation stays near zero, which is exactly "spinning in place"
      // as reported from actual play. Only the stall watchdog
      // (PitchCarsConfig.stallTimeout) can end a turn like this.
      final body = sim.carOf(firstTurn);
      final dt = 1 / PlatformConfig.simHz;
      var steps = 0;
      // 3s budget: past stallTimeout (2s), comfortably under maxFlightTime
      // (6s) — a pass here is specifically the watchdog, not the other cap.
      while (sim.currentTurn == firstTurn && steps < PlatformConfig.simHz * 3) {
        body
          ..linearVelocity = Vector2(steps.isEven ? 1.0 : -1.0, 0) * (PitchCarsConfig.restSpeed * 2)
          ..angularVelocity = 25.0;
        sim.step(dt);
        steps++;
      }

      expect(sim.currentTurn, isNot(firstTurn),
          reason: 'a car stuck oscillating in place must not hang the turn forever');
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

      // Self-fault sends the car back to where it had got to before the
      // flick — as the centerline point at that arclength, never the literal
      // point (see `_resolveOffTrack`), so the comparison is against the
      // projection rather than the raw pre-turn position.
      final expected = _centerlineAt(result.sim, result.preTurn);
      expect(result.settled.x, closeTo(expected.x, 1e-3));
      expect(result.settled.y, closeTo(expected.y, 1e-3));
      expect(
        (result.settled.x - result.hold.x).abs() > 1e-2 ||
            (result.settled.y - result.hold.y).abs() > 1e-2,
        isTrue,
        reason: 'a self-fault car reset to its last on-track point instead '
            'of its pre-turn position would defeat the grace window',
      );
    });

    test(
        'a hit landed in the idle window before a turn launches does not '
        'excuse that turn from self-fault', () {
      final result = _runCrossTurnGraceScenario();

      final expected = _centerlineAt(result.sim, result.preTurn);
      expect(result.settled.x, closeTo(expected.x, 1e-3),
          reason: 'a stale, pre-launch hit timestamp must not read as recent');
      expect(result.settled.y, closeTo(expected.y, 1e-3));
      expect(
        (result.settled.x - result.hold.x).abs() > 1e-2 ||
            (result.settled.y - result.hold.y).abs() > 1e-2,
        isTrue,
        reason: 'the car was let off as "bumped" on the strength of a '
            'collision recorded before its turn even started — the clip-'
            'anything-then-drive-off-for-free exploit',
      );
    });

  });

  group('PitchCarsSim — the starting grid', () {
    for (final count in [2, 3, 4]) {
      test('$count cars never spawn touching each other', () {
        for (final started in [
          start(count),
          if (count == 4) startRing(count),
        ]) {
          final sim = started.sim;
          final cars = sim.entities.where((e) => e.kind == 'car').toList();
          expect(cars.length, count);
          for (var i = 0; i < cars.length; i++) {
            for (var j = i + 1; j < cars.length; j++) {
              final d = math.sqrt(math.pow(cars[i].x - cars[j].x, 2) +
                  math.pow(cars[i].y - cars[j].y, 2));
              expect(d, greaterThan(PitchCarsConfig.carRadius * 2),
                  reason: '${cars[i].id} and ${cars[j].id} spawn overlapping, '
                      'which Forge2D resolves with a shove and a spurious '
                      'contact before anyone has flicked');
            }
          }
        }
      });

      test('$count cars all spawn on the track', () {
        final sim = start(count).sim;
        for (final car in sim.entities.where((e) => e.kind == 'car')) {
          expect(sim.track.isOnTrack(car.x, car.y), isTrue,
              reason: '${car.id} starts off the track');
        }
      });

      test(
          '$count cars all read 0% progress at the start of a race, on '
          'both topologies', () {
        // The staggered grid (`_startPositionFor`) places some cars ahead of
        // others in track arclength — a nonzero raw starting position. If
        // `_rawProgress` were still seeded to 0 for those cars, the very
        // first `_updateProgress` step would read that whole head start as
        // free progress. Every car must read exactly 0.0 before anyone has
        // moved, regardless of which row of the grid it starts in.
        for (final started in [start(count), startRing(count)]) {
          final sim = started.sim;
          // Cars start at rest, so a dt=0 step moves nothing via physics —
          // it only exercises `_updateProgress`'s first-step delta
          // bookkeeping, which is what actually reads `_rawProgress` and
          // would leak a staggered-grid head start into `sharedState`.
          sim.step(0.0);
          for (var i = 1; i <= count; i++) {
            expect(sim.sharedState['progress_p$i'], 0.0,
                reason: 'p$i has nonzero progress before the race has even '
                    'started — a starting-grid head start leaking through');
          }
        }
      });
    }
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
