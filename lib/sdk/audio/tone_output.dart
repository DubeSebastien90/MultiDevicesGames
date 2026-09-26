/// The seam between tones and whatever synthesises them.
///
/// Kept apart from [AudioOutput] because it is a different kind of thing: that
/// one plays files, this one runs oscillators whose pitch is set every frame.
/// The two can sit on different engines — recordings on `audioplayers`, tones
/// on SoLoud — without either knowing about the other.
library;

import 'package:flutter/foundation.dart';

abstract class ToneOutput {
  /// Start an oscillator under [handleId] at [hz] and [volume].
  void start(int handleId, double hz, double volume);

  /// Move a running tone. Called once per rendered frame while it plays, so it
  /// must be cheap and must not click — see `SoLoudToneOutput`.
  void set(int handleId, double hz, double volume);

  /// Stop [handleId], fading over [fade].
  void stop(int handleId, {Duration fade = Duration.zero});

  void stopAll();

  Future<void> dispose();
}

/// What every phone gets unless it asks for more, and what tests run on.
///
/// Records starts and stops (not every frame's `set`, which would drown the
/// log) so a test can see which tones began and ended, and reads back the last
/// pitch each tone was set to.
class SilentToneOutput implements ToneOutput {
  SilentToneOutput({this.keepLog = false});

  final bool keepLog;
  final _log = <String>[];
  final _hz = <int, double>{};

  List<String> get log => List.unmodifiable(_log);

  /// The pitch [handleId] was last started or set at, or null if not playing.
  double? hzOf(int handleId) => _hz[handleId];

  @override
  void start(int handleId, double hz, double volume) {
    _hz[handleId] = hz;
    if (keepLog) _log.add('tone $handleId ${hz.round()}Hz');
  }

  @override
  void set(int handleId, double hz, double volume) {
    if (_hz.containsKey(handleId)) _hz[handleId] = hz;
  }

  @override
  void stop(int handleId, {Duration fade = Duration.zero}) {
    if (_hz.remove(handleId) != null && keepLog) _log.add('stop $handleId');
  }

  @override
  void stopAll() {
    for (final id in _hz.keys.toList()) {
      stop(id);
    }
  }

  @override
  Future<void> dispose() async => stopAll();

  @visibleForTesting
  void clearLog() => _log.clear();
}
