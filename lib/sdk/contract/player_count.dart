import 'dart:math' as math;

/// Whether a game needs an odd or an even number of phones.
///
/// Teams want even; anything with a single odd-one-out — a hunter, a caller, a
/// judge — wants odd.
enum CountParity { any, odd, even }

extension CountParityCheck on CountParity {
  bool allows(int count) => switch (this) {
    CountParity.any => true,
    CountParity.odd => count.isOdd,
    CountParity.even => count.isEven,
  };

  String get phrase => switch (this) {
    CountParity.any => '',
    CountParity.odd => 'an odd number of',
    CountParity.even => 'an even number of',
  };
}

/// How many phones a game can actually be played with.
///
/// Three shapes, in order of how often you want them:
///
/// ```dart
/// PlayerCount.range(min: 3)                        // 3 or more
/// PlayerCount.range(min: 4, max: 8, parity: CountParity.even)
/// PlayerCount.exactly(2)                           // head to head
/// PlayerCount.anyOf([3, 5, 9])                     // when nothing else fits
/// ```
///
/// [anyOf] is the escape hatch, and it exists because a range plus a parity
/// still cannot say "three, five or nine". Reach for it last: a range says
/// *why* a game has limits, and a bare list of numbers says only that it does.
class PlayerCount {
  /// A span, optionally restricted to odd or even counts.
  const PlayerCount.range({
    required int min,
    int max = 8,
    this.parity = CountParity.any,
  }) : _min = min,
       _max = max,
       allowed = null;

  /// Exactly this many, no more and no fewer.
  const PlayerCount.exactly(int count)
    : _min = count,
      _max = count,
      parity = CountParity.any,
      allowed = null;

  /// An explicit list, for a game whose shape no range describes.
  const PlayerCount.anyOf(List<int> counts)
    : allowed = counts,
      _min = null,
      _max = null,
      parity = CountParity.any;

  final int? _min;
  final int? _max;

  final CountParity parity;

  /// Non-null only for [PlayerCount.anyOf], and then it is the whole answer.
  final List<int>? allowed;

  bool fits(int phones) {
    final list = allowed;
    if (list != null) return list.contains(phones);
    return phones >= _min! && phones <= _max! && parity.allows(phones);
  }

  /// The fewest phones this game can be played with — for sorting a catalogue
  /// and for telling a two-person table what they are missing.
  int get smallest {
    final list = allowed;
    if (list != null && list.isNotEmpty) return list.reduce(math.min);
    // A parity rule can push the real floor one above the stated minimum.
    for (var n = _min!; n <= _max!; n++) {
      if (parity.allows(n)) return n;
    }
    return _min;
  }

  int get largest {
    final list = allowed;
    if (list != null && list.isNotEmpty) return list.reduce(math.max);
    for (var n = _max!; n >= _min!; n--) {
      if (parity.allows(n)) return n;
    }
    return _max;
  }

  /// Every count that works, up to [ceiling]. Handy for a picker, and for
  /// tests that want to check the whole set rather than the endpoints.
  List<int> playableCounts({int ceiling = 8}) =>
      [for (var n = 1; n <= ceiling; n++) if (fits(n)) n];

  /// How to say it out loud, for the lobby: 'needs an odd number of phones,
  /// 3 to 7'.
  String describe() {
    final list = allowed;
    if (list != null) {
      if (list.isEmpty) return 'cannot be played';
      final sorted = List.of(list)..sort();
      if (sorted.length == 1) return 'needs exactly ${sorted.single} phones';
      final last = sorted.removeLast();
      return 'needs ${sorted.join(', ')} or $last phones';
    }

    if (_min == _max) return 'needs exactly $_min phones';

    final parityWord = parity.phrase;
    if (parityWord.isEmpty) {
      return _max! >= 8
          ? 'needs $_min+ phones'
          : 'needs $_min–$_max phones';
    }
    return 'needs $parityWord phones, $smallest to $largest';
  }

  @override
  String toString() => describe();
}
