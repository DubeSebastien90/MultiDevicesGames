/// Tunables for the Arena fighter game.
class ArenaConfig {
  const ArenaConfig._();

  // -- movement ---------------------------------------------------------------
  static const double moveSpeed = 8.0; // cm/s (world units/s)
  static const double characterRadius = 0.6; // cm

  // -- health -----------------------------------------------------------------
  static const int maxHp = 100;
  static const int attackDamage = 25;

  // -- attack -----------------------------------------------------------------
  static const double attackRange = 2.5; // cm
  static const double attackArc = 0.7; // rad (~40 deg)
  static const double attackCooldown = 1.0; // seconds
  static const double attackFlash = 0.2; // seconds the cone shows

  // -- block ------------------------------------------------------------------
  static const double blockCooldown = 2.0; // seconds
  static const double blockMaxDuration = 1.5; // seconds

  // -- status effects ---------------------------------------------------------
  static const double stunDuration = 1.5; // seconds
  static const double spawnInvincibility = 2.0; // seconds

  // -- scoring ----------------------------------------------------------------
  static const int pointsPerKill = 10;
  static const int pointsForWinning = 25;

  // -- countdown --------------------------------------------------------------
  static const double countdownSeconds = 3.0;

  // -- gesture thresholds -----------------------------------------------------
  static const double minMoveDistance = 0.8; // cm
  static const int tapMaxMs = 250;
  static const int blockHoldMs = 350;

  // -- joystick ---------------------------------------------------------------
  /// Full tilt: the distance from the anchor at which the fighter runs at
  /// [moveSpeed], and where the drawn knob stops following the finger. Pushing
  /// further still steers — it just cannot go faster or look more pushed.
  static const double joystickRadius = 1.65; // cm

  static const double joystickKnobRadius = 0.56; // cm

  /// Faint throughout: the stick sits under the finger, over a floor somebody
  /// may be fighting on, and it is feedback rather than furniture.
  static const int joystickWellAlpha = 24;
  static const int joystickRingAlpha = 70;
  static const int joystickDeadZoneAlpha = 45;
  static const int joystickKnobAlpha = 130;

  /// How hard the stick is pushed, from a finger [distance] out of the anchor:
  /// 0 inside the dead zone, 1 at [joystickRadius] and beyond.
  ///
  /// The ramp starts where the dead zone ends rather than at the anchor, so
  /// the first distance that moves a fighter at all moves them slowly. A jump
  /// straight to half speed the instant the dead zone is crossed is the thing
  /// that makes an analogue stick feel like a digital one.
  static double moveScaleFor(double distance) {
    if (distance <= minMoveDistance) return 0;
    final span = joystickRadius - minMoveDistance;
    if (span <= 0) return 1;
    final t = (distance - minMoveDistance) / span;
    return t < 1 ? t : 1;
  }

  // -- player colours (ARGB ints) ---------------------------------------------
  static const List<int> playerColors = [
    0xFFE63946, // red
    0xFF457B9D, // blue
    0xFF2A9D8F, // teal
    0xFFE9C46A, // yellow
    0xFFF4A261, // orange
    0xFF6A0572, // purple
    0xFF1D3557, // navy
    0xFF8AC926, // lime
  ];
}
