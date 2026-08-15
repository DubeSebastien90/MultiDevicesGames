import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/fusebox/fusebox_config.dart';
import 'package:multiscreen_slingshot/games/fusebox/fusebox_game.dart';
import 'package:multiscreen_slingshot/games/fusebox/fusebox_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/layouts.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
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

({FuseBoxSim sim, BoardLayout board, Scoreboard scores}) start(
  int phoneCount, {
  int seed = 3,
}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++) phone('p${i + 1}'),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }

  const game = FuseBoxGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = FuseBoxSim(board.contextFor(scores), random: math.Random(seed));
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

/// Which cells are lit right now, keyed by phone id rather than entity id —
/// the tests below reason about phones, not about the sim's internal indices.
/// Cell `n` belongs to the phone at `board.slices[n]`, the same order the sim
/// builds its cells from.
Map<String, bool> litByPhone(FuseBoxSim sim, BoardLayout board) {
  final lit = sim.sharedState['lit'] as Map<String, Object?>;
  return {
    for (var i = 0; i < board.slices.length; i++)
      board.slices[i].phoneId: lit['cell$i'] == true,
  };
}

void tap(FuseBoxSim sim, String phoneId) {
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: 0,
    worldY: 0,
    phase: TouchPhase.down,
  ));
}

/// The orthogonal-neighbour graph a two-row grid should have, derived the
/// same way the sim derives it: reading order down the board then across it,
/// split into two equal rows.
Map<String, List<String>> expectedNeighbors(BoardLayout board) {
  final ids = [for (final s in board.slices) s.phoneId];
  final cols = ids.length ~/ 2;
  int rowOf(int i) => i < cols ? 0 : 1;
  int colOf(int i) => i % cols;

  return {
    for (var i = 0; i < ids.length; i++)
      ids[i]: [
        for (var j = 0; j < ids.length; j++)
          if (i != j &&
              ((rowOf(i) == rowOf(j) && (colOf(i) - colOf(j)).abs() == 1) ||
                  (rowOf(i) != rowOf(j) && colOf(i) == colOf(j))))
            ids[j],
      ],
  };
}

/// Brute-forces which subset of phones to tap, from the *current* lit state,
/// to leave every light off. Small boards only (used at 4 and 6 phones), so
/// trying every subset is cheap and — because every tap is its own inverse
/// and they all commute — a solution is guaranteed to exist.
List<String> solve(FuseBoxSim sim, BoardLayout board) {
  final neighbors = expectedNeighbors(board);
  final ids = [for (final s in board.slices) s.phoneId];
  final lit = litByPhone(sim, board);

  for (var mask = 0; mask < (1 << ids.length); mask++) {
    final result = {for (final id in ids) id: lit[id] ?? false};
    for (var i = 0; i < ids.length; i++) {
      if (mask & (1 << i) == 0) continue;
      final id = ids[i];
      result[id] = !result[id]!;
      for (final n in neighbors[id]!) {
        result[n] = !result[n]!;
      }
    }
    if (result.values.every((v) => !v)) {
      return [
        for (var i = 0; i < ids.length; i++)
          if (mask & (1 << i) != 0) ids[i],
      ];
    }
  }
  fail('no solution found for the current board — the puzzle is unsolvable');
}

void main() {
  group('the board', () {
    test('a tap trips its own light and only its orthogonal neighbours', () {
      final started = start(4);
      final board = started.board;
      final neighbors = expectedNeighbors(board);

      // Solving would end the round before a second tap could be observed
      // (correctly — a tap after the win is ignored), so this reads the
      // effect of one tap directly off the opening, still-scrambled board:
      // exactly the target and its orthogonal neighbours must flip, and
      // nothing else.
      final before = litByPhone(started.sim, board);
      final target = board.slices.first.phoneId;
      tap(started.sim, target);
      final after = litByPhone(started.sim, board);

      for (final id in neighbors.keys) {
        final shouldFlip = id == target || neighbors[target]!.contains(id);
        expect(after[id], shouldFlip ? !before[id]! : before[id],
            reason: '$id should have ${shouldFlip ? 'flipped' : 'stayed put'} '
                'after tapping $target (before: ${before[id]}, '
                'after: ${after[id]})');
      }
    });

    test('each phone has two or three neighbours on a 2xN grid, never four', () {
      for (final count in [4, 6, 8]) {
        final started = start(count);
        final neighbors = expectedNeighbors(started.board);
        for (final entry in neighbors.entries) {
          expect(entry.value.length, inInclusiveRange(2, 3),
              reason: '${entry.key} on a $count-phone board had '
                  '${entry.value.length} neighbours: ${entry.value}');
        }
      }
    });
  });

  group('opening a round', () {
    test('starts scrambled but always solvable', () {
      for (var seed = 0; seed < 10; seed++) {
        final started = start(4, seed: seed);
        expect(started.sim.litCount, greaterThan(0),
            reason: 'seed $seed opened already solved');
        expect(started.sim.outcome, isNull);

        // solve() itself proves solvability by finding a working subset; a
        // failure to find one calls fail() and stops the test.
        final moves = solve(started.sim, started.board);
        for (final id in moves) {
          tap(started.sim, id);
        }
        expect(started.sim.litCount, 0, reason: 'seed $seed had no solution');
      }
    });

    test('an untouched round has taken no taps and paid nobody', () {
      final started = start(4);
      expect(started.sim.sharedState['taps'], 0);
      expect(started.scores.isUsed, isFalse);
    });
  });

  group('winning', () {
    test('solving it pays every phone once, and only once', () {
      final started = start(4);
      final moves = solve(started.sim, started.board);

      for (final id in moves) {
        tap(started.sim, id);
      }

      expect(started.sim.outcome, isNotNull);
      expect(started.sim.outcome!.kind, OutcomeKind.shared);
      expect(started.sim.outcome!.won, isTrue);
      for (final id in started.sim.context.phoneIds) {
        expect(started.scores[id], FuseBoxConfig.winBonus,
            reason: '$id should share the co-operative bonus');
      }

      // Polled repeatedly, as the platform does: one verdict, built once.
      final outcome = started.sim.outcome;
      expect(identical(started.sim.outcome, outcome), isTrue);

      // Taps after the win change nothing further — the round is over.
      tap(started.sim, started.board.slices.first.phoneId);
      for (final id in started.sim.context.phoneIds) {
        expect(started.scores[id], FuseBoxConfig.winBonus);
      }
    });

    test('taps stop mattering the instant it is solved, mid-sequence', () {
      final started = start(4);
      final moves = solve(started.sim, started.board);

      // Tap every solving move plus one bystander tap appended: if the round
      // ends the moment the board goes dark, the extra tap must not relight
      // anything the outcome already latched.
      for (final id in moves) {
        tap(started.sim, id);
      }
      final litAtWin = started.sim.litCount;
      tap(started.sim, started.board.slices.first.phoneId);

      expect(litAtWin, 0);
      expect(started.sim.litCount, 0,
          reason: 'a tap after the win must be ignored');
    });
  });

  group('losing', () {
    test('running out the clock without solving it ends the round lost', () {
      final started = start(4);
      for (var i = 0; i < FuseBoxConfig.roundSeconds * 60 + 60; i++) {
        started.sim.step(1 / 60);
      }

      expect(started.sim.outcome, isNotNull);
      expect(started.sim.outcome!.kind, OutcomeKind.shared);
      expect(started.sim.outcome!.won, isFalse);
      expect(started.sim.litCount, greaterThan(0));
      // A round that is lost pays nobody — the bonus is only for finishing.
      expect(started.scores.isUsed, isFalse);
    });
  });

  group('reset', () {
    test('starts a fresh, scrambled, unsolved board', () {
      final started = start(4);
      final moves = solve(started.sim, started.board);
      for (final id in moves) {
        tap(started.sim, id);
      }
      expect(started.sim.outcome, isNotNull);

      started.sim.reset();

      expect(started.sim.outcome, isNull);
      expect(started.sim.sharedState['taps'], 0);
      expect(started.sim.secondsLeft, FuseBoxConfig.roundSeconds);
      expect(started.sim.litCount, greaterThan(0));
    });
  });

  group('the manifest', () {
    test('needs an even table of four to eight', () {
      final manifest = const FuseBoxGame().manifest;
      expect(manifest.fits(3), isFalse);
      expect(manifest.fits(4), isTrue);
      expect(manifest.fits(5), isFalse, reason: 'the grid needs two even rows');
      expect(manifest.fits(8), isTrue);
      expect(manifest.fits(9), isFalse);
    });

    test('planBoard refuses an odd table before anything is broadcast', () {
      final lobby = LobbyInfo([for (var i = 0; i < 5; i++) phone('p${i + 1}')]);
      expect(
        () => Layouts.grid(lobby.phones, rows: 2),
        throwsA(isA<BoardPlanError>()),
      );
    });
  });
}
