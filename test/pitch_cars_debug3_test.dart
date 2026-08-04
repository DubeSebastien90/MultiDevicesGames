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

/// Returns (hitStep, resetStep, resetMatchesOriginal) or null if nothing
/// interesting happened within the budget.
({int hitStep, int? resetStep, bool matchesOriginal})? tryScenario(
    int count, int seed, double mixRatio) {
  final started = start(count, seed: seed);
  final sim = started.sim;
  final firstTurn = sim.currentTurn;
  final car = sim.entities.firstWhere((e) => e.id == firstTurn);
  final others = sim.entities.where((e) => e.id != firstTurn && e.kind == 'car').toList();

  final s = sim.track.progressAt(car.x, car.y);
  final tangent = sim.track.tangentAt(s);
  final sidewaysX = -tangent.y;
  final sidewaysY = tangent.x;

  var dirX = sidewaysX * mixRatio + tangent.x * (1 - mixRatio);
  var dirY = sidewaysY * mixRatio + tangent.y * (1 - mixRatio);
  var len = math.sqrt(dirX * dirX + dirY * dirY);
  dirX /= len;
  dirY /= len;

  final origX = car.x;
  final origY = car.y;

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

  final prevOthers = {for (final o in others) o.id: [o.x, o.y]};
  var prevX = car.x;
  var prevY = car.y;
  int? hitStep;
  int? resetStep;
  bool matchesOriginal = false;

  for (var i = 0; i < 600 && sim.currentTurn == firstTurn; i++) {
    sim.step(1 / PlatformConfig.simHz);
    final e = sim.entities.firstWhere((x) => x.id == firstTurn);

    if (hitStep == null) {
      for (final oid in prevOthers.keys) {
        final o = sim.entities.firstWhere((x) => x.id == oid);
        final prev = prevOthers[oid]!;
        final d = math.sqrt(math.pow(o.x - prev[0], 2) + math.pow(o.y - prev[1], 2));
        if (d > 0.005) {
          hitStep = i;
        }
        prevOthers[oid] = [o.x, o.y];
      }
    } else {
      for (final oid in prevOthers.keys) {
        final o = sim.entities.firstWhere((x) => x.id == oid);
        prevOthers[oid] = [o.x, o.y];
      }
    }

    final jump = math.sqrt(math.pow(e.x - prevX, 2) + math.pow(e.y - prevY, 2));
    if (jump > 0.3 && resetStep == null) {
      resetStep = i;
      matchesOriginal = (e.x - origX).abs() < 0.05 && (e.y - origY).abs() < 0.05;
    }
    prevX = e.x;
    prevY = e.y;
  }

  if (hitStep == null) return null;
  return (hitStep: hitStep, resetStep: resetStep, matchesOriginal: matchesOriginal);
}

void main() {
  test('search for a graze-then-later-exit scenario', () {
    for (final count in [2, 3, 4]) {
      for (var seed = 1; seed <= 40; seed++) {
        for (final mix in [0.9, 0.8, 0.7, 0.6, 0.95]) {
          final r = tryScenario(count, seed, mix);
          if (r != null && r.resetStep != null && r.hitStep <= 10 && r.resetStep! > 20) {
            print('FOUND: count=$count seed=$seed mix=$mix hitStep=${r.hitStep} resetStep=${r.resetStep} matchesOriginal=${r.matchesOriginal}');
          }
        }
      }
    }
    print('search done');
  });
}
