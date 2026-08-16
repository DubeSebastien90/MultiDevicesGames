/// Tunables for Highwire. Plain data, no SDK dependency.
class HighwireConfig {
  const HighwireConfig._();

  /// How long a full, uninterrupted crossing takes, scaled to whatever board
  /// width this table actually has.
  static const double crossingSeconds = 16;

  /// Backstop so a table that never finds a rhythm cannot run forever.
  static const double timeLimitSeconds = 60;

  /// Seconds of being left unsupported before the walker's balance runs out.
  static const double balanceDrainSeconds = 3.5;

  /// Seconds of being properly held before balance refills from empty.
  static const double balanceRegainSeconds = 1.5;

  static const double walkerRadius = 0.9;
  static const double wireThickness = 0.18;

  /// Split evenly across the table the moment the walker makes it across.
  static const int crossingBonus = 10;
}
