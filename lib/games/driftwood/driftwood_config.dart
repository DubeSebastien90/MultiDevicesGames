/// Tunables for Driftwood.
class DriftwoodConfig {
  const DriftwoodConfig._();

  /// World units per second the log travels downstream, whatever anybody does.
  /// Fixed rather than player-driven, which is what bounds a round without a
  /// separate clock: it always ends within `board.width / currentSpeed`.
  static const double currentSpeed = 6.5;

  static const double logRadius = 0.8;
  static const double rockRadius = 0.9;

  /// Added to vertical speed by one tap, toward wherever the tap landed.
  static const double steerImpulse = 10.0;

  /// How hard vertical speed decays, per second. A tap is a nudge kept alive
  /// only by more taps, not a heading set once and forgotten.
  static const double steerDamping = 1.6;

  static const double vyMax = 9.0;

  /// How far a tap may land from the log and still steer it — a phone only
  /// influences the log while it is actually passing that screen.
  static const double reachWorld = 8.0;

  static const int hazardCount = 3;

  /// Rocks sit between these two fractions of the board's width. Kept clear of
  /// the first half so a short table's very first seam is never straddled by
  /// one — see the seam-crossing test, which relies on that gap.
  static const double hazardStartFraction = 0.6;
  static const double hazardEndFraction = 0.92;

  /// How far off the centreline a rock sits, as a fraction of the half lane
  /// height. Comfortably inside `logRadius + rockRadius` so an unsteered log
  /// heading straight down the middle collides with every one of them —
  /// dodging is not optional, it is the whole game.
  static const double hazardOffsetFraction = 0.35;

  static const double startMarginFraction = 0.06;
  static const double finishMarginFraction = 0.04;

  static const int winBonus = 8;

  static const int colorLog = 0xFF8B5A2B;
  static const int colorRock = 0xFF6E7580;
}
