import '../net/protocol.dart';

/// What the host needs from a minigame, and nothing more.
///
/// Every implementation is a headless authoritative world: no Flutter, no
/// Flame, no knowledge of which pixels are on which phone. The host drives all
/// of them through the same loop, so adding a game means writing one of these
/// and adding it to the catalog — the transport, layout, snapshot and
/// interpolation paths never learn its name.
abstract class MiniGameSim {
  /// Static description of every entity that can ever appear, sent once at
  /// start. Entities that are not currently in play simply do not show up in
  /// [entityStates]; the renderer draws only what a snapshot mentions, which is
  /// what lets balls spawn and vanish without a protocol message.
  List<EntitySpec> get specs;

  int get tick;

  /// True once the win condition is met. The host stops the loop and moves the
  /// playlist along.
  bool get won;

  /// Per-game extras for the `worldInit` message — a sling anchor, a target
  /// score. Kept as loose data so a new game needs no new message type.
  Map<String, dynamic> worldInitExtras();

  /// A touch, already converted from that phone's local pixels to world space.
  void onTouch({
    required String phoneId,
    required double worldX,
    required double worldY,
    required String phase,
  });

  void step(double dt);

  List<EntityState> entityStates();

  /// The slingshot band, for games that have one. Null otherwise, and then the
  /// field is left out of the snapshot entirely.
  SlingState? slingState();

  /// Live progress for the on-screen readout, or null for games without one.
  GameProgress? get progress;

  void reset();
}

/// "7 / 10 caught" — whatever the player is working towards.
class GameProgress {
  const GameProgress({
    required this.value,
    required this.goal,
    required this.label,
  });

  final int value;
  final int goal;
  final String label;

  Map<String, dynamic> toJson() => {
    'value': value,
    'goal': goal,
    'label': label,
  };

  static GameProgress fromJson(Map<String, dynamic> j) => GameProgress(
    value: (j['value'] as num).toInt(),
    goal: (j['goal'] as num).toInt(),
    label: j['label'] as String,
  );
}
