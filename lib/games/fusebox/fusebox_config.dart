/// Tunables for Fuse Box.
class FuseBoxConfig {
  const FuseBoxConfig._();

  /// A round, in seconds. Flat rather than scaled by board size — a bigger
  /// board gives the table more lights to fix, but also more hands able to fix
  /// them at once, and the two roughly cancel out on a real table.
  static const double roundSeconds = 60;

  /// Random toggles applied to the solved board to scramble it. Every toggle
  /// is its own inverse and they all commute, so however these are chosen the
  /// board stays solvable: pressing the same set of cells again, in any order,
  /// is guaranteed to return every light to off.
  static int scrambleMoves(int cellCount) => cellCount;

  /// Points every phone gets for going dark together. Awarded once, to
  /// everyone — nobody's tap counted more than anyone else's.
  static const int winBonus = 10;

  // ----------------------------------------------------------------- paint
  static const double cellSizeFraction = 0.68;
  static const int colorBackground = 0xFF15121C;
  static const int colorPlayfield = 0xFF201B2B;
  static const int colorCellOff = 0xFF2C2740;
  static const int colorCellOn = 0xFFFFC857;
  static const int colorCellRim = 0xFF433C5C;
}
