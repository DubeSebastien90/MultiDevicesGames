/// Tunables for Rally.
class RallyConfig {
  const RallyConfig._();

  static const double ballRadius = 0.9;
  static const double ballDensity = 1.0;

  /// Bounce off the lane's top and bottom edges — high, so a rally stays
  /// lively instead of dying against the rails.
  static const double wallRestitution = 0.95;

  static const double serveSpeedX = 5.0;
  static const double serveSpeedY = 1.6;

  /// How far a tap may land from the ball's own edge and still return it —
  /// a little grabbier than the ball itself, the same idea as Pitch Cars'
  /// `grabSlack`.
  static const double hitReach = 2.2;

  /// Added to the ball's horizontal speed on every clean return, so a long
  /// rally gets harder to keep alive rather than settling into one rhythm.
  static const double hitSpeedBoost = 0.5;
  static const double maxBallSpeedX = 9.0;
  static const double maxBallSpeedY = 6.0;

  /// How much a tap's vertical offset from the ball's centre bends the
  /// return: tap above the ball and it comes back low, tap below and it
  /// lifts — the one piece of aim a return gives you.
  static const double deflectFactor = 2.0;

  /// Guards against one finger reporting as a burst of downs.
  static const double hitCooldownSeconds = 0.08;

  static const int targetPoints = 5;
  static const int pointValue = 1;
  static const double maxRoundSeconds = 90.0;

  static const int colorBall = 0xFFF4F4F4;
  static const int colorTeamA = 0xFF2FA7ED;
  static const int colorTeamB = 0xFFED8A2F;
}
