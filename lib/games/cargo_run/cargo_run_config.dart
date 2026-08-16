/// Tunables for Cargo Run.
///
/// World units are centimetres, same as everything else on the platform.
class CargoRunConfig {
  const CargoRunConfig._();

  /// A round, in seconds.
  static const double roundSeconds = 45;

  /// How fast a crate rolls down the belt, in world units per second — the
  /// same order of magnitude as Subway Skater's scrolling traffic, since it is
  /// covering the same kind of ground.
  static const double crateSpeed = 14;

  static const double crateRadius = 1.1;

  /// How close a tap has to land to a crate's centre to catch it. Generous —
  /// fingers are wide and the belt does not wait.
  static const double tapReach = crateRadius * 2.5;

  /// Seconds between spawns, at the start of the round and at the end.
  static const double spawnGapStart = 1.0;
  static const double spawnGapEnd = 0.5;

  /// Fraction of the round after which spawns are at [spawnGapEnd].
  static const double rampFraction = 0.6;

  /// Chance a spawned crate is worth catching rather than worth dodging.
  static const double goodChance = 0.7;

  static const int pointsGood = 1;
  static const int pointsBadPenalty = 1;

  /// The pool: the most crates in flight at once. Sized so a long table never
  /// runs dry mid-round.
  static int poolSize(int playerCount) => (playerCount * 5).clamp(10, 48);

  // ----------------------------------------------------------------- paint
  static const int colorBackground = 0xFF14202B;
  static const int colorPlayfield = 0xFF1D2E3D;
  static const int colorLane = 0xFF27404F;
  static const int colorGood = 0xFF57C785;
  static const int colorBad = 0xFFE0555A;
}
