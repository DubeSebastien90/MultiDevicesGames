import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/copycat/copycat_config.dart';
import 'package:multiscreen_slingshot/games/copycat/copycat_game.dart';
import 'package:multiscreen_slingshot/games/copycat/copycat_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A memory game with no physics and no entities at all — like Reaction Time,
/// it is driven entirely by `sharedState`.
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

({CopycatSim sim, BoardLayout board, Scoreboard scores}) start(
  int count, {
  math.Random? random,
}) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = CopycatGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = CopycatSim(board.contextFor(scores), random: random ?? math.Random(1));
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

/// A finger landing dead centre of [phoneId]'s own screen — a whole phone is
/// one key, so where on it does not matter.
void tapDown(CopycatSim sim, BoardLayout board, String phoneId) {
  final me = board.forPhone(phoneId)!;
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: me.worldCenterX,
    worldY: me.worldCenterY,
    phase: TouchPhase.down,
  ));
}

/// Steps the sim until the team is being asked to tap, or the round has
/// already ended.
void stepUntilInputPhase(CopycatSim sim) {
  var guard = 0;
  while (sim.sharedState['phase'] != 'input' && sim.outcome == null) {
    sim.step(1 / PlatformConfig.simHz);
    guard++;
    if (guard > PlatformConfig.simHz * 30) {
      throw StateError('never reached the input phase');
    }
  }
}

void main() {
  test('opens on a one-tile sequence, already playing back', () {
    final started = start(3);
    expect(started.sim.sequence, hasLength(1));
    expect(started.sim.sharedState['phase'], 'watch');
    expect(started.sim.sharedState['lit'], started.sim.sequence.single);
    expect(started.sim.sharedState['length'], 1);
    expect(started.sim.outcome, isNull);
  });

  test('the lit tile goes dark again once its beat is up', () {
    final started = start(3);
    expect(started.sim.sharedState['lit'], isNotNull);
    for (var i = 0; i < PlatformConfig.simHz; i++) {
      started.sim.step(1 / PlatformConfig.simHz);
    }
    expect(started.sim.sharedState['lit'], isNull);
  });

  test('replaying the sequence correctly grows it by one tile', () {
    final started = start(3);
    stepUntilInputPhase(started.sim);
    final first = started.sim.sequence.single;

    tapDown(started.sim, started.board, first);

    expect(started.sim.outcome, isNull);
    expect(started.sim.sequence, hasLength(2));
    expect(started.sim.sequence.first, first, reason: 'the old tile stays');
    expect(started.sim.sharedState['phase'], 'watch');
    expect(started.sim.sharedState['length'], 2);
  });

  test('a wrong tap loses the round for the whole table, once', () {
    final started = start(3);
    stepUntilInputPhase(started.sim);
    final expected = started.sim.sequence.single;
    final wrong = started.board.phones
        .map((p) => p.phoneId)
        .firstWhere((id) => id != expected);

    tapDown(started.sim, started.board, wrong);

    final outcome = started.sim.outcome;
    expect(outcome, isNotNull);
    expect(outcome!.kind, OutcomeKind.shared);
    expect(outcome.won, isFalse);

    // Latched: stepping past the loss must not replace the verdict, and a
    // second tap must not either.
    started.sim.step(1 / PlatformConfig.simHz);
    tapDown(started.sim, started.board, expected);
    expect(identical(started.sim.outcome, outcome), isTrue);
  });

  test('nobody tapping at all times the round out as a loss', () {
    final started = start(2);
    var guard = 0;
    while (started.sim.outcome == null) {
      started.sim.step(1 / PlatformConfig.simHz);
      guard++;
      if (guard > PlatformConfig.simHz * (CopycatConfig.roundSeconds + 5)) {
        throw StateError('the round never timed out');
      }
    }
    expect(started.sim.outcome!.won, isFalse);
  });

  test('replaying the full pattern wins it, and pays everybody once', () {
    final started = start(2, random: math.Random(7));

    var rounds = 0;
    while (started.sim.outcome == null) {
      stepUntilInputPhase(started.sim);
      if (started.sim.outcome != null) break;

      for (final tile in started.sim.sequence) {
        tapDown(started.sim, started.board, tile);
        if (started.sim.outcome != null) break;
      }

      rounds++;
      if (rounds > CopycatConfig.targetLength + 2) {
        throw StateError('the pattern never reached its target length');
      }
    }

    final outcome = started.sim.outcome!;
    expect(outcome.kind, OutcomeKind.shared);
    expect(outcome.won, isTrue);
    expect(started.sim.sequence, hasLength(CopycatConfig.targetLength));

    for (final p in started.board.phones) {
      expect(started.scores[p.phoneId], CopycatConfig.winBonus);
    }

    // Kept stepping well past the win; it must not keep paying out.
    for (var i = 0; i < PlatformConfig.simHz * 3; i++) {
      started.sim.step(1 / PlatformConfig.simHz);
    }
    for (final p in started.board.phones) {
      expect(started.scores[p.phoneId], CopycatConfig.winBonus);
    }
  });

  test('reset puts the pattern back to a single fresh tile', () {
    final started = start(3);
    stepUntilInputPhase(started.sim);
    tapDown(started.sim, started.board, started.sim.sequence.single);
    expect(started.sim.sequence, hasLength(2));

    started.sim.reset();

    expect(started.sim.sequence, hasLength(1));
    expect(started.sim.sharedState['phase'], 'watch');
    expect(started.sim.outcome, isNull);
  });
}
