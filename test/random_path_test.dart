import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/random_path/random_path_config.dart';
import 'package:multiscreen_slingshot/games/random_path/random_path_game.dart';
import 'package:multiscreen_slingshot/games/random_path/random_path_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_links.dart';
import 'package:multiscreen_slingshot/sdk/layout/layouts.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A board laid out differently every round, and no game on top of it.
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

List<PhoneSpec> phones(int count) =>
    [for (var i = 0; i < count; i++) phone('p${i + 1}')];

BoardLayout pathBoard(int count, {int? seed}) {
  final lobby = LobbyInfo(phones(count));
  return const BoardCompiler().compile(
    Layouts.path(lobby.phones, random: seed == null ? null : math.Random(seed)),
    lobby,
  );
}

void main() {
  group('the path', () {
    test('compiles for every table size, whatever it rolls', () {
      // The compiler is the real judge here: it refuses overlapping screens and
      // strays that touch nothing. Run it often enough that a rare unlucky
      // shape cannot pass unnoticed.
      for (var count = 2; count <= 7; count++) {
        for (var seed = 0; seed < 40; seed++) {
          final board = pathBoard(count, seed: seed);
          expect(board.slices, hasLength(count),
              reason: '$count phones, seed $seed');
        }
      }
    });

    test('no two screens share any space', () {
      for (var seed = 0; seed < 40; seed++) {
        final board = pathBoard(5, seed: seed);
        for (var i = 0; i < board.slices.length; i++) {
          for (var j = i + 1; j < board.slices.length; j++) {
            final a = board.slices[i].viewport;
            final b = board.slices[j].viewport;
            final overlaps = a.left < b.right - 0.01 &&
                b.left < a.right - 0.01 &&
                a.top < b.bottom - 0.01 &&
                b.top < a.bottom - 0.01;
            expect(overlaps, isFalse, reason: 'seed $seed: screens on top');
          }
        }
      }
    });

    test('is a chain: every phone meets only the one before it', () {
      // The guarantee Pitch Cars reads the board with — it walks the phones end
      // to end to lay a track along them. A path that wound back and brushed an
      // earlier phone made a fork, and a walk through a fork picks one way and
      // drops the rest: on a table that is somebody watching a blank screen for
      // the whole round.
      for (var count = 2; count <= 8; count++) {
        for (var seed = 0; seed < 60; seed++) {
          final board = pathBoard(count, seed: seed);

          final neighbours = <String, int>{};
          for (final link in board.links) {
            if (link.partnerId == null) continue;
            neighbours[link.phoneId] = (neighbours[link.phoneId] ?? 0) + 1;
          }

          for (final entry in neighbours.entries) {
            expect(entry.value, lessThanOrEqualTo(2),
                reason: '$count phones, seed $seed: ${entry.key} has '
                    '${entry.value} neighbours — the path forked');
          }

          // And it is one chain, not two: exactly two ends, or none at all
          // when there are only two phones and both are ends.
          final ends =
              neighbours.entries.where((e) => e.value == 1).length;
          expect(ends, count == 1 ? 0 : 2,
              reason: '$count phones, seed $seed: the path is in pieces');
        }
      }
    });

    test('a path that paints itself into a corner is walked again', () {
      // Winding into a dead end is not a repairable mistake — it was made
      // several phones ago — so the whole layout is rolled again rather than
      // patched. What must never happen is giving up on a table that a
      // different roll would have placed.
      for (var count = 2; count <= 8; count++) {
        for (var seed = 0; seed < 60; seed++) {
          expect(() => pathBoard(count, seed: seed), returnsNormally,
              reason: '$count phones, seed $seed: gave up');
        }
      }
    });

    test('turns, rather than growing in a straight line', () {
      // A path that never turns is a row, and a row is already a helper.
      var turned = 0;
      for (var seed = 0; seed < 30; seed++) {
        final board = pathBoard(5, seed: seed);
        final angles = board.slices.map((s) => s.screen.isTurned).toSet();
        if (angles.length > 1) turned++;
      }
      expect(turned, greaterThan(20),
          reason: 'hardly any board mixed upright and sideways phones');
    });

    test('is a different shape every round', () {
      // The point of the thing: nobody can lay this out from memory.
      String shapeOf(BoardLayout board) => board.slices
          .map((s) => '${s.screen.centerX.toStringAsFixed(0)},'
              '${s.screen.centerY.toStringAsFixed(0)},'
              '${s.screen.turnRadians.toStringAsFixed(2)}')
          .join('|');

      final shapes = {
        for (var seed = 0; seed < 20; seed++) shapeOf(pathBoard(4, seed: seed)),
      };
      expect(shapes.length, greaterThan(15));
    });

    test('the same seed lays out the same board', () {
      // Not for the game — for anyone trying to reproduce a report about one.
      final a = pathBoard(5, seed: 12);
      final b = pathBoard(5, seed: 12);
      for (var i = 0; i < a.slices.length; i++) {
        expect(a.slices[i].screen.centerX,
            closeTo(b.slices[i].screen.centerX, 1e-9));
        expect(a.slices[i].screen.centerY,
            closeTo(b.slices[i].screen.centerY, 1e-9));
      }
    });
  });

  group('the game', () {
    test('takes two phones and up', () {
      const game = RandomPathGame();
      expect(game.manifest.fits(2), isTrue);
      expect(game.manifest.fits(1), isFalse);
      expect(game.manifest.fits(6), isTrue);
    });

    test('rolls a new board each time it is asked', () {
      // The randomness has to be in the game's own `planBoard`, not only in the
      // helper: the platform calls it once per round, and that call is where
      // the shape for that round is settled.
      const game = RandomPathGame();
      final lobby = LobbyInfo(phones(4));

      final shapes = {
        for (var i = 0; i < 12; i++)
          game
              .planBoard(lobby)
              .placements
              .map((p) => '${p.xMm.toStringAsFixed(0)},'
                  '${p.yMm.toStringAsFixed(0)},${p.turnDeg}')
              .join('|'),
      };
      expect(shapes.length, greaterThan(6),
          reason: 'the same board came back over and over');
    });
  });

  group('the connectors', () {
    test('every phone is joined to something, in a paired colour', () {
      // The question this game exists to answer: does the existing connector
      // rule cope with a board nobody designed? It is derived from the compiled
      // geometry alone, so it should — and this is what proves it.
      for (var seed = 0; seed < 30; seed++) {
        final board = pathBoard(5, seed: seed);

        for (final slice in board.slices) {
          final mine =
              board.links.where((l) => l.phoneId == slice.phoneId).toList();
          expect(mine, isNotEmpty,
              reason: 'seed $seed: ${slice.phoneId} has no stripe at all');
          expect(mine.every((l) => l.isJoin), isTrue,
              reason: 'seed $seed: ${slice.phoneId} fell back to an inward '
                  'stripe, which means it is touching nothing');
        }

        // Both halves of every join agree on the colour.
        for (final link in board.links) {
          final other = board.links.singleWhere(
            (l) => l.phoneId == link.partnerId && l.partnerId == link.phoneId,
          );
          expect(other.colorIndex, link.colorIndex, reason: 'seed $seed');
        }
      }
    });

    test('no join ever runs the whole length of a phone', () {
      // The rule the whole layout is built around. Two phones flush side by
      // side share every millimetre of one edge each, and the pair stops
      // reading as two steps of a path: it is one fat screen with a bar down
      // the middle that says nothing about which way to go next.
      for (var seed = 0; seed < 60; seed++) {
        final board = pathBoard(5, seed: seed);

        for (final link in board.links) {
          final me = board.forPhone(link.phoneId)!.viewport;
          final them = board.forPhone(link.partnerId!)!.viewport;
          final vertical = link.x1 == link.x2;

          final shared = vertical
              ? math.min(me.bottom, them.bottom) - math.max(me.top, them.top)
              : math.min(me.right, them.right) - math.max(me.left, them.left);
          final longest = math.max(
            math.max(me.width, me.height),
            math.max(them.width, them.height),
          );

          expect(shared, lessThan(longest - 0.05),
              reason: 'seed $seed: ${link.phoneId} and ${link.partnerId} are '
                  'joined along a whole long edge');
        }
      }
    });

    test('each phone is laid on a full short edge, or half a long one', () {
      // The seven ways come out as two shapes of join, and nothing else:
      //
      //  - laid end-on or turned against a flank: the *whole* short edge of one
      //    of the two phones, corner to corner;
      //  - laid alongside: half a long edge, because flush would be the whole
      //    of it and that is the one thing forbidden.
      //
      // A winding path also brushes past phones it was not attached to, and
      // those extra joins take whatever the geometry gives them — real
      // connections, correctly drawn, just not the deliberate one. So each
      // phone must have at least one join of a deliberate shape.
      for (var seed = 0; seed < 40; seed++) {
        final board = pathBoard(5, seed: seed);

        for (final slice in board.slices) {
          final deliberate =
              board.links.where((l) => l.phoneId == slice.phoneId).where((link) {
            final me = board.forPhone(link.phoneId)!.viewport;
            final them = board.forPhone(link.partnerId!)!.viewport;
            final vertical = link.x1 == link.x2;

            final shared = vertical
                ? math.min(me.bottom, them.bottom) - math.max(me.top, them.top)
                : math.min(me.right, them.right) - math.max(me.left, them.left);

            final shortMe = math.min(me.width, me.height);
            final shortThem = math.min(them.width, them.height);
            final halfLong = math.max(me.width, me.height) / 2;

            return (shared - shortMe).abs() < 0.05 ||
                (shared - shortThem).abs() < 0.05 ||
                (shared - halfLong).abs() < 0.05;
          });

          expect(deliberate, isNotEmpty,
              reason: 'seed $seed: ${slice.phoneId} is joined to its '
                  'neighbours in no shape the seven ways can produce');
        }
      }
    });

    test('a stripe covers the shared run and no more', () {
      // A portrait phone against a sideways one shares only part of an edge —
      // the drawing has to mark that part, because it is the length there is to
      // line up.
      for (var seed = 0; seed < 30; seed++) {
        final board = pathBoard(4, seed: seed);

        for (final link in board.links) {
          final me = board.forPhone(link.phoneId)!.viewport;
          final them = board.forPhone(link.partnerId!)!.viewport;
          final length = math.sqrt(math.pow(link.x2 - link.x1, 2) +
              math.pow(link.y2 - link.y1, 2));

          final shared = link.x1 == link.x2
              ? math.min(me.bottom, them.bottom) - math.max(me.top, them.top)
              : math.min(me.right, them.right) - math.max(me.left, them.left);

          expect(length, closeTo(shared, 1e-6),
              reason: 'seed $seed: the stripe is not the shared run');
          expect(length, greaterThan(0));
        }
      }
    });

    test('both ends of a join are the same length', () {
      for (var seed = 0; seed < 20; seed++) {
        final board = pathBoard(5, seed: seed);
        double lengthOf(EdgeMarker m) => math.sqrt(
            math.pow(m.x2 - m.x1, 2) + math.pow(m.y2 - m.y1, 2));

        for (final link in board.links) {
          final other = board.links.singleWhere(
            (l) => l.phoneId == link.partnerId && l.partnerId == link.phoneId,
          );
          expect(lengthOf(other), closeTo(lengthOf(link), 1e-6),
              reason: 'seed $seed');
        }
      }
    });
  });

  group('the round', () {
    ({RandomPathSim sim, Scoreboard scores}) start(int count) {
      final lobby = LobbyInfo(phones(count));
      final scores = Scoreboard();
      for (final p in lobby.phones) {
        scores.register(p.phoneId, p.label);
      }
      final board =
          const BoardCompiler().compile(Layouts.path(lobby.phones), lobby);
      return (
        sim: RandomPathSim(board.contextFor(scores)),
        scores: scores,
      );
    }

    test('everybody wins after five seconds', () {
      final started = start(3);

      for (var t = 0.0; t < RandomPathConfig.roundSeconds - 0.5; t += 1 / 60) {
        started.sim.step(1 / 60);
      }
      expect(started.sim.outcome, isNull, reason: 'ended early');

      for (var t = 0.0; t < 1; t += 1 / 60) {
        started.sim.step(1 / 60);
      }

      final outcome = started.sim.outcome!;
      expect(outcome.kind, OutcomeKind.shared);
      expect(outcome.won, isTrue, reason: 'the whole table wins this one');
    });

    test('a replayed round starts over', () {
      final started = start(2);
      for (var t = 0.0; t < RandomPathConfig.roundSeconds + 1; t += 1 / 60) {
        started.sim.step(1 / 60);
      }
      expect(started.sim.outcome, isNotNull);

      started.sim.reset();
      expect(started.sim.outcome, isNull);
    });
  });
}
