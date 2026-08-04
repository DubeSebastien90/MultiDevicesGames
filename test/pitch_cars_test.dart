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
}
