import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/echo/echo_config.dart';
import 'package:multiscreen_slingshot/games/echo/echo_game.dart';
import 'package:multiscreen_slingshot/games/echo/echo_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A game with no physics and no seam, on a ring — the same shape of board as
/// Hot Potato, driven the same headless way.
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

({EchoSim sim, BoardLayout board, Scoreboard scores}) start(
  int count, {
  int seed = 1,
}) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = EchoGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = EchoSim(board.contextFor(scores), random: math.Random(seed));
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

/// Steps the sim through however much of the reveal it takes to reach recall.
void stepThroughReveal(EchoSim sim) {
  for (var i = 0; i < PlatformConfig.simHz * 20; i++) {
    sim.step(1 / PlatformConfig.simHz);
    if (sim.sharedState['phase'] == EchoPhase.recall) return;
  }
  fail('reveal never finished');
}

void tap(EchoSim sim, BoardLayout board, String phoneId) {
  final me = board.forPhone(phoneId)!;
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: me.worldCenterX,
    worldY: me.worldCenterY,
    phase: TouchPhase.down,
  ));
}

/// Recalls the whole current sequence correctly, in order.
void recallCorrectly(EchoSim sim, BoardLayout board) {
  final order = List.of(sim.sequence);
  for (final id in order) {
    tap(sim, board, id);
  }
}

void main() {
  group('a level', () {
    test('needs at least three phones, like the ring it stands on', () {
      expect(const EchoGame().manifest.smallestTable, 3);
      expect(const EchoGame().manifest.fits(2), isFalse);
      expect(const EchoGame().manifest.fits(3), isTrue);
    });

    test('starts in reveal, showing every active phone once', () {
      final started = start(4);
      final sim = started.sim;
      expect(sim.sharedState['phase'], EchoPhase.reveal);
      expect(sim.sequence, hasLength(4));
      final orbOwners = sim.entities.map((e) => e.id.replaceFirst('orb_', ''));
      expect(sim.sequence.toSet(), orbOwners.toSet());
    });

    test('lights exactly one seat at a time, moving through the sequence',
        () {
      final started = start(4);
      final sim = started.sim;

      final seen = <String>[];
      for (var i = 0; i < PlatformConfig.simHz * 20; i++) {
        sim.step(1 / PlatformConfig.simHz);
        final lit = sim.sharedState['litSeat'];
        if (lit is String && (seen.isEmpty || seen.last != lit)) {
          seen.add(lit);
        }
        if (sim.sharedState['phase'] == EchoPhase.recall) break;
      }
      expect(seen, sim.sequence);
    });

    test('moves to recall once every seat has been shown', () {
      final started = start(3);
      stepThroughReveal(started.sim);
      expect(started.sim.sharedState['phase'], EchoPhase.recall);
      expect(started.sim.sharedState['litSeat'], isNull);
    });
  });

  group('recalling it', () {
    test('a fully correct recall advances the round and starts a new one',
        () {
      final started = start(4);
      final sim = started.sim;
      final board = started.board;

      stepThroughReveal(sim);
      final firstSequence = List.of(sim.sequence);
      recallCorrectly(sim, board);

      expect(sim.round, 2);
      expect(sim.sharedState['phase'], EchoPhase.reveal);
      expect(sim.sequence, hasLength(4));
      // A fresh shuffle — vanishingly unlikely to land on the same order
      // twice in a row for four phones, and this seed does not.
      expect(sim.sequence, isNot(equals(firstSequence)));
      expect(sim.outcome, isNull);
    });

    test('a wrong tap eliminates the tapper, not the phone whose turn it was',
        () {
      final started = start(4);
      final sim = started.sim;
      final board = started.board;

      stepThroughReveal(sim);
      final expected = sim.sequence.first;
      final wrongTapper =
          sim.sequence.firstWhere((id) => id != expected);

      tap(sim, board, wrongTapper);

      expect((sim.sharedState['eliminated'] as List).single, wrongTapper);
      expect(sim.outcome, isNull, reason: 'four in, one out, still a game');
    });

    test('an eliminated phone cannot touch its way back in', () {
      final started = start(4);
      final sim = started.sim;
      final board = started.board;

      stepThroughReveal(sim);
      final wrongTapper =
          sim.sequence.firstWhere((id) => id != sim.sequence.first);
      tap(sim, board, wrongTapper);

      // The level restarted for the remaining three, without the loser.
      stepThroughReveal(sim);
      expect(sim.sequence, isNot(contains(wrongTapper)));

      // A touch from the sidelines does nothing at all.
      tap(sim, board, wrongTapper);
      expect(sim.sharedState['phase'], EchoPhase.recall);
      expect(sim.sharedState['recallIndex'], 0);
    });

    test('down to one active phone, that phone wins outright', () {
      final started = start(3);
      final sim = started.sim;
      final board = started.board;

      // Eliminate two of the three, one level at a time.
      for (var i = 0; i < 2; i++) {
        stepThroughReveal(sim);
        final expected = sim.sequence.first;
        final wrongTapper = sim.sequence.firstWhere((id) => id != expected);
        tap(sim, board, wrongTapper);
      }

      final outcome = sim.outcome;
      expect(outcome, isNotNull);
      expect(outcome!.kind, OutcomeKind.contest);
      expect(outcome.winners, hasLength(1));
      expect((sim.sharedState['eliminated'] as List), hasLength(2));
      expect(sim.sharedState['eliminated'],
          isNot(contains(outcome.winners!.first)));

      // Polled repeatedly, as the platform does — always the same verdict.
      expect(identical(sim.outcome, outcome), isTrue);
    });

    test('once there is a winner, nothing moves the game on any further', () {
      final started = start(3);
      final sim = started.sim;
      final board = started.board;

      for (var i = 0; i < 2; i++) {
        stepThroughReveal(sim);
        final expected = sim.sequence.first;
        final wrongTapper = sim.sequence.firstWhere((id) => id != expected);
        tap(sim, board, wrongTapper);
      }
      final winner = sim.outcome!.winners!.single;

      final before = sim.sharedState['round'];
      sim.step(1 / PlatformConfig.simHz);
      tap(sim, board, winner);
      expect(sim.sharedState['round'], before);
    });
  });

  group('scoring', () {
    test('an eliminated phone banks points for the rounds it survived', () {
      final started = start(4);
      final sim = started.sim;
      final board = started.board;
      final scores = started.scores;

      stepThroughReveal(sim);
      final expected = sim.sequence.first;
      final wrongTapper = sim.sequence.firstWhere((id) => id != expected);
      tap(sim, board, wrongTapper);

      expect(scores[wrongTapper], EchoConfig.pointsPerRoundSurvived * 1);
    });

    test('the last phone standing collects the winner bonus', () {
      final started = start(3);
      final sim = started.sim;
      final board = started.board;
      final scores = started.scores;

      for (var i = 0; i < 2; i++) {
        stepThroughReveal(sim);
        final expected = sim.sequence.first;
        final wrongTapper = sim.sequence.firstWhere((id) => id != expected);
        tap(sim, board, wrongTapper);
      }
      final winner = sim.outcome!.winners!.single;
      expect(scores[winner], greaterThanOrEqualTo(EchoConfig.winnerBonus));
    });
  });

  test('reset puts a fresh round one back and clears the eliminated list',
      () {
    final started = start(4);
    final sim = started.sim;
    final board = started.board;

    // One clean level to move the round on, then a mistake to populate the
    // eliminated list — both are things reset has to undo.
    stepThroughReveal(sim);
    recallCorrectly(sim, board);
    expect(sim.round, greaterThan(1));

    stepThroughReveal(sim);
    final expected = sim.sequence.first;
    final wrongTapper = sim.sequence.firstWhere((id) => id != expected);
    tap(sim, board, wrongTapper);
    expect(sim.sharedState['eliminated'], isNotEmpty);

    sim.reset();

    expect(sim.round, 1);
    expect(sim.outcome, isNull);
    expect(sim.sharedState['eliminated'], isEmpty);
    expect(sim.sequence, hasLength(4));
  });
}
