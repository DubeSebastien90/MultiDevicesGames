/// Tunables for Carousel.
class CarouselConfig {
  const CarouselConfig._();

  /// Backstop: the round ends here even if nobody reaches [targetLandings].
  static const double roundSeconds = 60;

  /// First phone to bank this many landings wins outright.
  static const int targetLandings = 5;

  /// What a landing is worth on the scoreboard.
  static const int pointsPerLanding = 10;

  /// Angular speed a single tap adds, in radians per second.
  static const double tapImpulse = 1.8;

  /// However many taps stack up, the marker never spins faster than this.
  static const double maxOmega = 9.0;

  /// Constant angular deceleration, in radians per second squared — the marker
  /// always eventually stops on its own, tapped or not.
  static const double friction = 2.5;

  /// The soonest two taps from the same phone both count. Stops one thumb
  /// mashing the glass from being strictly better than a single well-timed tap.
  static const double tapCooldown = 0.12;

  /// How long the marker sits still, ignoring taps, right after it lands — long
  /// enough that everyone actually sees where it stopped before it can move
  /// again.
  static const double settleSeconds = 1.2;

  /// World units across.
  static const double markerRadius = 0.9;

  static const int colorMarker = 0xFFF2C14E;
  static const int colorMarkerSettled = 0xFF4EE2A0;
}
