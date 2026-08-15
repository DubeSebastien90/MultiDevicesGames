/// The one place bytes actually reach a speaker.
///
/// Everything else in `sdk/audio/` is routing, scheduling and lifetime — none
/// of which needs a decoder, and all of which is testable without one. This is
/// the seam where a real audio package plugs in.
///
/// It is deliberately the last piece. There is not a single sound file in the
/// project yet, so shipping a native audio dependency now would add a plugin to
/// four platform builds in order to play nothing. [SilentAudioOutput] is the
/// default and behaves correctly in every respect except making noise; when the
/// first clip is recorded, one class arrives here and nothing else changes.
library;

import 'dart:async';

/// Plays and stops one sound at a time, identified by handle.
///
/// Implementations must tolerate being told to stop something that already
/// finished, and must never throw into the caller: a missing file, a codec that
/// does not like an asset, or a device with no audio route are all *silence*,
/// never a crashed round. A game does not get to fail because of a sound.
abstract class AudioOutput {
  /// Start [asset] under [handleId]. Returns when playback has been *asked*
  /// for, not when the sound finishes.
  Future<void> play(
    int handleId,
    String asset, {
    bool loop = false,
    double volume = 1.0,
  });

  /// Stop [handleId], fading over [fade] where the implementation can.
  Future<void> stop(int handleId, {Duration fade = Duration.zero});

  Future<void> stopAll();

  Future<void> dispose();
}

/// Correct in every way except audible.
///
/// Not a test double — this is what every phone runs today. It records what it
/// was asked to do so a test, a debug panel, or a person watching the log can
/// confirm the routing and the timing are right long before there is anything
/// to hear.
class SilentAudioOutput implements AudioOutput {
  SilentAudioOutput({this.keepLog = false});

  /// Whether to remember calls. Off by default: a round can raise thousands of
  /// cues and a list that only a test ever reads should not grow on every
  /// phone at the table.
  final bool keepLog;

  final _log = <String>[];
  final _playing = <int>{};

  List<String> get log => List.unmodifiable(_log);

  /// Forget what has been played so far, so a test can watch one moment
  /// without counting everything that led up to it.
  void clearLog() => _log.clear();

  /// Handles currently 'playing', which is what makes the lifetime rules
  /// testable: a round that ends must leave this empty apart from persistent
  /// sounds.
  Set<int> get playing => Set.unmodifiable(_playing);

  @override
  Future<void> play(
    int handleId,
    String asset, {
    bool loop = false,
    double volume = 1.0,
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
