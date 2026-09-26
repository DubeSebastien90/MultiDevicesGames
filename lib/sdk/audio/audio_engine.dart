/// One phone's ear: what it has been told to play, and when to play it.
///
/// Every device runs one of these, the host included — the host's own screen is
/// a viewport receiving snapshots like any other, and its speaker is reached
/// the same way. A sim never touches an audio device; it emits a cue, the host
/// sends it, and the phone that should hear it decides when.
///
/// **When** is the interesting part. A cue is not played on arrival. It carries
/// the sim time of the step that raised it, and it fires when *this* phone's
/// delayed render clock passes that instant — the same clock, and the same
/// delay, that makes two screens agree about where the ball is.
///
/// Playing on arrival is the tempting shortcut and it is wrong. A player dying
/// at time T appears on every screen at T + 80ms, host included, because that
/// is what the interpolation buffer is for. A sound played the moment the
/// packet lands arrives *before* the picture that explains it — and
/// sound-before-picture is by far the more noticeable direction of error.
/// Scheduling also makes a general cue and a targeted one land together for
/// free, which matters the first time a game does both for one event.
library;

import '../platform_config.dart';
import 'audio_output.dart';
import 'game_audio.dart';
import 'sound_cue.dart';
import 'tone.dart';
import 'tone_output.dart';

/// A cue waiting for the timeline to reach it.
class _Scheduled {
  _Scheduled({
    required this.handleId,
    required this.asset,
    required this.atMs,
    required this.loop,
    required this.volume,
    required this.persist,
    this.tone,
  });

  final int handleId;

  /// The recording to play — or, for a tone, empty and [tone] set instead.
  final String asset;
  final Tone? tone;
  final double atMs;
  final bool loop;
  final double volume;
  final bool persist;
}

/// A sound that has started, and the two facts that decide when it ends.
class _Live {
  const _Live({
    required this.persist,
    required this.loop,
    this.tone,
    this.startMs = 0,
  });

  /// Set for a synthesised tone, which is moved every frame rather than left
  /// to play; [startMs] is where on the timeline its glide began.
  final Tone? tone;
  final double startMs;

  /// Survives the round that started it.
  final bool persist;

  /// Exempt from the voice cap: music is never what should be culled.
  final bool loop;
}

class AudioEngine implements LocalAudio {
  AudioEngine({AudioOutput? output, ToneOutput? tones, this.muted = false})
    : _output = output ?? SilentAudioOutput(),
      _tones = tones ?? SilentToneOutput() {
    // A one-shot that has played to the end is not a live voice any more.
    // Without this the voice cap below is a one-way ratchet: eight cues into a
    // round, [_live] is full of sounds that finished seconds ago and every cue
    // after them is dropped in silence until the round ends and clears it.
    _output.onFinished = _finished;
  }

  /// A sound ended on its own. Frees the seat, and nothing else — the output
  /// has already let go of its player.
  void _finished(int handleId) => _live.remove(handleId);

  final AudioOutput _output;

  /// Where tones are synthesised: a different engine from [_output], because
  /// the one that plays files cannot bend pitch on iOS.
  final ToneOutput _tones;

  ToneOutput get tones => _tones;

  /// Silence, honoured centrally so no game has to check it.
  ///
  /// Muting does not remember what it suppressed: unmuting starts the *next*
  /// sound, not the one that was playing when the switch was thrown. A loop
  /// resuming from nowhere thirty seconds later is a worse surprise than a
  /// silence that simply ends.
  bool muted;

  AudioOutput get output => _output;

  /// Cues whose instant has not arrived, oldest first.
  final _pending = <_Scheduled>[];

  /// Handles started and not yet stopped.
  final _live = <int, _Live>{};

  /// How far past its instant a cue may be fired.
  ///
  /// A phone that reconnects, or one whose app was suspended, receives a burst
  /// of cues whose moments are all in the past. Firing them would replay a
  /// minute of the round into somebody's ear at once. A sound played late is
  /// worse than a sound not played, so they are dropped.
  static const staleMs = 400.0;

  /// A ceiling on *simultaneous* one-shots — which is only meaningful because
  /// [_finished] takes a sound out of the count when it ends.
  ///
  /// Twelve: one voice per seat at the biggest table, plus room for the sounds
  /// that belong to nobody — an explosion, a bounce, a countdown tick — which
  /// the old eight had fighting the players for space. Loops are exempt on top
  /// of that, so music never counts and is never culled.
  ///
  /// Chosen against what is underneath it rather than picked round: the output
  /// pools sixteen native players, and Android's SoundPool is built with
  /// thirty-two streams. Twelve leaves both with room to spare, which is the
  /// point — the moment a burst reaches the platform's own ceiling, *it*
  /// decides what to cut, by its own rules, differently on every phone at the
  /// table.
  ///
  /// What happens at the ceiling depends on who is asking, and the two answers
  /// are opposite on purpose:
  ///
  /// * A **round's cue** is dropped. It is one of many the game is raising, it
  ///   was meant to be heard among seven others, and cutting one of those
  ///   short to make room would trade a sound somebody is hearing for one they
  ///   are not.
  /// * A **local sound** steals the oldest voice. It is the answer to a finger
  ///   that has just touched this glass — the tap tick, the placement screen's
  ///   pokes — and silence in reply to your own hand reads as a broken app,
  ///   not as a busy mixer. The oldest one-shot is the one nearest its end, so
  ///   it is the cheapest thing in the room to cut.
  static const maxVoices = 12;

  /// Local ids, kept negative so they can never collide with the host's, which
  /// count up from one. `-1` is [SoundHandle.none].
  int _nextLocalHandle = -2;

  /// A message from the host: `HostMsg.sound`.
  void receive(Map<String, dynamic> msg) {
    switch (msg['op'] as String?) {
      case AudioOp.play:
        final asset = msg['asset'] as String?;
        // No asset means the cue exists but the file does not yet. The host
        // sends it anyway so the routing is exercised; there is nothing to
        // play.
        if (asset == null) return;
        _pending.add(
          _Scheduled(
            handleId: (msg['h'] as num).toInt(),
            asset: asset,
            atMs: (msg['at'] as num?)?.toDouble() ?? 0,
            loop: msg['loop'] == true,
            volume: (msg['vol'] as num?)?.toDouble() ?? 1.0,
            persist: msg['persist'] == true,
          ),
        );
        // Bounded, for the phone that stops rendering while the host keeps
        // talking. Dropping the oldest matches the staleness rule: the ones
        // furthest in the past are the ones least worth hearing.
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

  /// Walk the timeline forward. Called once per rendered frame, from the same
  /// place the interpolator is advanced, with the same instant.
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
        // Never stale. A tone is a state, not an event: a phone that arrives
        // late — reconnected, or woken from the background — should join the
        // glide where it has got to, not skip it. [_glide] below works out
        // where that is from the tone's own start.
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
      );
    }
    _glide(renderTimeMs);
  }

  /// Moves every playing tone to where its glide says it is now. Every frame,
  /// on this phone's own clock: nothing about a glide crosses the wire after
  /// it starts, which is what keeps it smooth on a bad connection.
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
    // Exempt from the voice cap, like a loop: it is one oscillator, not a
    // clip, and culling it would leave a hole where a sustained sound was.
    _live[handleId] = _Live(
      persist: persist,
      loop: true,
      tone: tone,
      startMs: atMs,
    );
    final elapsed = nowMs - atMs;
    _tones.start(handleId, tone.hzAt(elapsed), tone.volumeAt(elapsed));
  }

  /// A view's own sound, on this device, now.
  ///
  /// No scheduling: a tap tick on this phone's own glass has no shared instant
  /// to agree with, and waiting eighty milliseconds to acknowledge a finger is
  /// the one thing local feedback exists to avoid.
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
  }) {
    if (muted) return;

    if (!loop && _oneShotCount >= maxVoices) {
      // Local handles are minted negative (see [_nextLocalHandle]), which is
      // what tells a finger's own sound from one the host sent — and which of
      // the two rules above applies.
      final stolen = handleId < 0 ? _oldestOneShot : null;
      if (stolen == null) return;
      _stop(stolen);
    }
    _live[handleId] = _Live(persist: persist, loop: loop);
    // Not awaited: a decode that takes a moment must not stall a render frame,
    // and there is nothing to do with the answer. Failures are the output's to
    // swallow — a missing file is a silence, never a crashed round.
    _output.play(handleId, asset, loop: loop, volume: volume);
  }

  /// The live one-shot that started first, or null if there are none.
  ///
  /// Insertion order, straight off the map — Dart's keeps it — so this is the
  /// sound that has been going longest and therefore the one closest to being
  /// over anyway.
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
    // A cue can be stopped before its instant arrives: with cues scheduled on
    // the delayed timeline, a play at T and a stop at T+200ms are both in this
    // queue while the clock is still short of T. Cancelling is the same
    // operation as stopping, from the game's point of view.
    _pending.removeWhere((c) => c.handleId == handleId);
    final live = _live.remove(handleId);
    if (live == null) return;
    if (live.tone != null) {
      _tones.stop(handleId, fade: fade);
    } else {
      _output.stop(handleId, fade: fade);
    }
  }

  /// End of round, or leaving the game entirely.
  ///
  /// [includingPersistent] false is the round boundary: everything the round
  /// started goes quiet and anything handed to the session — the lobby bed —
  /// plays on.
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
