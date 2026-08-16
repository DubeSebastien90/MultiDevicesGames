/// Tunables for Plummet.
class PlummetConfig {
  const PlummetConfig._();

  /// Gravity in world units/s², positive = down the shaft.
  static const double gravity = 12.0;

  static const double ballRadius = 0.9;
  static const double ballDensity = 0.6;
  static const double ballFriction = 0.1;

  /// Bounce off the shaft's side walls — lively enough that a graze off a
  /// wall does not just kill all the ball's sideways speed.
  static const double wallRestitution = 0.4;

  /// How far a tap may land from the ball's centre and still count as a
  /// touch — the same reach-gated idea Beach Ball's bump uses.
  static const double reachRadius = 3.2;

  /// A touch is a clean horizontal velocity set, away from the tap — not an
  /// accumulating shove — so every dodge feels the same regardless of how
  /// fast the ball happens to already be moving sideways.
  static const double pushSpeed = 8.5;

  /// Minimum time between two touches, so one finger cannot register twice.
  static const double pushCooldown = 0.12;

  /// Each wall spike covers this fraction of the shaft's width, jutting in
  /// from one side; the rest is the gap the ball has to be steered through.
  static const double spikeWidthFraction = 0.62;

  /// A spike's vertical thickness, as a fraction of one phone's own share of
  /// the shaft's height.
  static const double spikeThicknessFraction = 0.42;

  /// Backstop only — gravity always nets the ball downward, so this is a
  /// safety valve rather than the real ending condition.
  static const double maxRoundSeconds = 60.0;

  static const int bonusPerPhone = 5;

  static const int colorBall = 0xFF6FE3C6;
  static const int colorSpike = 0xFFED4C67;
  static const int colorFloor = 0xFF3FA7FF;
}
