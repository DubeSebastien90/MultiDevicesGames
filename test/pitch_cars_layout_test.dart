import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_layout.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';

void main() {
  group('_partSizes', () {
    test('every part is 2 or 3, and they sum to n, for every supported count',
        () {
      for (var n = 2; n <= 8; n++) {
        for (var seed = 0; seed < 20; seed++) {
          final parts = partSizesForTest(n, math.Random(seed));
          expect(parts.every((p) => p == 2 || p == 3), isTrue,
              reason: 'n=$n parts=$parts');
          expect(parts.reduce((a, b) => a + b), n, reason: 'n=$n parts=$parts');
        }
      }
    });

    test('n=4 always resolves to two parts of 2 — the only valid composition',
        () {
      for (var seed = 0; seed < 10; seed++) {
        expect(partSizesForTest(4, math.Random(seed)), unorderedEquals([2, 2]));
      }
    });

    test('n=6 explores both valid compositions over enough trials', () {
      final seen = <List<int>>{};
      for (var seed = 0; seed < 200; seed++) {
        final parts = List.of(partSizesForTest(6, math.Random(seed)))..sort();
        seen.add(parts);
      }
      expect(seen, containsAll([
        [2, 2, 2],
        [3, 3],
      ]));
    });

    test('n=8 explores both valid compositions over enough trials', () {
      final seen = <List<int>>{};
      for (var seed = 0; seed < 200; seed++) {
        final parts = List.of(partSizesForTest(8, math.Random(seed)))..sort();
        seen.add(parts);
      }
      expect(seen, containsAll([
        [2, 2, 2, 2],
        [2, 3, 3],
      ]));
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
      expect(placed[2].cy, lessThan(placed[1].cy),
          reason: 'staircase must alternate turns, not spiral');
      expect((placed[2].cx - placed[1].cx).abs(), greaterThan(0));
    });
  });
}
