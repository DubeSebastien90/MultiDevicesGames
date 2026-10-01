library;

import '../platform_config.dart';
import 'audio_output.dart';
import 'game_audio.dart';
import 'sound_cue.dart';
import 'tone.dart';
import 'tone_output.dart';

class _Scheduled {
  _Scheduled({
    required this.handleId,
    required this.asset,
    required this.atMs,
    required this.loop,
    required this.volume,
    required this.persist,
    this.tone,
    this.fadeInMs = 0,
  });

  final int handleId;

  final String asset;
  final Tone? tone;
  final double atMs;
  final bool loop;
  final double volume;
  final bool persist;
  final int fadeInMs;
}

class _Live {
  const _Live({
    required this.persist,
    required this.loop,
    this.tone,
    this.startMs = 0,
  });

  final Tone? tone;
  final double startMs;

  final bool persist;

  final bool loop;
}

class AudioEngine implements LocalAudio {
  AudioEngine({AudioOutput? output, ToneOutput? tones, this.muted = false})
    : _output = output ?? SilentAudioOutput(),
      _tones = tones ?? SilentToneOutput() {
    _output.onFinished = _finished;
  }

  void _finished(int handleId) => _live.remove(handleId);

  final AudioOutput _output;

  final ToneOutput _tones;

  ToneOutput get tones => _tones;

  bool muted;

  AudioOutput get output => _output;

  final _pending = <_Scheduled>[];

  final _live = <int, _Live>{};

  static const staleMs = 400.0;

  static const maxVoices = 12;

  int _nextLocalHandle = -2;

  void receive(Map<String, dynamic> msg) {
    switch (msg['op'] as String?) {
      case AudioOp.play:
        final asset = msg['asset'] as String?;

        if (asset == null) return;
        _pending.add(
          _Scheduled(
            handleId: (msg['h'] as num).toInt(),
            asset: asset,
            atMs: (msg['at'] as num?)?.toDouble() ?? 0,
            loop: msg['loop'] == true,
            volume: (msg['vol'] as num?)?.toDouble() ?? 1.0,
            persist: msg['persist'] == true,
            fadeInMs: (msg['fadeIn'] as num?)?.toInt() ?? 0,
          ),
        );

        while (_pending.length > 64) {
          _pending.removeAt(0);
        }

      case AudioOp.tone:
        _pending.add(
          _Scheduled(
            handleId: (msg['h'] as num).toInt(),
            asset: '',
            tone: Tone.fromJson(msg['tone'] as Map<String, dynamic>),
            atMs: (msg['at'] as num?)?.toDouble() ?? 0,
            loop: true,
            volume: 1.0,
            persist: msg['persist'] == true,
          ),
        );

      case AudioOp.stop:
        _stop(
          (msg['h'] as num).toInt(),
          fade: Duration(milliseconds: (msg['fade'] as num?)?.toInt() ?? 0),
        );

      case AudioOp.stopRound:
        stopAll(includingPersistent: false);
    }
  }

  void pump(double renderTimeMs) {
    var i = 0;
    while (i < _pending.length) {
      final cue = _pending[i];
      if (renderTimeMs < cue.atMs) {
        i++;
        continue;
      }
      _pending.removeAt(i);
      final tone = cue.tone;
      if (tone != null) {
        _startTone(cue.handleId, tone, cue.atMs, renderTimeMs, cue.persist);
        continue;
      }
      if (renderTimeMs - cue.atMs > staleMs) continue;
      _start(
        cue.handleId,
        cue.asset,
        loop: cue.loop,
        volume: cue.volume,
        persist: cue.persist,
        fadeIn: Duration(milliseconds: cue.fadeInMs),
      );
    }
    _glide(renderTimeMs);
  }

  void _glide(double renderTimeMs) {
    for (final e in _live.entries) {
      final tone = e.value.tone;
      if (tone == null) continue;
      final elapsed = renderTimeMs - e.value.startMs;
      _tones.set(e.key, tone.hzAt(elapsed), tone.volumeAt(elapsed));
    }
  }

  void _startTone(
    int handleId,
    Tone tone,
    double atMs,
    double nowMs,
    bool persist,
  ) {
    if (muted) return;

    _live[handleId] = _Live(
      persist: persist,
      loop: true,
      tone: tone,
      startMs: atMs,
    );
    final elapsed = nowMs - atMs;
    _tones.start(handleId, tone.hzAt(elapsed), tone.volumeAt(elapsed));
  }

  @override
  SoundHandle play(SoundCue cue, {bool loop = false, double volume = 1.0}) {
    if (!cue.exists) return SoundHandle.none;
    final id = _nextLocalHandle--;
    _start(id, cue.asset!, loop: loop, volume: volume, persist: false);
    return SoundHandle(id);
  }

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) =>
      _stop(handle.id, fade: fade);

  void _start(
    int handleId,
    String asset, {
    required bool loop,
    required double volume,
    required bool persist,
    Duration fadeIn = Duration.zero,
  }) {
    if (muted) return;

    if (!loop && _oneShotCount >= maxVoices) {
      final stolen = handleId < 0 ? _oldestOneShot : null;
      if (stolen == null) return;
      _stop(stolen);
    }
    _live[handleId] = _Live(persist: persist, loop: loop);

    _output.play(handleId, asset, loop: loop, volume: volume, fadeIn: fadeIn);
  }

  int? get _oldestOneShot {
    for (final e in _live.entries) {
      if (!e.value.loop) return e.key;
    }
    return null;
  }

  int get _oneShotCount {
    var n = 0;
    for (final live in _live.values) {
      if (!live.loop) n++;
    }
    return n;
  }

  void _stop(int handleId, {Duration fade = Duration.zero}) {
    _pending.removeWhere((c) => c.handleId == handleId);
    final live = _live.remove(handleId);
    if (live == null) return;
    if (live.tone != null) {
      _tones.stop(handleId, fade: fade);
    } else {
      _output.stop(handleId, fade: fade);
    }
  }

  void stopAll({bool includingPersistent = true}) {
    if (includingPersistent) {
      _pending.clear();
      _live.clear();
      _output.stopAll();
      _tones.stopAll();
      return;
    }
    _pending.removeWhere((c) => !c.persist);
    final ending = [
      for (final e in _live.entries)
        if (!e.value.persist) e.key,
    ];
    for (final id in ending) {
      final live = _live.remove(id);
      if (live?.tone != null) {
        _tones.stop(id, fade: PlatformConfig.roundEndFade);
      } else {
        _output.stop(id, fade: PlatformConfig.roundEndFade);
      }
    }
  }

  Future<void> dispose() async {
    _pending.clear();
    _live.clear();
    await _output.dispose();
    await _tones.dispose();
  }
}
