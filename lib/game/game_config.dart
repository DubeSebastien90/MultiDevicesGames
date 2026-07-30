/// Tunables for the v1 slingshot.
///
/// Kept as plain data in one place: "games as downloadable definitions" is a
/// later goal, and the cheapest way to keep that door open is to never bury a
/// number inside logic.
class GameConfig {
  const GameConfig();

  /// World units per millimetre, shared by every phone.
  ///
  /// 0.1 means **1 world unit = 1 cm**, which puts a two-phone board at roughly
  /// 32 x 7 units — comfortably inside the 0.1..10 range Box2D is tuned for.
  static const double mmToWorld = 0.1;

  /// Physics steps per second (fixed timestep, so the sim is deterministic).
  static const int simHz = 60;

  /// Snapshots per second. Matching [simHz] keeps clients from ever having to
  /// extrapolate far, which matters most exactly at the seam.
  static const int broadcastHz = 60;

  /// Gravity in world units/s², positive = down (y grows downward everywhere).
  ///
  /// Not real gravity: at 1 unit = 1 cm, 9.81 m/s² would be 981 units/s² and the
  /// bird would cross both screens in a blink.
  ///
  /// This is tuned together with [impulsePerPull] against a hard fact about a
  /// two-phone board: it is ~31 units wide and only ~7 tall. For a launch at
  /// angle θ the apex-to-range ratio is fixed at `tan(θ)/4`, so crossing 24
  /// units while rising less than 3 means shooting flat — around 20°. These
  /// values put that shot at roughly a 1.8 second flight, which is slow enough
  /// to watch the bird cross the gap and fast enough not to feel broken.
  static const double gravity = 6.3;

  static const double birdRadius = 0.6; // 12mm across
  static const double birdDensity = 1.0;
  static const double birdRestitution = 0.35;
  static const double birdDamping = 0.02;

  /// How far past the bird's edge a grab still counts (fingers are wide).
  static const double grabSlack = 1.0; // 10mm

  /// Maximum pull distance from the anchor. 30mm is about as far as a thumb
  /// travels comfortably without lifting off the glass.
  static const double maxPull = 3.0;

  /// Impulse magnitude per world unit of pull, for a board [referenceBoardWidth]
  /// wide. The sim scales it for other widths — see [referenceBoardWidth].
  static const double impulsePerPull = 6.2;

  /// The board this game's feel was tuned against: two ~152mm phones side by
  /// side. Range goes as the square of launch speed, so the sim scales the
  /// impulse by `sqrt(width / referenceBoardWidth)` and a full pull covers about
  /// the same *fraction* of the board whether there are two phones or four.
  static const double referenceBoardWidth = 31.0;

  /// Anchor position as a fraction of the board. Far enough in from the left
  /// edge that a full [maxPull] backwards still lands on the glass.
  static const double anchorXFraction = 0.14;
  static const double anchorYFraction = 0.45;

  /// Auto-reset triggers.
  static const double restSpeed = 0.35; // world units/s
  static const Duration restDelay = Duration(milliseconds: 1200);
  static const Duration maxFlightTime = Duration(seconds: 9);

  /// How far outside the board an entity may drift before we call it lost.
  static const double outOfBoundsMargin = 8.0;

  // Colours are chosen host-side so every screen agrees exactly.
  static const int colorBird = 0xFFFF6B4A;
  static const int colorTarget = 0xFF4ECDC4;
  static const int colorTargetAlt = 0xFFFFD166;
  static const int colorGround = 0xFF2E4057;
}
