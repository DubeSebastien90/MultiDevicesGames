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

/// Starts SoLoud for the whole app, however many outputs ask.
///
/// Shared with the tone output: two callers racing `init()` on one engine is
/// exactly the kind of start-up bug that only shows on a slow phone.
Future<bool> ensureSoLoud() => _starter.ensure();

final _starter = AudioStarter(
  start: () async {
    final soloud = so.SoLoud.instance;
    if (!soloud.isInitialized) await soloud.init();
  },
);

/// Starts an audio engine once, and — unlike a plain `??=` — tries again if it
/// could not.
///
/// The first version kept the first answer for good, failure included: an app
/// launched while the system would not hand over the audio device — during a
/// call, say — stayed silent for the rest of its life, however long ago the
/// call ended. Now a failure is forgotten after [retryAfter], and the next
/// sound asked for tries again. Not sooner, so a device that is genuinely
/// gone is not asked twelve times a second.
class AudioStarter {
  AudioStarter({
    required this.start,
    this.retryAfter = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Brings the engine up, or throws.
  final Future<void> Function() start;
  final Duration retryAfter;
  final DateTime Function() _now;

  Future<bool>? _ready;
  DateTime? _failedAt;

  /// True once the engine is up. A caller that finds it down gets false, and
  /// only the first caller after [retryAfter] pays for another attempt.
  Future<bool> ensure() {
    final ready = _ready;
    if (ready != null) return ready;
    final failedAt = _failedAt;
    if (failedAt != null && _now().difference(failedAt) < retryAfter) {
      return SynchronousFuture(false);
    }
    final attempt = _attempt();
    _ready = attempt;
    // Registered before anybody else can await it, so by the time a caller
    // hears 'false' the failure is already forgotten.
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

  /// Forget everything, as if the app had just launched.
  void reset() {
    _ready = null;
    _failedAt = null;
  }
}

/// Stops SoLoud's mixer before the process goes away.
///
/// Not optional on Windows: the mixer runs on its own native thread, and a
/// window closed with that thread still alive leaves the process running with
/// no window — holding `flutter_soloud_plugin.dll`, so the next build cannot
/// overwrite it and fails at the install step.
/// Throws SoLoud away and starts it again, for when the app comes back from
/// the background.
///
/// The system takes the audio device from an app that is not in front — iOS
/// the moment it is minimised, Android when something else wants to play —
/// and SoLoud is not told. It still says it is initialised, every play still
/// succeeds, and nothing comes out of the speaker for the rest of the app's
/// life. So on the way back it is not asked; it is rebuilt:
///
/// 1. every output forgets what it was playing, and tells its engine those
///    sounds are over, so none of them holds a seat;
/// 2. every decoded file is dropped — they belong to the old engine — and any
///    decode still in flight is marked stale so it cannot land in the cache;
/// 3. SoLoud is shut down and started afresh;
/// 4. whoever else holds SoLoud things (the tone output) is told to reopen
///    them, and the files preloaded at launch are decoded again, so the next
///    tap is as quick as the first one was.
///
/// Calls made while one is running share it.
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

/// Called once SoLoud has been started again by [restartSoLoud], for anything
/// outside this file holding voices or sources on it.
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

  /// Every output alive, so a restart can tell each what it lost.
  static final _outputs = <SoLoudOutput>{};

  /// Bumped by every [restartSoLoud]. A decode started before one belongs to
  /// the old engine, and must not be kept.
  static int _generation = 0;

  /// Everything ever preloaded, to be decoded again after a restart.
  static final _preloaded = <String>{};

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
  static Future<void> preload(Iterable<String> assets) {
    _preloaded.addAll(assets);
    return Future.wait([for (final a in assets) _load(a)]);
  }

  static Future<so.AudioSource?> _load(String asset) {
    final done = _loaded[asset];
    if (done != null) return SynchronousFuture(done);
    return _loading[asset] ??= () async {
      if (!await ensureSoLoud()) {
        // Not remembered: the engine may be up by the next play, and a file
        // that failed only because it was asked for too early must not stay
        // silent for good.
        _loading.remove(asset);
        return null;
      }
      try {
        final generation = _generation;
        final source = await so.SoLoud.instance.loadAsset(asset);
        // Restarted while it decoded: a source from an engine that is gone.
        if (generation != _generation) return null;
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
    if (_disposed) {
      _gaveUp(handleId);
      return;
    }

    // Already decoded — the usual case — plays right here, synchronously, so
    // cues asked for in order start in order.
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

  /// A sound that will never play, reported as over.
  ///
  /// The engine counts every sound it asked for as live until it hears the
  /// sound has finished, and turns a round's sounds away once twelve are live.
  /// A file that would not load, an engine that would not start, a play that
  /// threw: none of those ever finish, so each one used to hold a seat for the
  /// rest of the round — and twelve of them silenced it. Saying so at once
  /// frees the seat. A sound stopped while it loaded is already out of the
  /// count, and hearing about it again changes nothing.
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
      // On the mixer's own clock, like the fade out in [stop].
      if (fading) soloud.fadeVolume(voice, target, fadeIn);
      _live[handleId] = voice;
      _owners[voice] = this;
    } on Object catch (e) {
      debugPrint('[audio] ${source.soundPath} did not play: $e');
      _gaveUp(handleId);
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

  /// Everything this output was playing is gone with the old engine: forget it
  /// and say so, so the engine counting voices does not wait on sounds that
  /// will never report their end.
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
