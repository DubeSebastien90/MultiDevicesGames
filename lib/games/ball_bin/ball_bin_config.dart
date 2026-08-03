/// Tunables for the ball bin.
///
/// Its board is the other way round from the slingshot's: one phone wide and
/// several tall, so everything here is tuned for a fall of roughly 14-21 world
/// units rather than a flight across 31.
class BallBinConfig {
  const BallBinConfig._();

  /// Catch this many and the round is won.
  static const int goal = 10;

  /// Real-ish gravity would end a 20-unit drop in under a second. This gives
  /// about two seconds top to bottom, enough time to move the bin across a
  /// seam and watch the ball come to you.
  static const double gravity = 9.0;

  static const double ballRadius = 0.5; // 10mm across
  static const double ballDensity = 0.8;
  static const double ballRestitution = 0.25;

  /// How many balls may exist at once. Also the size of the entity pool.
  static const int maxLiveBalls = 6;

  /// Gap between spawns. Tightens as the score climbs, down to [minSpawnGap].
  static const Duration spawnGap = Duration(milliseconds: 1600);
  static const Duration minSpawnGap = Duration(milliseconds: 700);

  /// Fraction of the goal at which spawning is at its fastest.
  static const double rampFraction = 0.8;

  /// The bin, in world units. Wide enough to be catchable on a ~15 unit board,
  /// narrow enough that aiming matters.
  static const double binWidth = 4.2;
  static const double binHeight = 1.8;
  static const double binWallThickness = 0.28;

  /// How far above the bottom edge the bin's floor sits.
  static const double binBottomMargin = 1.2;

  /// How far past the bin's rim a grab still counts (fingers are wide).
  static const double binGrabSlack = 1.6;

  /// Bin travel per second when chasing the finger. Fast enough to feel
  /// direct, slow enough that it cannot teleport across the board.
  static const double binSpeed = 34.0;

  /// Balls spawn within this fraction of the board width, centred — never so
  /// close to a wall that the bin cannot reach them.
  static const double spawnInset = 0.12;

  static const int colorBall = 0xFFFFD166;
  static const int colorBallAlt = 0xFF7FD1C4;
  static const int colorBin = 0xFF4ECDC4;
  static const int colorFloor = 0xFF2E4057;
}
