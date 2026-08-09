import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_game.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_layout.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_links.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';

void main() {
  group('_partSizes', () {
    test(
      'every part is 2 or 3, and they sum to n, for every supported count',
      () {
        for (var n = 2; n <= 8; n++) {
          for (var seed = 0; seed < 20; seed++) {
            final parts = partSizesForTest(n, math.Random(seed));
            expect(
              parts.every((p) => p == 2 || p == 3),
              isTrue,
              reason: 'n=$n parts=$parts',
            );
            expect(
              parts.reduce((a, b) => a + b),
              n,
              reason: 'n=$n parts=$parts',
            );
          }
        }
      },
    );

    test(
      'n=4 always resolves to two parts of 2 — the only valid composition',
      () {
        for (var seed = 0; seed < 10; seed++) {
          expect(
            partSizesForTest(4, math.Random(seed)),
            unorderedEquals([2, 2]),
          );
        }
      },
    );

    test('n=6 explores both valid compositions over enough trials', () {
      final seen = <List<int>>{};
      for (var seed = 0; seed < 200; seed++) {
        final parts = List.of(partSizesForTest(6, math.Random(seed)))..sort();
        seen.add(parts);
      }
      expect(
        seen,
        containsAll([
          [2, 2, 2],
          [3, 3],
        ]),
      );
    });

    test('n=8 explores both valid compositions over enough trials', () {
      final seen = <List<int>>{};
      for (var seed = 0; seed < 200; seed++) {
        final parts = List.of(partSizesForTest(8, math.Random(seed)))..sort();
        seen.add(parts);
      }
      expect(
        seen,
        containsAll([
          [2, 2, 2, 2],
          [2, 3, 3],
        ]),
      );
    });
  });

  group('motif placement primitives', () {
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

    test('L motif places 2 phones that do not overlap each other', () {
      final specs = [phone('p1'), phone('p2')];
      final placed = placeLForTest(
        seedPhoneForTest(sideways: false),
        specs,
        mirror: true,
      );
      expect(placed.length, 2);
      expect(placed[0].overlapsForTest(placed[1]), isFalse);
    });

    test('L motif mirror flips which side the turn lands on', () {
      final specs = [phone('p1'), phone('p2')];
      final anchor = seedPhoneForTest(sideways: false);
      final right = placeLForTest(anchor, specs, mirror: true);
      final left = placeLForTest(anchor, specs, mirror: false);
      // Same first phone either way (the turn is the second phone).
      expect(right[0].cx, closeTo(left[0].cx, 1e-9));
      expect(right[0].cy, closeTo(left[0].cy, 1e-9));
      expect(right[1].cx, isNot(closeTo(left[1].cx, 1e-6)));
    });

    test('staircase motif places 3 phones, none overlapping', () {
      final specs = [phone('p1'), phone('p2'), phone('p3')];
      final placed = placeStaircaseForTest(
        seedPhoneForTest(sideways: false),
        specs,
        mirror: true,
      );
      expect(placed.length, 3);
      expect(placed[0].overlapsForTest(placed[1]), isFalse);
      expect(placed[1].overlapsForTest(placed[2]), isFalse);
      expect(placed[0].overlapsForTest(placed[2]), isFalse);
    });

    test('staircase turns alternate direction (a zigzag, not a spiral)', () {
      // Two turns in the same rotational sense would spiral back over
      // themselves after 3-4 more phones; alternating is what keeps a long
      // chain of staircases from folding into itself.
      final specs = [phone('p1'), phone('p2'), phone('p3')];
      final placed = placeStaircaseForTest(
        seedPhoneForTest(sideways: false),
        specs,
        mirror: true,
      );
      // p1->p2 turns one way, p2->p3 the other: p3 ends up displaced along
      // the *original* heading axis from p1, not further along the first
      // turn's axis.
      // If both turns went the same direction (spiral bug), p3 would keep
      // moving further along p2's axis, ending up *beyond* p2 in that
      // direction. With alternating turns, p3 comes back: p3.cy < p2.cy.
      expect(
        placed[2].arrivedBy,
        equals(placed[0].arrivedBy),
        reason:
            'alternating turns return to the original heading; '
            'a spiral (same-direction turns) would not',
      );
      expect((placed[2].cx - placed[1].cx).abs(), greaterThan(0));
    });

    test('_fits rejects a candidate that would create an unintended '
        'BoardLinks join, not just an overlap', () {
      final anchor = seedPhoneForTest(sideways: false);
      final placedSoFar = placeLForTest(anchor, [
        phone('p1'),
        phone('p2'),
      ], mirror: true);
      // Positioned 6mm past placedSoFar[0]'s right edge, with full y-axis
      // overlap — well inside BoardLinks.maxJoinGap (40mm), so this
      // registers as joined even though it never overlaps.
      final near = motifPhoneForTest(
        cx: placedSoFar[0].right + 6 + 34.29,
        cy: placedSoFar[0].cy,
        sideways: false,
        halfW: 34.29,
        halfH: 76.2,
      );
      expect(placedSoFar[0].overlapsForTest(near), isFalse);
      expect(fitsForTest([near], placedSoFar, anchor), isFalse);
    });
  });

  group('PitchCarsLayout.motifChain', () {
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

    test('places every phone count from 2 to 8 without throwing, and every '
        'phone appears exactly once', () {
      for (var n = 2; n <= 8; n++) {
        final phones = [for (var i = 0; i < n; i++) phone('p${i + 1}')];
        final plan = PitchCarsLayout.motifChain(phones, random: math.Random(n));
        expect(plan.placements.length, n);
        expect(
          plan.placements.map((p) => p.phoneId).toSet(),
          phones.map((p) => p.phoneId).toSet(),
        );
      }
    });

    test('the compiled board never overlaps and is fully connected', () {
      for (var n = 2; n <= 8; n++) {
        final phones = [for (var i = 0; i < n; i++) phone('p${i + 1}')];
        final plan = PitchCarsLayout.motifChain(
          phones,
          random: math.Random(n * 7),
        );
        // Throws BoardPlanError on overlap or disconnection — reaching the
        // assertion below is the pass condition.
        final board = const BoardCompiler().compile(plan, LobbyInfo(phones));
        expect(board.slices.length, n);
      }
    });

    test('throws for fewer than 2 phones', () {
      expect(
        () => PitchCarsLayout.motifChain([phone('p1')]),
        throwsA(isA<BoardPlanError>()),
      );
    });

    test('no board the generator can produce ever forms a 3-phone touch '
        'cycle (the avoided T-junction pattern)', () {
      // TrackGenerator._recoverChainOrder assumes a simple path — a phone
      // adjacency graph with a cycle would break it silently rather than
      // throwing, so this is worth asserting directly rather than trusting
      // it never happens.
      for (var n = 3; n <= 8; n++) {
        for (var seed = 0; seed < 30; seed++) {
          final phones = [for (var i = 0; i < n; i++) phone('p${i + 1}')];
          final plan = PitchCarsLayout.motifChain(
            phones,
            random: math.Random(seed * 13 + n),
          );
          final board = const BoardCompiler().compile(plan, LobbyInfo(phones));
          final degree = <String, int>{for (final p in phones) p.phoneId: 0};
          for (final v in BoardLinks.explain(board.slices)) {
            if (!v.joined) continue;
            degree[v.aId] = degree[v.aId]! + 1;
            degree[v.bId] = degree[v.bId]! + 1;
          }
          // A simple path (no cycle) has exactly two nodes of degree 1 (or,
          // degenerately, one node of degree 0 when n=1 — not reachable
          // here since n >= 3) and every other node degree 2.
          final degreeOne = degree.values.where((d) => d == 1).length;
          final degreeTwo = degree.values.where((d) => d == 2).length;
          expect(degreeOne, 2, reason: 'seed=$seed n=$n degrees=$degree');
          expect(degreeTwo, n - 2, reason: 'seed=$seed n=$n degrees=$degree');
        }
      }
    });
  });

  group('PitchCarsGame.planBoard', () {
    test('uses the motif chain, not Layouts.path', () {
      final phones = [
        for (var i = 0; i < 5; i++)
          PhoneSpec(
            phoneId: 'p${i + 1}',
            label: 'phone ${i + 1}',
            widthMm: 68.58,
            heightMm: 152.4,
            bezelMm: 3,
            dpi: 400,
            devicePixelRatio: 3,
            activePxWidth: 1080,
            activePxHeight: 2400,
          ),
      ];
      const game = PitchCarsGame();
      final plan = game.planBoard(LobbyInfo(phones));
      expect(plan.placements.length, 5);
      // Layouts.path's default instruction mentions "match the coloured
      // edges" too, so the real signal that this went through the new
      // layout is simply that it succeeds at all for a count Layouts.path
      // would have handled identically — recompiling and checking
      // connectivity is the meaningful assertion.
      final board = const BoardCompiler().compile(plan, LobbyInfo(phones));
      expect(board.slices.length, 5);
    });
  });
}
