/// The one class in the SDK that actually makes a noise — through SoLoud.
///
/// Replaces `AudioPlayersOutput`, and the reason is latency that *varies*.
/// `audioplayers` on iOS is an `AVPlayer` per sound, built for streaming media:
/// every play is several platform-channel round trips and a fresh player item,
/// and the time from asking to hearing wanders between tens and hundreds of
/// milliseconds. The hold-to-confirm ring asks for a new step every 83ms, so a
/// wander bigger than that played the steps out of order.
///
/// SoLoud mixes in-process. Each file is decoded into memory once, and a play
/// after that is one synchronous FFI call onto a mixer that is already running
/// — no player to build, no channel to cross, and every cue starts in the
/// order it was asked for.
///
/// Wired in `main.dart` (the menus) and `AppController` (the session). Tests
/// never build one, so the suite stays silent and needs no audio device.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as so;

import 'audio_output.dart';

/// Starts SoLoud once for the whole app, however many outputs ask.
///
/// Shared with the tone output: two callers racing `init()` on one engine is
/// exactly the kind of start-up bug that only shows on a slow phone.
Future<bool> ensureSoLoud() => _ready ??= () async {
  try {
    final soloud = so.SoLoud.instance;
    if (!soloud.isInitialized) await soloud.init();
    return true;
  } on Object catch (e) {
    debugPrint('[audio] SoLoud did not start: $e');
    return false;
  }
}();
Future<bool>? _ready;

/// Stops SoLoud's mixer before the process goes away.
///
/// Not optional on Windows: the mixer runs on its own native thread, and a
/// window closed with that thread still alive leaves the process running with
/// no window — holding `flutter_soloud_plugin.dll`, so the next build cannot
/// overwrite it and fails at the install step.
void shutdownSoLoud() {
  final soloud = so.SoLoud.instance;
  if (soloud.isInitialized) soloud.deinit();
  _ready = null;
  SoLoudOutput._loaded.clear();
  SoLoudOutput._loading.clear();
  SoLoudOutput._owners.clear();
}

class SoLoudOutput implements AudioOutput {
  SoLoudOutput();

  // ------------------------------------------------------ the sample cache

  /// Decoded files, by asset path. Static because the menus and the session
  /// each have an output and the same boup should not be decoded twice.
  /// Never freed: the whole library is a couple of megabytes of PCM.
  static final _loaded = <String, so.AudioSource>{};
  static final _loading = <String, Future<so.AudioSource?>>{};

  /// Every live SoLoud voice, across every output, back to whoever owns it —
  /// so one listener per source can report a finished voice to the right one.
  static final _owners = <so.SoundHandle, SoLoudOutput>{};

  /// Decode [assets] now, so their first play is as quick as every other.
  ///
  /// Worth calling at launch for anything played in a rapid run — the hold
  /// steps above all. A file nobody preloaded still plays; its first play just
  /// waits for the decode.
  static Future<void> preload(Iterable<String> assets) =>
      Future.wait([for (final a in assets) _load(a)]);

  static Future<so.AudioSource?> _load(String asset) {
    final done = _loaded[asset];
    if (done != null) return SynchronousFuture(done);
    return _loading[asset] ??= () async {
      if (!await ensureSoLoud()) return null;
      try {
        final source = await so.SoLoud.instance.loadAsset(asset);
        source.soundEvents.listen((e) {
          if (e.event != so.SoundEventType.handleIsNoMoreValid) return;
          _owners.remove(e.handle)?._ended(e.handle);
        });
        _loaded[asset] = source;
        return source;
      } on Object catch (e) {
        // A missing file or a codec that will not have it: silence, never a
        // crashed round. Forgotten, so a later play can try again.
        debugPrint('[audio] $asset did not load: $e');
        _loading.remove(asset);
        return null;
      }
    }();
  }

  // ------------------------------------------------------------ this output

  @override
  set onFinished(void Function(int handleId)? callback) =>
      _onFinished = callback;
  void Function(int handleId)? _onFinished;

  /// The engine's handle id -> SoLoud's voice.
  final _live = <int, so.SoundHandle>{};

  /// Asked to play, still waiting on a decode. A stop in that gap removes the
  /// id, and the decode finishing then starts nothing.
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
    if (_disposed) return;

    // Already decoded — the usual case — plays right here, synchronously, so
    // cues asked for in order start in order.
    final ready = _loaded[asset];
    if (ready != null) {
      _start(handleId, ready, loop, volume, fadeIn);
      return;
    }

    _starting.add(handleId);
    final source = await _load(asset);
    if (!_starting.remove(handleId) || _disposed || source == null) return;
    _start(handleId, source, loop, volume, fadeIn);
  }

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
      // On the mixer's own clock, like the fade out in [stop].
      if (fading) soloud.fadeVolume(voice, target, fadeIn);
      _live[handleId] = voice;
      _owners[voice] = this;
    } on Object catch (e) {
      debugPrint('[audio] ${source.soundPath} did not play: $e');
    }
  }

  /// SoLoud says a voice ended by itself. Tell the engine, which counts voices
  /// and has no other way to learn one has stopped taking up a seat.
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
    // Stopped on purpose, so no finished callback — same as the old output.
    _owners.remove(voice);
    try {
      final soloud = so.SoLoud.instance;
      if (fade > Duration.zero) {
        // Both run on the mixer's own clock; nothing to wait for here.
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

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stopAll();
  }
}
