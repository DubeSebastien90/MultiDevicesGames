/// Copycat's tunables, all in one place.
class CopycatConfig {
  const CopycatConfig._();

  /// Replay a sequence this long, correctly, and the team wins.
  static const int targetLength = 8;

  /// How long a tile stays lit while the sequence plays back.
  static const double showSeconds = 0.55;

  /// The dark gap between two tiles in the playback, so the eye can tell where
  /// one ends and the next begins.
  static const double gapSeconds = 0.25;

  /// How long the team has to land the next tap. Reset on every correct tap,
  /// so only a table that has genuinely stalled ever hits it.
  static const double inputTimeoutSeconds = 4.0;

  /// A hard cap on the whole round, so a table that never taps at all still
  /// gets an ending rather than sitting on the placement forever.
  static const double roundSeconds = 120;

  /// Shared out to everybody once the team completes the whole pattern.
  static const int winBonus = 20;

  /// One colour per tile, picked by a hash of the phone id so neighbouring
  /// screens usually differ without any phone needing to know about another.
  static const List<int> palette = [
    0xFFEF4444, // red
    0xFF3B82F6, // blue
    0xFFF59E0B, // amber
    0xFF10B981, // green
    0xFFA855F7, // purple
    0xFFEC4899, // pink
  ];

  /// How dim the unlit tile sits, and how bright it flashes when its turn
  /// comes — the same colour both times, just less or more of it.
  static const double dimAlpha = 0.35;
}
