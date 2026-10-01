library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as so;

import 'audio_output.dart';

Future<bool> ensureSoLoud() => _starter.ensure();

final _starter = AudioStarter(
  start: () async {
    final soloud = so.SoLoud.instance;
    if (!soloud.isInitialized) await soloud.init();
  },
);

class AudioStarter {
  AudioStarter({
    required this.start,
    this.retryAfter = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<void> Function() start;
  final Duration retryAfter;
  final DateTime Function() _now;

  Future<bool>? _ready;
  DateTime? _failedAt;

  Future<bool> ensure() {
    final ready = _ready;
    if (ready != null) return ready;
    final failedAt = _failedAt;
    if (failedAt != null && _now().difference(failedAt) < retryAfter) {
      return SynchronousFuture(false);
    }
    final attempt = _attempt();
    _ready = attempt;

    attempt.then((ok) {
      if (ok || !identical(_ready, attempt)) return;
      _ready = null;
      _failedAt = _now();
    });
    return attempt;
  }

  Future<bool> _attempt() async {
    try {
      await start();
      return true;
    } on Object catch (e) {
      debugPrint('[audio] the audio engine did not start: $e');
      return false;
    }
  }

  void reset() {
    _ready = null;
    _failedAt = null;
  }
}

Future<void> restartSoLoud() => _restarting ??= () async {
  try {
    for (final output in SoLoudOutput._outputs.toList()) {
      output._forgetEverything();
    }
    SoLoudOutput._generation++;
    SoLoudOutput._loaded.clear();
    SoLoudOutput._loading.clear();
    SoLoudOutput._owners.clear();
    try {
      final soloud = so.SoLoud.instance;
      if (soloud.isInitialized) soloud.deinit();
    } on Object catch (e) {
      debugPrint('[audio] SoLoud did not shut down cleanly: $e');
    }
    _starter.reset();
    if (!await ensureSoLoud()) return;
    for (final reopen in List.of(soLoudRestarted)) {
      reopen();
    }
    await SoLoudOutput.preload(SoLoudOutput._preloaded.toList());
  } finally {
    _restarting = null;
  }
}();
Future<void>? _restarting;

final soLoudRestarted = <void Function()>[];

void shutdownSoLoud() {
  final soloud = so.SoLoud.instance;
  if (soloud.isInitialized) soloud.deinit();
  _starter.reset();
  SoLoudOutput._loaded.clear();
  SoLoudOutput._loading.clear();
  SoLoudOutput._owners.clear();
}

class SoLoudOutput implements AudioOutput {
  SoLoudOutput() {
    _outputs.add(this);
  }

  static final _outputs = <SoLoudOutput>{};

  static int _generation = 0;

  static final _preloaded = <String>{};

  static final _loaded = <String, so.AudioSource>{};
  static final _loading = <String, Future<so.AudioSource?>>{};

  static final _owners = <so.SoundHandle, SoLoudOutput>{};

  static Future<void> preload(Iterable<String> assets) {
    _preloaded.addAll(assets);
    return Future.wait([for (final a in assets) _load(a)]);
  }

  static Future<so.AudioSource?> _load(String asset) {
    final done = _loaded[asset];
    if (done != null) return SynchronousFuture(done);
    return _loading[asset] ??= () async {
      if (!await ensureSoLoud()) {
        _loading.remove(asset);
        return null;
      }
      try {
        final generation = _generation;
        final source = await so.SoLoud.instance.loadAsset(asset);

        if (generation != _generation) return null;
        source.soundEvents.listen((e) {
          if (e.event != so.SoundEventType.handleIsNoMoreValid) return;
          _owners.remove(e.handle)?._ended(e.handle);
        });
        _loaded[asset] = source;
        return source;
      } on Object catch (e) {
        debugPrint('[audio] $asset did not load: $e');
        _loading.remove(asset);
        return null;
      }
    }();
  }

  @override
  set onFinished(void Function(int handleId)? callback) =>
      _onFinished = callback;
  void Function(int handleId)? _onFinished;

  final _live = <int, so.SoundHandle>{};

  final _starting = <int>{};

  bool _disposed = false;

  @override
  Future<void> play(
    int handleId,
    String asset, {
    bool loop = false,
    double volume = 1.0,
    Duration fadeIn = Duration.zero,
  }) async {
    if (_disposed) {
      _gaveUp(handleId);
      return;
    }

    final ready = _loaded[asset];
    if (ready != null) {
      _start(handleId, ready, loop, volume, fadeIn);
      return;
    }

    _starting.add(handleId);
    final source = await _load(asset);
    if (!_starting.remove(handleId) || _disposed || source == null) {
      _gaveUp(handleId);
      return;
    }
    _start(handleId, source, loop, volume, fadeIn);
  }

  void _gaveUp(int handleId) => _onFinished?.call(handleId);

  void _start(
    int handleId,
    so.AudioSource source,
    bool loop,
    double volume,
    Duration fadeIn,
  ) {
    try {
      final soloud = so.SoLoud.instance;
      final target = volume.clamp(0.0, 1.0);
      final fading = fadeIn > Duration.zero;
      final voice = soloud.play(
        source,
        volume: fading ? 0 : target,
        looping: loop,
      );

      if (fading) soloud.fadeVolume(voice, target, fadeIn);
      _live[handleId] = voice;
      _owners[voice] = this;
    } on Object catch (e) {
      debugPrint('[audio] ${source.soundPath} did not play: $e');
      _gaveUp(handleId);
    }
  }

  void _ended(so.SoundHandle voice) {
    int? id;
    for (final e in _live.entries) {
      if (e.value == voice) {
        id = e.key;
        break;
      }
    }
    if (id == null) return;
    _live.remove(id);
    _onFinished?.call(id);
  }

  @override
  Future<void> stop(int handleId, {Duration fade = Duration.zero}) async {
    _starting.remove(handleId);
    final voice = _live.remove(handleId);
    if (voice == null) return;

    _owners.remove(voice);
    try {
      final soloud = so.SoLoud.instance;
      if (fade > Duration.zero) {
        soloud
          ..fadeVolume(voice, 0, fade)
          ..scheduleStop(voice, fade);
      } else {
        await soloud.stop(voice);
      }
    } on Object catch (e) {
      debugPrint('[audio] stop failed: $e');
    }
  }

  @override
  Future<void> stopAll() async {
    _starting.clear();
    for (final id in _live.keys.toList()) {
      await stop(id);
    }
  }

  void _forgetEverything() {
    final gone = [..._live.keys, ..._starting];
    _live.clear();
    _starting.clear();
    for (final id in gone) {
      _gaveUp(id);
    }
  }

  @override
  @override
  Future<void> dispose() async {
    _outputs.remove(this);
    _disposed = true;
    await stopAll();
  }
}
