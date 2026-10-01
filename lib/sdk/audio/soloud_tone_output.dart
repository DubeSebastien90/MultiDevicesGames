library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as so;

import 'soloud_output.dart';
import 'tone_output.dart';

class SoLoudToneOutput implements ToneOutput {
  SoLoudToneOutput() {
    soLoudRestarted.add(_reopen);
  }

  final _tones = <int, _Voice>{};
  bool _disposed = false;

  void _reopen() {
    for (final entry in _tones.entries) {
      entry.value
        ..source = null
        ..handle = null;
      unawaited(_open(entry.key, entry.value));
    }
  }

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

      if (!identical(_tones[handleId], voice)) {
        await soloud.disposeSource(source);
        return;
      }

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
    if (source == null) return;
    try {
      final soloud = so.SoLoud.instance;
      if (handle != null && fade > Duration.zero) {
        soloud.fadeVolume(handle, 0, fade);
        await Future<void>.delayed(fade);
      }

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
    soLoudRestarted.remove(_reopen);
    _disposed = true;
    stopAll();
  }
}

class _Voice {
  _Voice(this.hz, this.volume);

  double hz;
  double volume;
  so.AudioSource? source;
  so.SoundHandle? handle;
}
