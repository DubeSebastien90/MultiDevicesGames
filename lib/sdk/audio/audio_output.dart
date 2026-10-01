library;

import 'dart:async';

abstract class AudioOutput {
  set onFinished(void Function(int handleId)? callback);

  Future<void> play(
    int handleId,
    String asset, {
    bool loop = false,
    double volume = 1.0,
    Duration fadeIn = Duration.zero,
  });

  Future<void> stop(int handleId, {Duration fade = Duration.zero});

  Future<void> stopAll();

  Future<void> dispose();
}

class SilentAudioOutput implements AudioOutput {
  SilentAudioOutput({this.keepLog = false});

  @override
  set onFinished(void Function(int handleId)? callback) {}

  final bool keepLog;

  final _log = <String>[];
  final _playing = <int>{};

  List<String> get log => List.unmodifiable(_log);

  void clearLog() => _log.clear();

  Set<int> get playing => Set.unmodifiable(_playing);

  @override
  Future<void> play(
    int handleId,
    String asset, {
    bool loop = false,
    double volume = 1.0,
    Duration fadeIn = Duration.zero,
  }) async {
    _playing.add(handleId);
    if (keepLog) _log.add('play $handleId $asset${loop ? ' loop' : ''}');
  }

  @override
  Future<void> stop(int handleId, {Duration fade = Duration.zero}) async {
    _playing.remove(handleId);
    if (keepLog) _log.add('stop $handleId');
  }

  @override
  Future<void> stopAll() async {
    _playing.clear();
    if (keepLog) _log.add('stopAll');
  }

  @override
  Future<void> dispose() async {
    _playing.clear();
  }
}
