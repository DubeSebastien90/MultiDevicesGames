/// Tunables for Pitch Cars, kept as plain data next to the game that uses
/// them — none of this is the platform's business.
class PitchCarsConfig {
  const PitchCarsConfig._();

  /// The drivable ribbon's width, in world units (1 unit = 1cm). Wide enough
  /// for a car to have real room to aim within, narrow enough that a bad
  /// shot genuinely risks the dead space at the edges.
  static const double trackWidthWorld = 3.0;

  /// How far a "line" track's centerline swings from the board's vertical
  /// centre, before jitter. Forces the curvature that keeps the track from
  /// ever reading as straight.
  static const double lineAmplitudeWorld = 3.0;

  static const double carRadius = 0.5;
  static const double carDensity = 1.0;
  static const double carRestitution = 0.5;
  static const double carFriction = 0.3;

  /// Cars scrub to a stop on their own, unlike a bird in flight.
  static const double carLinearDamping = 0.6;

  /// How far past a car's edge a grab still counts (fingers are wide).
  static const double grabSlack = 1.0;

  /// Maximum pull distance from the car's rest position.
  static const double maxPull = 3.0;

  /// Impulse magnitude per world unit of pull.
  static const double impulsePerPull = 0.8;

  /// Auto-advance-the-turn triggers, once a flick has been launched.
  static const double restSpeed = 0.3;
  static const Duration restDelay = Duration(milliseconds: 600);
  static const Duration maxFlightTime = Duration(seconds: 6);

  /// A collision only excuses a car from the self-fault penalty if the car
  /// left the track within this long of being hit — a graze early in a turn,
  /// followed by the player's own reckless momentum carrying it off-track much
  /// later, still counts as self-fault.
  static const Duration hitGraceWindow = Duration(milliseconds: 250);

  /// Colours are chosen host-side so every screen agrees exactly.
  static const List<int> carColors = [
    0xFFFF6B4A,
    0xFF4ECDC4,
    0xFFFFD166,
    0xFFB388FF,
  ];
  static const int colorTrack = 0xFF2E4057;
}
