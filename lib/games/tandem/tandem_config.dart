/// Tunables for Tandem.
class TandemConfig {
  const TandemConfig._();

  /// How long the table has to reach the target.
  static const double roundSeconds = 60;

  /// Synced taps needed to win the round.
  static const int targetSuccesses = 8;

  /// How long two lit screens stay lit before the attempt is missed.
  static const double windowSeconds = 1.1;

  /// Dark pause between one attempt and the next.
  static const double cooldownSeconds = 0.7;

  /// Before the very first light, so the table has a moment to look up.
  static const double initialDelaySeconds = 1.2;

  /// Points each half of a synced pair earns.
  static const int pointsPerSuccess = 10;

  /// How long the green (or red) flash lasts after a resolved attempt.
  static const double flashMs = 500;
}
