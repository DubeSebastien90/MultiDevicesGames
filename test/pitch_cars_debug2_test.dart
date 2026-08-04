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
  test('debug seed5 sideways timing', () {
    final started = start(2, seed: 5);
    final sim = started.sim;
    final firstTurn = sim.currentTurn;
    final car = sim.entities.firstWhere((e) => e.id == firstTurn);
    final other = sim.entities.firstWhere((e) => e.id != firstTurn && e.kind == 'car');
    print('p1=(${car.x},${car.y}) other=(${other.x},${other.y}) dist=${(math.sqrt(math.pow(car.x - other.x, 2) + math.pow(car.y - other.y, 2)))}');

    final s = sim.track.progressAt(car.x, car.y);
    final tangent = sim.track.tangentAt(s);
    final sidewaysX = -tangent.y;
    final sidewaysY = tangent.x;
    print('tangent=(${tangent.x},${tangent.y}) sideways=($sidewaysX,$sidewaysY)');
    // which direction points toward other car?
    final towardOther = (other.x - car.x) * sidewaysX + (other.y - car.y) * sidewaysY;
    print('towardOther dot = $towardOther (positive means +sideways points toward other)');

    // mix: mostly toward the other car, slight forward bias for a glancing hit
    var dirX = sidewaysX * 0.85 + tangent.x * 0.15;
    var dirY = sidewaysY * 0.85 + tangent.y * 0.15;
    final dirLen = math.sqrt(dirX * dirX + dirY * dirY);
    dirX /= dirLen;
    dirY /= dirLen;
    sim.onTouch(TouchEvent(phoneId: firstTurn, worldX: car.x, worldY: car.y, phase: TouchPhase.down));
    sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x - dirX * PitchCarsConfig.maxPull,
        worldY: car.y - dirY * PitchCarsConfig.maxPull,
        phase: TouchPhase.move));
    sim.onTouch(TouchEvent(
        phoneId: firstTurn,
        worldX: car.x - dirX * PitchCarsConfig.maxPull,
        worldY: car.y - dirY * PitchCarsConfig.maxPull,
        phase: TouchPhase.up));

    var prevX = car.x;
    var prevY = car.y;
    var prevOx = other.x;
    var prevOy = other.y;
    for (var i = 0; i < 600 && sim.currentTurn == firstTurn; i++) {
      sim.step(1 / PlatformConfig.simHz);
      final e = sim.entities.firstWhere((x) => x.id == firstTurn);
      final o = sim.entities.firstWhere((x) => x.id != firstTurn && x.kind == 'car');
      final jump = math.sqrt(math.pow(e.x - prevX, 2) + math.pow(e.y - prevY, 2));
      final oJump = math.sqrt(math.pow(o.x - prevOx, 2) + math.pow(o.y - prevOy, 2));
      if (jump > 0.3) {
        print('P1 reset jump at step $i (${(i / 60 * 1000).round()}ms): (${prevX.toStringAsFixed(3)},${prevY.toStringAsFixed(3)}) -> (${e.x.toStringAsFixed(3)},${e.y.toStringAsFixed(3)})');
      }
      if (oJump > 0.02 && i < 30) {
        print('OTHER moved at step $i: (${prevOx.toStringAsFixed(3)},${prevOy.toStringAsFixed(3)}) -> (${o.x.toStringAsFixed(3)},${o.y.toStringAsFixed(3)})');
      }
      prevX = e.x;
      prevY = e.y;
      prevOx = o.x;
      prevOy = o.y;
    }
    final settled = sim.entities.firstWhere((e) => e.id == firstTurn);
    print('settled pos=(${settled.x},${settled.y}) currentTurn=${sim.currentTurn}');
    print('original pos=(${car.x},${car.y})');
  });
}
