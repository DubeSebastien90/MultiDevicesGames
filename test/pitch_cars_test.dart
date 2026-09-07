import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_config.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_game.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_sim.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_view.dart';
import 'package:multiscreen_slingshot/sdk/contract/entity.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/view.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/model/world_rect.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/render/shape_view.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

PhoneSpec phone(String id, {PlayerColor? color}) => PhoneSpec(
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

({PitchCarsSim sim, BoardLayout board, Scoreboard scores}) start(
  int count, {
  int seed = 1,
}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < count; i++)
      phone('p${i + 1}', color: PlayerPalette.all[i % PlayerPalette.size]),
  ]);
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

/// Runs the sim on until anything that has gone over the edge has finished
/// falling and been put back.
///
/// Leaving the track is no longer resolved in the tick it happens: a car sails
/// on for [PitchCarsConfig.fallSeconds] so the table can see it go, and only
/// then reappears. A single step after pushing a car off now catches it
/// mid-air, which is why every one of these scenarios ends with this.
void _settleFall(PitchCarsSim sim) {
  const dt = 1 / PlatformConfig.simHz;
  final ticks = (PitchCarsConfig.fallSeconds / dt).ceil() + 2;
  for (var i = 0; i < ticks; i++) {
    sim.step(dt);
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
  // p2 sits beside p1 along the tangent for the hit, close enough to overlap
  // so the hit step's physics registers a real Forge2D contact between them.
  //
  // Derived from the sim's own car, not a constant: cars are sized by the
  // table now, and the 0.4 this used to be — chosen against a combined radius
  // of 0.5 — is *wider* than the 0.375 two phones give them. The cars sailed
  // past each other, no contact was recorded, and every assertion about being
  // bumped was silently testing the self-fault path instead.
  final overlap = sim.scale.carRadius * 1.5;
  final p2Touching =
      Vector2(hold.x + tangent.x * overlap, hold.y + tangent.y * overlap);
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

  // Now push p1 off the track and let the sim resolve it — over the edge,
  // through the fall, and back onto the road.
  place(offTrack, Vector2.zero(), p2Clear);
  sim.step(dt);
  _settleFall(sim);

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
  // the other car overlapping this one — see the note in
  // [_runGraceWindowScenario] on why the gap comes from the sim's own car
  // rather than a constant — and step once so Forge2D reports a real contact.
  other
    ..setTransform(
        Vector2(preTurn.x + sim.scale.carRadius * 1.5, preTurn.y), 0)
    ..linearVelocity = Vector2.zero()
    ..setAwake(true);
  sim.step(dt);

  // Clear the other car well away — to a point still on the track, so the
  // sim's own off-track correction doesn't pull it straight back — and undo
  // any shove the overlap gave this one, so the turn starts from exactly
  // where the sim thinks it does.
  final farWp = sim.track.pointAtArclength(sim.track.length / 2);
  other
    ..setTransform(Vector2(farWp.x, farWp.y), 0)
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
  _settleFall(sim);

  final settled = sim.carOf(second).position;
  return _CrossTurnResult(
    sim: sim,
    settled: settled.clone(),
    hold: hold,
    preTurn: preTurn,
  );
}

void main() {
  group('PitchCarsSim — turns and input', () {
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

    test('a touch far from the current car aims from where it landed', () {
      final started = start(2);
      final sim = started.sim;
      final before = sim.entities.firstWhere((e) => e.id == sim.currentTurn);

      // Nowhere near the car — which is the point. The car may be jammed
      // against a screen edge or straddling a seam, so the draw is allowed to
      // happen anywhere and is measured from where the finger went down.
      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: before.x + 100,
        worldY: before.y + 100,
        phase: TouchPhase.down,
      ));
      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: before.x + 99,
        worldY: before.y + 100,
        phase: TouchPhase.move,
      ));

      // The car still doesn't budge while aiming...
      final after = sim.entities.firstWhere((e) => e.id == sim.currentTurn);
      expect(after.x, closeTo(before.x, 1e-6));
      expect(after.y, closeTo(before.y, 1e-6));
      // ...but the finger's one-unit displacement became a one-unit pull off
      // the car, not an aim point a hundred units away.
      expect(sim.sharedState['pullX'], closeTo(before.x - 1, 1e-3));
      expect(sim.sharedState['pullY'], closeTo(before.y, 1e-3));
      // And the pivot is published so the view can put a crosshair on it,
      // since nothing else on the board marks that spot.
      expect(sim.sharedState['anchorX'], closeTo(before.x + 100, 1e-3));
      expect(sim.sharedState['anchorY'], closeTo(before.y + 100, 1e-3));
    });

    test('a drag started on the car publishes no anchor to mark', () {
      final started = start(2);
      final sim = started.sim;
      final car = sim.entities.firstWhere((e) => e.id == sim.currentTurn);

      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: car.x,
        worldY: car.y,
        phase: TouchPhase.down,
      ));
      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: car.x - 1,
        worldY: car.y,
        phase: TouchPhase.move,
      ));

      // The car is standing on the pivot; a crosshair would only sit on top
      // of it.
      expect(sim.sharedState['anchorX'], isNull);
      expect(sim.sharedState['anchorY'], isNull);
    });

    test('the aim anchor is dropped once the shot is released', () {
      final started = start(2);
      final sim = started.sim;
      final car = sim.entities.firstWhere((e) => e.id == sim.currentTurn);
      final awayX = car.x + 50;
      final awayY = car.y + 50;

      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: awayX,
        worldY: awayY,
        phase: TouchPhase.down,
      ));
      expect(sim.sharedState['anchorX'], isNotNull);

      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: awayX - PitchCarsConfig.maxPull,
        worldY: awayY,
        phase: TouchPhase.move,
      ));
      sim.onTouch(TouchEvent(
        phoneId: 'p1',
        worldX: awayX - PitchCarsConfig.maxPull,
        worldY: awayY,
        phase: TouchPhase.up,
      ));

      expect(sim.sharedState['anchorX'], isNull);
      expect(sim.sharedState['anchorY'], isNull);
    });

    test('a drag too short to clear the cancel zone consumes no turn', () {
      final started = start(2);
      final sim = started.sim;
      final firstTurn = sim.currentTurn;
      final car = sim.entities.firstWhere((e) => e.id == firstTurn);

      // Inside the dead zone, measured the way the sim measures it.
      final nudge =
          sim.scale.maxPull * PitchCarsConfig.cancelPullFraction * 0.5;
      sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x,
        worldY: car.y,
        phase: TouchPhase.down,
      ));
      sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x - nudge,
        worldY: car.y,
        phase: TouchPhase.move,
      ));
      sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x - nudge,
        worldY: car.y,
        phase: TouchPhase.up,
      ));

      sim.step(1 / PlatformConfig.simHz);

      expect(sim.currentTurn, firstTurn);
      final after = sim.entities.firstWhere((e) => e.id == firstTurn);
      expect(after.x, closeTo(car.x, 1e-6));
      expect(after.y, closeTo(car.y, 1e-6));
      expect(sim.sharedState['moving'], isFalse);
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

    test(
        'two cars going off track at the same arclength do not land on top '
        'of each other', () {
      final started = start(2, seed: 3);
      final sim = started.sim;
      final ids = sim.entities
          .where((e) => e.kind == 'car')
          .map((e) => e.id)
          .toList();

      // Drive both cars off the track at the exact same arclength, on
      // opposite sides — mirroring two starting-grid lanes both bailing on
      // their first throw.
      const s = 0.0;
      final center = sim.track.pointAtArclength(s);
      final tangent = sim.track.tangentAt(s);
      final normal = Vector2(-tangent.y, tangent.x);
      final beyondEdge = sim.track.widthWorld;
      for (final id in ids) {
        sim.carOf(id)
          ..setTransform(
            Vector2(
              center.x + normal.x * beyondEdge,
              center.y + normal.y * beyondEdge,
            ),
            0,
          )
          ..linearVelocity = Vector2.zero()
          ..setAwake(true);
      }
      sim.step(1 / PlatformConfig.simHz);
      _settleFall(sim);

      final settledA = sim.carOf(ids[0]).position;
      final settledB = sim.carOf(ids[1]).position;
      expect(sim.track.isOnTrack(settledA.x, settledA.y), isTrue);
      expect(sim.track.isOnTrack(settledB.x, settledB.y), isTrue);
      expect(
        settledA.distanceTo(settledB),
        // The car is sized by the table now, so the gap they must keep is
        // too — a fixed `PitchCarsConfig.carRadius` here would be asserting
        // against a two-phone board using an eight-phone board's car.
        greaterThan(sim.scale.carRadius * 2),
        reason: 'both cars reset from the same arclength must not overlap',
      );
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
      final track = result.sim.track;

      // Being shoved off costs road, and that is the point of it. A bumped car
      // used to come back to the exact spot it was standing on, which made a
      // hit worth nothing to whoever landed it; it now reappears
      // `knockBackWorld` further back down the centerline.
      final landedArc = track.progressAt(result.settled.x, result.settled.y);
      final heldArc = track.progressAt(result.hold.x, result.hold.y);
      final lost = heldArc - landedArc;

      expect(track.isOnTrack(result.settled.x, result.settled.y), isTrue);
      expect(lost, closeTo(result.sim.scale.knockBackWorld, 0.2),
          reason: 'a bumped car goes back down the road by the knockback, '
              'no more and no less');
      expect(
        (result.settled.x - result.preTurn.x).abs() > 1e-2 ||
            (result.settled.y - result.preTurn.y).abs() > 1e-2,
        isTrue,
        reason: 'a bumped car must not be reset all the way back to its '
            'pre-turn position — that is the self-fault penalty',
      );
    });

    test(
        'a car hit well before leaving the track is treated as self-fault, '
        'despite the earlier hit', () {
      // 21 ticks (~350ms) between the hit and the exit — well outside the
      // 15-tick (250ms) hitGraceWindow.
      final result = _runGraceWindowScenario(holdTicks: 20);

      // Self-fault sends the car back exactly where it had got to before
      // the flick.
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

    test(
        'a hit landed in the idle window before a turn launches does not '
        'excuse that turn from self-fault', () {
      final result = _runCrossTurnGraceScenario();

      expect(result.settled.x, closeTo(result.preTurn.x, 1e-3),
          reason: 'a stale, pre-launch hit timestamp must not read as recent');
      expect(result.settled.y, closeTo(result.preTurn.y, 1e-3));
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
    test('every car says whose it is', () {
      // What turns the disc into that player's character on the board:
      // `ShapeView` draws a plain shape for anybody it has not been told
      // about, so a car that loses this prop silently goes back to being a
      // coloured dot.
      final cars =
          start(3).sim.entities.where((e) => e.kind == 'car').toList();
      expect(cars, hasLength(3));
      for (final car in cars) {
        expect(car.props[ShapeProps.player], car.id,
            reason: 'a car that names nobody is drawn as a plain circle');
      }
    });

    for (final count in [2, 3, 4]) {
      test('$count cars never spawn touching each other', () {
        for (final started in [start(count)]) {
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
          '$count cars all read 0% progress at the start of a race', () {
        // The staggered grid (`_startPositionFor`) places some cars ahead of
        // others in track arclength — a nonzero raw starting position. If
        // `_rawProgress` were still seeded to 0 for those cars, the very
        // first `_updateProgress` step would read that whole head start as
        // free progress. Every car must read exactly 0.0 before anyone has
        // moved, regardless of which row of the grid it starts in.
        for (final started in [start(count)]) {
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

      test('$count cars all spawn fully visible on some phone\'s screen', () {
        final started = start(count);
        final sim = started.sim;
        final coverage = started.board.coverage;
        for (final car in sim.entities.where((e) => e.kind == 'car')) {
          // Sample the car's rim, not just its center — a car half off the
          // edge of its phone is still a bug even if its center is covered.
          const samples = 8;
          for (var i = 0; i < samples; i++) {
            final angle = 2 * math.pi * i / samples;
            final x = car.x + PitchCarsConfig.carVisualRadius * math.cos(angle);
            final y = car.y + PitchCarsConfig.carVisualRadius * math.sin(angle);
            expect(coverage.isCovered(x, y), isTrue,
                reason: '${car.id} spawns with part of its disc off every '
                    'phone\'s screen at ($x, $y)');
          }
        }
      });
    }
  });

  group('the road that is drawn is the road that is driven on', () {
    /// The one entity carrying the centerline.
    Entity ribbonOf(PitchCarsSim sim) {
      final ribbons = [
        for (final e in sim.entities)
          if (e.kind == PitchCarsConfig.ribbonKind) e,
      ];
      expect(ribbons, hasLength(1),
          reason: 'the road is one stroked polyline, not a chain of pieces');
      return ribbons.single;
    }

    for (final count in [2, 3, 4]) {
      test('its points are the centerline collisions walk, at $count phones',
          () {
        final sim = start(count).sim;
        final ribbon = ribbonOf(sim);
        final flat =
            (ribbon.props[PitchCarsConfig.ribbonPoints] as List).cast<double>();
        final outline = sim.track.collisionOutline;

        expect(flat, hasLength(outline.length * 2),
            reason: 'every centerline point, and nothing else, gets drawn');

        // Points ride local to the entity, so putting its position back is
        // what recovers the world centerline. If these ever drift apart, the
        // picture is describing a road the physics does not have — which is
        // exactly the bug the boxes-per-segment version shipped.
        for (var i = 0; i < outline.length; i++) {
          expect(flat[i * 2] + ribbon.x, closeTo(outline[i].x, 1e-9));
          expect(flat[i * 2 + 1] + ribbon.y, closeTo(outline[i].y, 1e-9));
        }
      });
    }

    test('it is stroked at the width isOnTrack allows', () {
      final sim = start(3).sim;
      final ribbon = ribbonOf(sim);

      // A stroke straddles its path, so the full width here reaches exactly
      // `widthWorld / 2` either side — the number `lateralDistance` is
      // compared against. Half of it would draw a road half as wide as the
      // one cars are allowed to sit on.
      expect(
        ribbon.props[PitchCarsConfig.ribbonWidth] as double,
        closeTo(sim.track.widthWorld, 1e-9),
      );
    });

    // The two ends and the bends are where rectangles disagreed with the
    // physics, and both are places a car can legitimately be. A round cap
    // reaches half a width past the last waypoint; nothing but the tarmac
    // being drawn there makes that legible.
    test('the ends of the drawn road are on the track', () {
      final sim = start(3).sim;
      final outline = sim.track.collisionOutline;
      final half = sim.track.widthWorld / 2;

      for (final end in [outline.first, outline.last]) {
        expect(sim.track.isOnTrack(end.x, end.y), isTrue);
        // Just inside the cap the stroke paints, and just outside it.
        expect(sim.track.lateralDistance(end.x, end.y),
            lessThan(half * 0.999));
      }
    });

    test('no leftover box segments', () {
      final sim = start(4).sim;
      for (final e in sim.entities) {
        expect(e.kind, isNot('trackSegment'));
      }
    });
  });

  group('PitchCarsGame — board planning', () {
    test('createView returns a PitchCarsView', () {
      final view = const PitchCarsGame().createView(
          const ViewContext(phoneId: 'p1', board: WorldRect(0, 0, 1, 1)));
      expect(view, isA<PitchCarsView>());
    });

    test('always plans a connected path, never a ring', () {
      for (final count in [2, 3, 4]) {
        final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
        final plan = const PitchCarsGame().planBoard(lobby);
        expect(plan.allowGaps, isFalse);
      }
    });
  });
}
