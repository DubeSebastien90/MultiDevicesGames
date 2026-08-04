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
