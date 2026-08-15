/// Tunables for Push of War.
class PushOfWarConfig {
  const PushOfWarConfig._();

  static const double ballRadius = 1.0;
  static const double ballDensity = 1.0;
  static const double ballRestitution = 0.3;

  /// How fast the ball loses speed. Without this a single tap would coast
  /// forever; with it the ball needs to keep being pushed to keep moving,
  /// which is what makes it a tug of war rather than one shove each.
  static const double ballLinearDamping = 0.8;

  /// Impulse applied to the ball per tap, away from the tapper's own side.
  static const double pushImpulse = 6.0;

  /// A phone cannot register taps faster than this — guards against a held
  /// finger reporting as a stream of downs.
  static const double minTapIntervalSeconds = 0.05;

  /// Goal lines sit this fraction of the board's width in from each end.
  static const double goalMarginFraction = 0.08;

  /// Hard backstop: nobody has pushed it home by this many seconds and it's a
  /// stalemate.
  static const double maxRoundSeconds = 90.0;

  /// Points split across the winning team when the ball crosses a goal line.
  static const int winPoints = 5;

  static const int colorBall = 0xFFF4F4F4;
  static const int colorTeamA = 0xFF2F6FED;
  static const int colorTeamB = 0xFFED4B2F;
}
