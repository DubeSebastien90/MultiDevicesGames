import 'dart:math' as math;

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

class PlayerCount {
  const PlayerCount.range({
    required int min,
    int max = 8,
    this.parity = CountParity.any,
  }) : _min = min,
       _max = max,
       allowed = null;

  const PlayerCount.exactly(int count)
    : _min = count,
      _max = count,
      parity = CountParity.any,
      allowed = null;

  const PlayerCount.anyOf(List<int> counts)
    : allowed = counts,
      _min = null,
      _max = null,
      parity = CountParity.any;

  final int? _min;
  final int? _max;

  final CountParity parity;

  final List<int>? allowed;

  bool fits(int phones) {
    final list = allowed;
    if (list != null) return list.contains(phones);
    return phones >= _min! && phones <= _max! && parity.allows(phones);
  }

  int get smallest {
    final list = allowed;
    if (list != null && list.isNotEmpty) return list.reduce(math.min);

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

  bool get pairsOnly {
    final counts = playableCounts();
    return counts.isNotEmpty && counts.every((n) => n.isEven);
  }

  List<int> playableCounts({int ceiling = 8}) => [
    for (var n = 1; n <= ceiling; n++)
      if (fits(n)) n,
  ];

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
      return _max! >= 8 ? 'needs $_min+ phones' : 'needs $_min–$_max phones';
    }
    return 'needs $parityWord phones, $smallest to $largest';
  }

  @override
  String toString() => describe();
}
