/// Tunables for Pitch Cars, kept as plain data next to the game that uses
/// them — none of this is the platform's business.
class PitchCarsConfig {
  const PitchCarsConfig._();
  static const double trackWidthWorld = 3.0;

  static const double lineAmplitudeWorld = 3.0;

  /// A deliberate, tuned hook rather than a subtle wiggle — the catalog of
  /// motifs `PitchCarsLayout` produces is closed, so every corner's
  /// geometry is known in advance and this can be generous rather than
  /// conservative.
  static const double cornerAmplitudeWorld = 1.8;

  /// How many points the Catmull-Rom spline is sampled at between each
  /// pair of control points — `PitchTrack.waypoints`'s density.
  static const int splineSamplesPerSegment = 8;

  static const double carRadius = 0.25;

  static const double carVisualRadius = 0.25;

  static const double startLaneOffsetWorld = 0.65;

  static const double startRowSpacingWorld = 1.4;

  static const double carDensity = 4.0;
  static const double carRestitution = 0.5;
  static const double carFriction = 0.3;

  static const double carLinearDamping = 1.0;

  static const double carAngularDamping = 2.0;

  static const double stallDisplacement = 0.1;
  static const Duration stallTimeout = Duration(seconds: 2);

  static const double grabSlack = 1.0;

  static const double maxPull = 3.0;

  static const double impulsePerPull = 5.5;
  static const double restSpeed = 0.3;
  static const Duration restDelay = Duration(milliseconds: 600);
  static const Duration maxFlightTime = Duration(seconds: 6);
  static const Duration hitGraceWindow = Duration(milliseconds: 250);

  static const int colorTrack = 0xFF2E4057;

  static const int finishLineCols = 6;
  static const int finishLineRows = 4;
  static const int finishLineColorA = 0xFF000000;
  static const int finishLineColorB = 0xFFFFFFFF;

  /// Points the race winner nets in a full 8-player race, matching
  /// `ReactionConfig.bestScore`.
  static const int bestScore = 30;

  /// Must match `PitchCarsGame.manifest.players.max` — the scoring ladder's
  /// fixed size, so a small race occupies its top slots instead of
  /// stretching to fill it.
  static const int maxPlayers = 8;
}
