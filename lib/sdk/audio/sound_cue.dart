/// A sound, named rather than loaded.
///
/// The same indirection as `PlayerArt`, for the same reason: a game says *what*
/// it wants heard, and the SDK decides what that is on disk. A cue is a value —
/// it can be a `const` on a game's config class, compared, and put in a table —
/// and it holds no resources, so nothing is opened until something is played.
library;

/// One playable sound.
///
/// [asset] is **nullable, and every SDK cue's is null today.** That is the
/// design, not a gap: the library can be named in full before a single file
/// exists, games can be written against `Sounds.win` now, and a cue with no
/// asset plays silence instead of throwing. The day the file lands, one line
/// changes and every game that already referenced it starts making a noise.
class SoundCue {
  const SoundCue(this.id, [this.asset]);

  /// A game's own sound, which needs no entry in any table.
  ///
  /// The path is its own id: two calls naming the same file are the same cue,
  /// which is what a mixer wants when asked to stop 'that one'.
  const SoundCue.asset(String path)
      : id = path,
        asset = path;

  /// Stable and wire-visible: 'countdown', 'green.sad'. Never derived from the
  /// path, so the file can be renamed or re-recorded without invalidating
  /// anything that referred to it.
  final String id;

  /// Where it lives, or null when it does not exist yet.
  final String? asset;

  /// Whether playing this can make any sound at all.
  bool get exists => asset != null;

  @override
  String toString() => 'SoundCue($id)';
}

/// A running sound, so it can be stopped.
///
/// An **id, not an object**. The thing actually making noise lives on another
/// device — even for a general sound, since the host plays through its own
/// client side like every other phone — so there is nothing on the sim side to
/// hold a reference to. The id is minted by the host and travels in the
/// message; stopping is a second message carrying the same id.
///
/// Ids come from a counter and never from a clock. `GameSim.step` is required
/// to be pure with respect to wall-clock time — no `DateTime.now()`, no timers
/// — and that purity is what keeps the timeline reproducible and the snapshots
/// evenly spaced. A handle minted from the clock would break the one rule the
/// whole engine rests on, quietly, and only under replay.
class SoundHandle {
  const SoundHandle(this.id);

  final int id;

  /// A handle to nothing: what a play that could never make a sound returns,
  /// so a caller can still store it and stop it without a null check.
  static const none = SoundHandle(-1);

  @override
  bool operator ==(Object other) => other is SoundHandle && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SoundHandle($id)';
}
