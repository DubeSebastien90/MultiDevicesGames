library;

import '../model/player.dart';
import 'sound_cue.dart';
import 'tone.dart';

abstract class GameAudio {
  SoundHandle playGeneral(
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
    Duration fadeIn = Duration.zero,
  });

  SoundHandle playOnPhone(
    Player player,
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
    Duration fadeIn = Duration.zero,
  });

  SoundHandle playToneOnPhone(Player player, Tone tone, {bool persist = false});

  void stopSound(SoundHandle handle, {Duration fade = Duration.zero});

  void stopRoundSounds();
}

abstract class LocalAudio {
  SoundHandle play(SoundCue cue, {bool loop = false, double volume = 1.0});

  void stopSound(SoundHandle handle, {Duration fade = Duration.zero});
}

class SilentGameAudio implements GameAudio {
  const SilentGameAudio();

  @override
  SoundHandle playGeneral(
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
    Duration fadeIn = Duration.zero,
  }) => SoundHandle.none;

  @override
  SoundHandle playOnPhone(
    Player player,
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
    Duration fadeIn = Duration.zero,
  }) => SoundHandle.none;

  @override
  SoundHandle playToneOnPhone(
    Player player,
    Tone tone, {
    bool persist = false,
  }) => SoundHandle.none;

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) {}

  @override
  void stopRoundSounds() {}
}

class SilentLocalAudio implements LocalAudio {
  const SilentLocalAudio();

  @override
  SoundHandle play(SoundCue cue, {bool loop = false, double volume = 1.0}) =>
      SoundHandle.none;

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) {}
}

class AudioCommand {
  AudioCommand.play({
    required this.handleId,
    required this.cue,
    required this.phoneId,
    required this.loop,
    required this.volume,
    required this.persist,
    this.fadeInMs = 0,
  }) : op = AudioOp.play,
       tone = null,
       fadeMs = 0;

  AudioCommand.tone({
    required this.handleId,
    required Tone this.tone,
    required this.phoneId,
    required this.persist,
  }) : op = AudioOp.tone,
       cue = null,
       loop = true,
       volume = 1.0,
       fadeMs = 0,
       fadeInMs = 0;

  AudioCommand.stop({
    required this.handleId,
    required this.fadeMs,
    required this.phoneId,
  }) : op = AudioOp.stop,
       cue = null,
       tone = null,
       loop = false,
       volume = 1.0,
       persist = false,
       fadeInMs = 0;

  AudioCommand.stopRound()
    : op = AudioOp.stopRound,
      handleId = -1,
      cue = null,
      tone = null,
      phoneId = null,
      loop = false,
      volume = 1.0,
      persist = false,
      fadeMs = 0,
      fadeInMs = 0;

  final String op;
  final int handleId;
  final SoundCue? cue;

  final Tone? tone;

  final String? phoneId;

  final bool loop;
  final double volume;
  final bool persist;
  final int fadeMs;

  final int fadeInMs;

  bool get isBroadcast => op == AudioOp.stopRound;

  Map<String, dynamic> toJson(double atMs) => {
    'op': op,
    'h': handleId,
    'at': atMs,
    if (cue != null) 'cue': cue!.id,
    if (cue?.asset != null) 'asset': cue!.asset,
    if (tone != null) 'tone': tone!.toJson(),
    if (phoneId != null) 'phoneId': phoneId,
    if (loop) 'loop': true,
    if (volume != 1.0) 'vol': volume,
    if (persist) 'persist': true,
    if (fadeMs > 0) 'fade': fadeMs,
    if (fadeInMs > 0) 'fadeIn': fadeInMs,
  };
}

class AudioOp {
  static const play = 'play';

  static const tone = 'tone';
  static const stop = 'stop';

  static const stopRound = 'stopRound';
}

class RoundAudio implements GameAudio {
  RoundAudio();

  final _pending = <AudioCommand>[];

  int _nextHandle = 1;

  final _target = <int, String?>{};

  List<AudioCommand> drain() {
    if (_pending.isEmpty) return const [];
    final out = List<AudioCommand>.of(_pending);
    _pending.clear();
    return out;
  }

  bool get hasPending => _pending.isNotEmpty;

  @override
  SoundHandle playGeneral(
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
    Duration fadeIn = Duration.zero,
  }) => _play(cue, null, loop, volume, persist, fadeIn);

  @override
  SoundHandle playOnPhone(
    Player player,
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
    Duration fadeIn = Duration.zero,
  }) => _play(cue, player.phoneId, loop, volume, persist, fadeIn);

  @override
  SoundHandle playToneOnPhone(
    Player player,
    Tone tone, {
    bool persist = false,
  }) {
    final id = _nextHandle++;
    _target[id] = player.phoneId;
    _pending.add(
      AudioCommand.tone(
        handleId: id,
        tone: tone,
        phoneId: player.phoneId,
        persist: persist,
      ),
    );
    return SoundHandle(id);
  }

  SoundHandle _play(
    SoundCue cue,
    String? phoneId,
    bool loop,
    double volume,
    bool persist,
    Duration fadeIn,
  ) {
    if (!cue.exists) return SoundHandle.none;

    final id = _nextHandle++;
    _target[id] = phoneId;
    _pending.add(
      AudioCommand.play(
        handleId: id,
        cue: cue,
        phoneId: phoneId,
        loop: loop,
        volume: volume,
        persist: persist,
        fadeInMs: fadeIn.inMilliseconds,
      ),
    );
    return SoundHandle(id);
  }

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) {
    if (handle.id < 0) return;
    _pending.add(
      AudioCommand.stop(
        handleId: handle.id,
        fadeMs: fade.inMilliseconds,
        phoneId: _target.remove(handle.id),
      ),
    );
  }

  @override
  void stopRoundSounds() {
    _target.clear();
    _pending.add(AudioCommand.stopRound());
  }
}
