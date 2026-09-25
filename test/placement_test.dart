import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

Scoreboard board(int n) {
  final scores = Scoreboard();
  for (var i = 1; i <= n; i++) {
    scores.register('p$i', 'phone $i');
  }
  return scores;
}

List<Set<String>> inOrder(int n) => [
  for (var i = 1; i <= n; i++) {'p$i'},
];

void main() {
  group('the placement ladder', () {
    test('first takes 100, last takes nothing, evenly spaced between', () {
      expect(Scoreboard.placements(inOrder(4)), {
        'p1': 100,
        'p2': 67,
        'p3': 33,
        'p4': 0,
      });
      expect(Scoreboard.placements(inOrder(2)), {'p1': 100, 'p2': 0});
      expect(Scoreboard.placements(inOrder(8)).values.toList(), [
        100, 86, 71, 57, 43, 29, 14, 0, //
      ]);
    });

    test('is worth fifty a head at every table size', () {
      for (var n = 2; n <= 8; n++) {
        final total = Scoreboard.placements(
          inOrder(n),
        ).values.fold<int>(0, (a, b) => a + b);
        expect(total, closeTo(50 * n, 1), reason: 'at $n players');
      }
    });

    test('a tie shares the places it takes up', () {
      final paid = Scoreboard.placements([
        {'p1', 'p2'},
        {'p3'},
        {'p4'},
      ]);
      expect(paid['p1'], 83);
      expect(paid['p2'], 83);
      expect(paid['p3'], 33);
      expect(paid['p4'], 0);
    });

    test('a dead heat is half the prize each', () {
      final paid = Scoreboard.placements([
        {'p1', 'p2', 'p3', 'p4'},
      ]);
      expect(paid.values.toSet(), {50});
    });

    test('max shortens the ladder', () {
      expect(Scoreboard.placements(inOrder(4), max: 80), {
        'p1': 80,
        'p2': 53,
        'p3': 27,
        'p4': 0,
      });
    });

    test('a lone player has nobody to beat', () {
      expect(Scoreboard.placements(inOrder(1)), {'p1': 0});
    });

    test('awardPlacements pays the scoreboard what placements says', () {
      final scores = board(4)..award('p4', 12);
      final paid = scores.awardPlacements(inOrder(4));
      expect(paid, Scoreboard.placements(inOrder(4)));
      expect(scores['p1'], 100);
      expect(scores['p4'], 12, reason: 'last adds nothing to what was there');
    });

    test('tiersBy ranks highest first and groups equal values', () {
      expect(Scoreboard.tiersBy({'a': 3, 'b': 7, 'c': 3, 'd': 0}), [
        {'b'},
        {'a', 'c'},
        {'d'},
      ]);
    });
  });
}
