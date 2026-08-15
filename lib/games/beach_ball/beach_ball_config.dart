/// Tunables for Beach Ball.
///
/// Kept as plain data next to the game that uses them, same as every other
/// game's config.
class BeachBallConfig {
  const BeachBallConfig._();

  /// Gravity in world units/s², positive = down.
  ///
  /// The board stands roughly one phone tall (~15 units for a 152mm phone),
  /// so this is tuned gentler than Ball Bin's fall — the ball needs to hang in
  /// the air long enough to be worth reaching for.
  static const double gravity = 7.5;

  static const double ballRadius = 0.7; // 14mm across
  static const double ballDensity = 0.5;
  static const double ballRestitution = 0.3;

  /// How far a tap may land from the ball's centre and still count as a bump.
  static const double reachRadius = 3.4; // 34mm — a generous poke

  /// The bump is a direct velocity set, not an added impulse — a clean,
  /// repeatable "hit" rather than physics compounding on itself.
  static const double bumpSpeed = 10.5;

  /// How much a tap can steer the ball sideways, as a fraction of the
  /// distance between the tap and the ball's centre.
  static const double aimFactor = 1.6;
  static const double maxAimVx = 7.0;

  /// A bump only connects while the ball is falling — tapping it on the way
  /// up does nothing, so the table cannot just spam it into a permanent
  /// hover.
  static const double mustBeFallingVy = 0.2;

  /// Minimum time between two bumps, so a held or double finger cannot land
  /// twice on the same fall.
  static const double bumpCooldown = 0.15;

  /// Survive this long, uninterrupted, and the table wins.
  static const double targetSeconds = 25.0;

  static const int colorBall = 0xFFFFD166;
  static const int colorGroundLine = 0xFFFF5C6C;
}
