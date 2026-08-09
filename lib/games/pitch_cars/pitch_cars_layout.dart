import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A partition of [n] into parts of size 2 or 3, in random order.
///
/// Every count from 2 has at least one such partition (2 = [2], 3 = [3],
/// and every larger n by induction), so this never returns an empty list
/// for `n >= 2`. When more than one partition exists (e.g. n=6: three 2s,
/// or two 3s), one is picked uniformly at random.
List<int> _partSizes(int n, math.Random rng) {
  final options = <List<int>>[];
  for (var threes = 0; threes * 3 <= n; threes++) {
    final remainder = n - threes * 3;
    if (remainder % 2 == 0) {
      final twos = remainder ~/ 2;
      options.add([
        ...List.filled(twos, 2),
        ...List.filled(threes, 3),
      ]);
    }
  }
  final chosen = List.of(options[rng.nextInt(options.length)]);
  chosen.shuffle(rng);
  return chosen;
}

/// Test-only access to [_partSizes] — kept private otherwise, since nothing
/// outside this file needs a partition on its own.
@visibleForTesting
List<int> partSizesForTest(int n, math.Random rng) => _partSizes(n, rng);
