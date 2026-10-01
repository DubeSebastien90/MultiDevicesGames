import '../layout/name_drop_optimizer.dart';

class NameDropDetector {
  NameDropDetector({Duration Function()? clock}) : _clock = clock ?? _running();

  static Duration Function() _running() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  static const _window = Duration(seconds: 2);

  static const _memory = Duration(seconds: 30);

  static const _maxAge = Duration(seconds: 60);

  final Duration Function() _clock;

  final _began = <String, Duration>{};

  (String, String)? report(
    String phoneId,
    Duration ago,
    Set<(String, String)> dangerPairs,
  ) {
    if (ago.isNegative || ago > _maxAge) return null;

    final now = _clock();
    final began = now - ago;

    _began.removeWhere((_, at) => now - at > _memory);

    for (final entry in _began.entries) {
      if (entry.key == phoneId) continue;
      final pair = NameDropOptimizer.pairKey(phoneId, entry.key);
      if (!dangerPairs.contains(pair)) continue;
      if ((entry.value - began).abs() > _window) continue;

      _began.remove(entry.key);
      _began.remove(phoneId);
      return pair;
    }

    _began[phoneId] = began;
    return null;
  }

  void clear() => _began.clear();
}
