import '../layout/name_drop_optimizer.dart';

/// Decides whether two phones being interrupted at once was NameDrop.
///
/// Each phone can only report that *something* covered its screen — iOS never
/// says what, and no API will tell an app whether the setting behind NameDrop
/// is even on. One such report is nearly worthless: with phones lying flat on a
/// table and people reaching across them, a half-finished home-indicator swipe
/// produces exactly the same signal, all evening.
///
/// What makes it mean something is that NameDrop takes **two phones**, and
/// specific ones — the pair whose tops are touching. A phone call, a Control
/// Centre pull, a stray thumb: all of those hit one device. So a report is
/// believed only when a second phone reports the same moment, and the layout
/// says those two are a pair [NameDropOptimizer] could not turn apart.
///
/// Nothing here is certain, and it is not built to be. Two alarms going off
/// together on adjacent phones would fool it. The cost of that is one extra
/// question in a lobby, which is why the bar is set where it is rather than
/// higher.
class NameDropDetector {
  /// [clock] reads elapsed time since some fixed point — any fixed point. Only
  /// differences are ever taken. Injectable because the thing worth testing
  /// here is what happens across a gap of several seconds, and a test that
  /// waits out its own subject matter is a slow test that still only proves
  /// the machine was not busy.
  NameDropDetector({Duration Function()? clock}) : _clock = clock ?? _running();

  static Duration Function() _running() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  /// How far apart two interruptions may have *begun* and still count as the
  /// same event.
  ///
  /// Generous next to the millisecond both cards actually appear in, because
  /// the reports are built from each phone's own elapsed time and travel over
  /// a network. Tight next to anything coincidental.
  static const _window = Duration(seconds: 2);

  /// How long an unmatched report waits for a partner.
  ///
  /// Long, because the two phones report when their user dismisses the card,
  /// and one person can sit staring at it for a while after the other has
  /// swiped it away.
  static const _memory = Duration(seconds: 30);

  /// Longer than this and the client should not have sent it; see
  /// `InterruptionWatcher`. Guarded again here because this is fed from the
  /// network.
  static const _maxAge = Duration(seconds: 60);

  final Duration Function() _clock;

  /// When each phone's last unmatched interruption began, on the host's clock.
  final _began = <String, Duration>{};

  /// A report just arrived. Returns the pair to warn, or null.
  ///
  /// [ago] is how long before *now* the interruption started, as measured on
  /// the reporting phone. Converting it here means the two devices never have
  /// to agree what time it is — only how long a moment lasted, which their own
  /// stopwatches answer accurately.
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

      // Both are spent. Without this the next report from either phone could
      // pair with the same stale entry and raise the same event twice.
      _began.remove(entry.key);
      _began.remove(phoneId);
      return pair;
    }

    _began[phoneId] = began;
    return null;
  }

  /// Forget everything pending — the table has been rearranged, so a report
  /// still waiting for a partner was measured against a layout that is gone.
  void clear() => _began.clear();
}
