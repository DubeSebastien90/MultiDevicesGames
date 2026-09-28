/// When to rebuild the audio engine: on the way back from actually leaving.
///
/// Leaving is the app being hidden or paused — minimised, switched away from,
/// the screen locked. Being merely inactive — the notification shade pulled
/// down, a system dialog over the app — keeps the audio device, and rebuilding
/// the engine then would cut off whatever was playing for nothing.
library;

import 'dart:async';

class AudioResumeWatcher {
  AudioResumeWatcher({required this.restart});

  /// What to do on the way back.
  final Future<void> Function() restart;

  bool _away = false;

  /// The app was hidden or paused.
  void left() => _away = true;

  /// The app is in front again. Restarts only if it had really gone.
  void back() {
    if (!_away) return;
    _away = false;
    unawaited(restart());
  }
}
