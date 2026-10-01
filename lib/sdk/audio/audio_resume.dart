library;

import 'dart:async';

class AudioResumeWatcher {
  AudioResumeWatcher({required this.restart});

  final Future<void> Function() restart;

  bool _away = false;

  void left() => _away = true;

  void back() {
    if (!_away) return;
    _away = false;
    unawaited(restart());
  }
}
