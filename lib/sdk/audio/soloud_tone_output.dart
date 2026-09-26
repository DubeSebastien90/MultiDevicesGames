/// Tones on SoLoud: the one engine here that can bend pitch while it plays.
///
/// Recordings go through `SoLoudOutput`, on the same engine. `audioplayers`
/// could never have done this — on iOS it changes rate with a pitch-preserving
/// algorithm, so a rising tone would only ever rise on Android. SoLoud synthesises the sine itself, and
/// its oscillator accumulates phase and smooths each change of frequency over
/// the next buffer (`src/synth/basic_wave.cpp`), so moving the pitch every
/// frame is a glide and not a staircase of clicks.
///
/// Anything that goes wrong — the engine will not start, a platform without
/// it — is silence, never a crashed round. A game does not get to fail because
/// of a sound.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as so;

import 'soloud_output.dart';
import 'tone_output.dart';

class SoLoudToneOutput implements ToneOutput {
  final _tones = <int, _Voice>{};
  bool _disposed = false;

  @override
  void start(int handleId, double hz, double volume) {
    if (_disposed) return;
    final voice = _Voice(hz, volume);
    _tones[handleId] = voice;
    unawaited(_open(handleId, voice));
  }

  Future<void> _open(int handleId, _Voice voice) async {
    if (!await ensureSoLoud()) return;
    try {
      final soloud = so.SoLoud.instance;
      final source = await soloud.loadWaveform(so.WaveForm.sin, false, 1, 0);
      // Stopped while the waveform was loading: nothing to start.
      if (!identical(_tones[handleId], voice)) {
        await soloud.disposeSource(source);
        return;
      }
      // Pitch first, so it does not begin at the default and slide up.
      soloud.setWaveformFreq(source, voice.hz);
      voice.source = source;
      voice.handle = soloud.play(source, volume: voice.volume);
    } on Object catch (e) {
      debugPrint('[tone] $handleId did not start: $e');
    }
  }

  @override
  void set(int handleId, double hz, double volume) {
    final voice = _tones[handleId];
    if (voice == null) return;
    voice
      ..hz = hz
      ..volume = volume;
    final source = voice.source;
    final handle = voice.handle;
    // Still opening: [_open] applies the latest values when it gets there.
    if (source == null || handle == null) return;
    try {
      final soloud = so.SoLoud.instance;
      soloud.setWaveformFreq(source, hz);
      soloud.setVolume(handle, volume);
    } on Object catch (e) {
      debugPrint('[tone] $handleId could not move: $e');
    }
  }

  @override
  void stop(int handleId, {Duration fade = Duration.zero}) {
    final voice = _tones.remove(handleId);
    if (voice == null) return;
    unawaited(_close(voice, fade));
  }

  Future<void> _close(_Voice voice, Duration fade) async {
    final source = voice.source;
    final handle = voice.handle;
    if (source == null) return; // Never opened; [_open] will see it is gone.
    try {
      final soloud = so.SoLoud.instance;
      if (handle != null && fade > Duration.zero) {
        soloud.fadeVolume(handle, 0, fade);
        await Future<void>.delayed(fade);
      }
      // Disposing the source stops every voice playing it.
      await soloud.disposeSource(source);
    } on Object catch (e) {
      debugPrint('[tone] stop failed: $e');
    }
  }

  @override
  void stopAll() {
    for (final id in _tones.keys.toList()) {
      stop(id);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    stopAll();
  }
}

/// One oscillator: where it should be, and what SoLoud handed back once it was.
class _Voice {
  _Voice(this.hz, this.volume);

  double hz;
  double volume;
  so.AudioSource? source;
  so.SoundHandle? handle;
}
