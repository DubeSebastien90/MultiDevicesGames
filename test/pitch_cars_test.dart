import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_config.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_game.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
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
  });
}
