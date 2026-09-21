/// What a game says when it wants something heard.
///
/// A table of phones is not one speaker, and pretending otherwise is what makes
/// multi-device audio sound wrong. So there are two verbs, and choosing between
/// them is a real decision a game makes:
///
/// ```dart
/// context.audio.playGeneral(Sounds.countdown);          // the table's speaker
/// context.audio.playOnPhone(dead, dead.soundSad);       // that person's phone
/// ```
///
/// [playGeneral] is the room — music, the countdown, the goal horn — and one
/// device carries it, because eight phones playing one clip at eight distances
/// with eight codec latencies is a flam, not a chord. [playOnPhone] is the
/// person: Green dies, and the phone in Green's hand says so. That is
/// directional information — you know it is *you* before you have found your
/// character on the board — and it is the thing a phone-per-player table can do
/// that a television cannot.
///
/// Both are raised by rules, so both live on the host. The emitter arrives in
/// `BoardContext` rather than as a member of `GameSim`, and that is not
/// tidiness: every game says `implements GameSim`, Dart makes an `implements`
/// clause carry every member including ones with a body, and adding a method
/// there would break all thirteen games at once and force each to write an
/// empty one. The same reasoning is already written down for `PlayerPresence`.
library;

import '../model/player.dart';
import 'sound_cue.dart';

/// The audio a [GameSim] can make.
abstract class GameAudio {
  /// Play on the table's speaker — the host's phone.
  ///
  /// Returns a handle even for a cue with no asset, so a caller can store and
  /// stop it without ever checking for null.
  ///
  /// [persist] hands the sound to the *session* instead of the round. Without
  /// it, everything a round started is stopped when the round ends — see
  /// [stopRoundSounds] — which is what stops an abandoned round leaving a loop
  /// playing forever with nobody holding its handle.
  SoundHandle playGeneral(
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
  });

  /// Play on one player's phone, and nowhere else.
  ///
  /// A phone that has gone, or whose owner has muted it, is **silence**. It
  /// never falls back to the host: a sound coming from the wrong side of the
  /// table is worse information than no sound at all.
  SoundHandle playOnPhone(
    Player player,
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
  });

  /// Stop something that is playing, or cancel something that has not started.
  ///
  /// Both cases are real. Cues are scheduled on the shared timeline, so a play
  /// at T and a stop at T+200ms can both be sitting in a phone's queue before
  /// its clock has reached T at all. Stopping a sound that already finished is
  /// a no-op rather than an error.
  ///
  /// [fade] is what music wants and a one-shot does not; zero cuts.
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero});

  /// Stop everything this round started, keeping anything marked `persist`.
  ///
  /// Called by the platform at every round boundary — an outcome, a reset, a
  /// return to the lobby — so a game never has to remember, and a game that
  /// crashed mid-round still goes quiet.
  void stopRoundSounds();
}

/// The audio a [GameView] can make: this device, and only now.
///
/// Deliberately a different type from [GameAudio] rather than the same one with
/// fewer methods. A view runs on every phone at once, so a `playGeneral` from
/// inside one would mean eight phones each asking the host to play the same
/// thing — which is not a smaller version of the authoritative API, it is a
/// bug. Anything the table should hear is a decision the rules make.
///
/// What is left is real and worth having: a tick under a finger on this phone's
/// own glass, which has no shared instant to agree with and should not wait
/// eighty milliseconds to acknowledge a touch.
abstract class LocalAudio {
  SoundHandle play(SoundCue cue, {bool loop = false, double volume = 1.0});

  void stopSound(SoundHandle handle, {Duration fade = Duration.zero});
}

/// Accepts everything and makes no sound.
///
/// What a context built without a session behind it uses — a sim under test, a
/// widget preview — so that neither a game nor a test ever has to be handed a
/// fake speaker or check whether it has one.
class SilentGameAudio implements GameAudio {
  const SilentGameAudio();

  @override
  SoundHandle playGeneral(
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
  }) => SoundHandle.none;

  @override
  SoundHandle playOnPhone(
    Player player,
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
  }) => SoundHandle.none;

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) {}

  @override
  void stopRoundSounds() {}
}

/// The same, for a view with no session behind it.
class SilentLocalAudio implements LocalAudio {
  const SilentLocalAudio();

  @override
  SoundHandle play(SoundCue cue, {bool loop = false, double volume = 1.0}) =>
      SoundHandle.none;

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) {}
}

/// One instruction on its way to a phone.
///
/// Deliberately flat and JSON-shaped: this is what goes on the wire, and
/// keeping the queue in the same shape as the message means there is no second
/// representation to keep in step with the first.
class AudioCommand {
  AudioCommand.play({
    required this.handleId,
    required this.cue,
    required this.phoneId,
    required this.loop,
    required this.volume,
    required this.persist,
  }) : op = AudioOp.play,
       fadeMs = 0;

  /// [phoneId] is where the sound was *started*, not where the stop was
  /// decided. A stop has to follow its handle to the phone that holds it, or
  /// the message goes to the host and the sound plays on across the table.
  AudioCommand.stop({
    required this.handleId,
    required this.fadeMs,
    required this.phoneId,
  }) : op = AudioOp.stop,
       cue = null,
       loop = false,
       volume = 1.0,
       persist = false;

  AudioCommand.stopRound()
    : op = AudioOp.stopRound,
      handleId = -1,
      cue = null,
      phoneId = null,
      loop = false,
      volume = 1.0,
      persist = false,
      fadeMs = 0;

  final String op;
  final int handleId;
  final SoundCue? cue;

  /// Which phone, or null for the table's speaker.
  final String? phoneId;

  final bool loop;
  final double volume;
  final bool persist;
  final int fadeMs;

  /// Whether every phone needs to hear about this.
  ///
  /// Only the end of a round is: each phone knows what *it* was told to play,
  /// so silencing the round is one message to all of them rather than the host
  /// keeping a ledger of who is playing what. Everything else goes to exactly
  /// one device — the phone named in [phoneId], or the host when that is null.
  bool get isBroadcast => op == AudioOp.stopRound;

  /// [atMs] is stamped by the host when the queue is drained, never here.
  ///
  /// The stamp is the sim time of the step that raised the cue, which is the
  /// same timestamp as the snapshot broadcast in that tick — so the sound and
  /// the picture that caused it land on a phone at the same instant of the
  /// shared timeline instead of eighty milliseconds apart.
  Map<String, dynamic> toJson(double atMs) => {
    'op': op,
    'h': handleId,
    'at': atMs,
    if (cue != null) 'cue': cue!.id,
    if (cue?.asset != null) 'asset': cue!.asset,
    if (phoneId != null) 'phoneId': phoneId,
    if (loop) 'loop': true,
    if (volume != 1.0) 'vol': volume,
    if (persist) 'persist': true,
    if (fadeMs > 0) 'fade': fadeMs,
  };
}

/// The three things a phone can be told about sound.
class AudioOp {
  static const play = 'play';
  static const stop = 'stop';

  /// End of round: drop everything that was not marked `persist`.
  static const stopRound = 'stopRound';
}

/// The host's implementation: a queue, not a speaker.
///
/// **Emitting is queueing, not I/O.** Cues raised during `step` go in here and
/// the host drains them after the step, exactly as entity changes already are.
/// A step that reached an audio device directly would be a step that cannot be
/// replayed, and the fixed timestep exists precisely so that it can be.
class RoundAudio implements GameAudio {
  RoundAudio();

  final _pending = <AudioCommand>[];

  /// Monotonic, and the reason handles are safe to mint inside a step. Starts
  /// at 1 so that zero is never a valid handle.
  int _nextHandle = 1;

  /// Where each live handle was started, so a later stop can be sent to the
  /// same phone. Kept because the game holds the handle for as long as it
  /// likes and the host is the only thing that knows where it went.
  ///
  /// Emptied at the end of the round, which is also when every handle in it
  /// stops meaning anything.
  final _target = <int, String?>{};

  /// Everything queued since the last drain, and empties the queue.
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
  }) => _play(cue, null, loop, volume, persist);

  @override
  SoundHandle playOnPhone(
    Player player,
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
  }) => _play(cue, player.phoneId, loop, volume, persist);

  SoundHandle _play(
    SoundCue cue,
    String? phoneId,
    bool loop,
    double volume,
    bool persist,
  ) {
    // A cue with no asset is a silence, and a silence still gets a handle: a
    // game that stores one and stops it later must not have to care which of
    // the library has been recorded yet.
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
      ),
    );
    return SoundHandle(id);
  }

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) {
    // [SoundHandle.none] — a cue with no asset. Nothing was ever started, so
    // there is nothing to tell a phone about.
    if (handle.id < 0) return;
    _pending.add(
      AudioCommand.stop(
        handleId: handle.id,
        fadeMs: fade.inMilliseconds,
        phoneId: _target.remove(handle.id),
      ),
    );
  }

  /// One message rather than a stop per handle: the phones already know which
  /// sounds were marked `persist`, because they were told when each one
  /// started, so they can work out what to keep without the host tracking it.
  @override
  void stopRoundSounds() {
    _target.clear();
    _pending.add(AudioCommand.stopRound());
  }
}
