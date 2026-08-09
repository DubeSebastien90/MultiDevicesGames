import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_layout.dart';

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
}
