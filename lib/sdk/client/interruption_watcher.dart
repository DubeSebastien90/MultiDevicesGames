import 'package:flutter/widgets.dart';

class InterruptionWatcher with WidgetsBindingObserver {
  InterruptionWatcher(this.onInterrupted);

  final void Function(Duration held) onInterrupted;

  static const _floor = Duration(milliseconds: 500);

  static const _ceiling = Duration(seconds: 60);

  Stopwatch? _covered;

  bool _left = false;

  void start() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  void stop() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        _covered ??= (Stopwatch()..start());

      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _left = true;

      case AppLifecycleState.resumed:
        final covered = _covered;
        _covered = null;
        final left = _left;
        _left = false;

        if (covered == null || left) return;
        final held = covered.elapsed;
        if (held >= _floor && held <= _ceiling) onInterrupted(held);
    }
  }
}
