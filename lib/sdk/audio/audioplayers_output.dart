/// The one class in the SDK that actually makes a noise.
///
/// Everything else in `sdk/audio/` is routing, scheduling and lifetime, and
/// none of it knows this exists — [AudioEngine] holds an [AudioOutput] and the
/// silent one is still the default. That is what let the whole system be built
/// and tested before there was a single recording, and it is what keeps every
/// test silent now that there is.
///
/// Wired in exactly one place: `AppController`, where the phone's own session
/// is built. A test that constructs a [ClientSession] gets silence unless it
/// asks for otherwise, which is the right default for a suite that runs on a
/// build machine with no audio device.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_output.dart';

/// Plays cues through `audioplayers`, one player per running sound.
///
/// A player per sound rather than one shared: eight players at a table can
/// score in the same tick, and a single player would cut each sound off with
/// the next. They are pooled and reused, because creating one has a real cost
/// on Android and a squish is not the moment to pay it.
class AudioPlayersOutput implements AudioOutput {
  AudioPlayersOutput({this.maxPlayers = 12});

  /// A ceiling on live players. [AudioEngine] already caps voices; this is the
  /// backstop for anything that reaches the output another way, and the number
  /// of native players a phone is asked to hold.
  final int maxPlayers;

  final _live = <int, AudioPlayer>{};
  final _idle = <AudioPlayer>[];
  final _fades = <int, Timer>{};
  bool _disposed = false;

  /// `audioplayers` resolves an [AssetSource] under its own `assets/` prefix,
  /// so the path a cue carries — which is the real, complete one every other
  /// part of Flutter uses — has to have that prefix taken off again.
  static String _sourcePath(String asset) =>
      asset.startsWith('assets/') ? asset.substring('assets/'.length) : asset;

  @override
  Future<void> play(
    int handleId,
    String asset, {
    bool loop = false,
    double volume = 1.0,
  }) async {
    if (_disposed) return;
    try {
      final player = _take();
      _live[handleId] = player;

      await player.setReleaseMode(
        loop ? ReleaseMode.loop : ReleaseMode.stop,
      );
      await player.setVolume(volume.clamp(0.0, 1.0));
      await player.play(AssetSource(_sourcePath(asset)));

      // A one-shot hands its player back when it finishes, so a round of
      // squishes does not accumulate a player each.
      if (!loop) {
        late final StreamSubscription<void> sub;
        sub = player.onPlayerComplete.listen((_) {
          sub.cancel();
          if (identical(_live[handleId], player)) _release(handleId);
        });
      }
    } on Object catch (e) {
      // A missing file, a codec that will not have it, a device with no audio
      // route. All of them are silence — never a crashed round. A game does
      // not get to fail because of a sound.
      debugPrint('[audio] $asset did not play: $e');
      _release(handleId);
    }
  }

  @override
  Future<void> stop(int handleId, {Duration fade = Duration.zero}) async {
    final player = _live[handleId];
    if (player == null) return;

    if (fade <= Duration.zero) {
      await _stopNow(handleId, player);
      return;
    }

    // `audioplayers` has no fade, so this is a short volume ramp. Music
    // stopping dead at the end of a round is heard as a fault; a one-shot
    // passes zero and is cut.
    _fades[handleId]?.cancel();
    const stepMs = 25;
    final steps = (fade.inMilliseconds / stepMs).ceil().clamp(1, 200);
    var step = 0;
    _fades[handleId] = Timer.periodic(
      const Duration(milliseconds: stepMs),
      (timer) async {
        step++;
        if (step >= steps || _disposed) {
          timer.cancel();
          _fades.remove(handleId);
          await _stopNow(handleId, player);
          return;
        }
        try {
          await player.setVolume((1 - step / steps).clamp(0.0, 1.0));
        } on Object {
          timer.cancel();
          _fades.remove(handleId);
        }
      },
    );
  }

  Future<void> _stopNow(int handleId, AudioPlayer player) async {
    try {
      await player.stop();
      await player.setVolume(1);
    } on Object catch (e) {
      debugPrint('[audio] stop failed: $e');
    }
    _release(handleId);
  }

  @override
  Future<void> stopAll() async {
    for (final timer in _fades.values) {
      timer.cancel();
    }
    _fades.clear();
    for (final entry in _live.entries.toList()) {
      await _stopNow(entry.key, entry.value);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stopAll();
    for (final player in [..._idle, ..._live.values]) {
      await player.dispose();
    }
    _idle.clear();
    _live.clear();
  }

  AudioPlayer _take() {
    if (_idle.isNotEmpty) return _idle.removeLast();
    final player = AudioPlayer();

    // Short clips through the low-latency path where the platform has one —
    // the difference between a tap that answers and a tap that lags. Windows
    // and Linux have no such mode and no-op it; Android and iOS do. Guarded
    // rather than assumed, because an unawaited failure here would surface as
    // an unhandled async error a long way from its cause.
    player
        .setPlayerMode(PlayerMode.lowLatency)
        .catchError((Object e) => debugPrint('[audio] low latency mode: $e'));

    // A sound that fails to play is silence, and silence is indistinguishable
    // from a sound that was never asked for. This is the one thing that makes
    // the difference visible while the audio is new.
    player.onLog.listen(
      (message) => debugPrint('[audio] $message'),
      onError: (Object e) => debugPrint('[audio] error: $e'),
    );
    return player;
  }

  void _release(int handleId) {
    final player = _live.remove(handleId);
    if (player == null) return;
    _fades.remove(handleId)?.cancel();
    if (_idle.length < maxPlayers) {
      _idle.add(player);
    } else {
      unawaited(player.dispose());
    }
  }
}
