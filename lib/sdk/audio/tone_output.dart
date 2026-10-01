library;

import 'package:flutter/foundation.dart';

abstract class ToneOutput {
  void start(int handleId, double hz, double volume);

  void set(int handleId, double hz, double volume);

  void stop(int handleId, {Duration fade = Duration.zero});

  void stopAll();

  Future<void> dispose();
}

class SilentToneOutput implements ToneOutput {
  SilentToneOutput({this.keepLog = false});

  final bool keepLog;
  final _log = <String>[];
  final _hz = <int, double>{};

  List<String> get log => List.unmodifiable(_log);

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
