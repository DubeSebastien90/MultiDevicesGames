/// Tunables for the Dodgeball game.
class DodgeballConfig {
  const DodgeballConfig._();

  // -- movement ---------------------------------------------------------------
  static const double moveSpeed = 8.0; // cm/s
  static const double characterRadius = 0.5; // cm

  // -- dash -------------------------------------------------------------------
  static const double dashSpeed = 28.0; // cm/s (burst speed)
  static const double dashDuration = 0.15; // seconds
  static const double dashCooldown = 2.5; // seconds
  static const double dashInvincibility = 0.2; // seconds (i-frames during dash)

  // -- balls ------------------------------------------------------------------
  static const double ballRadius = 0.3; // cm
  static const double ballBaseSpeed = 5.0; // cm/s
  static const double ballSpeedIncrement = 0.4; // cm/s added per spawn
  static const double ballMaxSpeed = 20.0; // cm/s
  static const double ballSpawnInterval = 3.0; // seconds between spawns
  static const double ballSpawnIntervalMin = 1.0; // minimum interval
  static const double ballSpawnIntervalDecay = 0.92; // multiplier each spawn
  static const int ballMaxCount = 20;

  // -- scoring ----------------------------------------------------------------
  static const int pointsPerSurvival = 5; // per ball dodge wave
  static const int pointsForWinning = 25;

  // -- countdown --------------------------------------------------------------
  static const double countdownSeconds = 3.0;

  // -- gesture thresholds -----------------------------------------------------
  static const double minMoveDistance = 0.8; // cm
  static const int tapMaxMs = 250;

  // -- joystick ---------------------------------------------------------------
  /// Full tilt: the distance from the anchor at which the player runs at
  /// [moveSpeed], and where the drawn knob stops following the finger. Pushing
  /// further still steers — it just cannot go faster or look more pushed.
  static const double joystickRadius = 1.65; // cm

  static const double joystickKnobRadius = 0.56; // cm

  /// Faint throughout: the stick sits under the finger, over a floor with
  /// balls crossing it, and it is feedback rather than furniture.
  static const int joystickWellAlpha = 24;
  static const int joystickRingAlpha = 70;
  static const int joystickDeadZoneAlpha = 45;
  static const int joystickKnobAlpha = 130;

  /// How hard the stick is pushed, from a finger [distance] out of the anchor:
  /// 0 inside the dead zone, 1 at [joystickRadius] and beyond.
  ///
  /// The ramp starts where the dead zone ends rather than at the anchor, so
  /// the first distance that moves a player at all moves them slowly. A jump
  /// straight to half speed the instant the dead zone is crossed is the thing
  /// that makes an analogue stick feel like a digital one.
  ///
  /// The dash ignores this: a dash is a fixed burst, and a nudged stick that
  /// dashed a short way would make the one escape in the game unreliable.
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
