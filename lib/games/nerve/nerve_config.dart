/// Nerve's tunables, all in one place.
class NerveConfig {
  const NerveConfig._();

  /// How long the whole round lasts.
  static const double roundSeconds = 45;

  /// Where a turn's hidden burst point is drawn from. Never fixed, or holding
  /// would stop being a gamble and become counting.
  static const double minBurstSeconds = 2;
  static const double maxBurstSeconds = 6;

  /// A turn nobody starts is given up on after this — put the phone down and
  /// the table moves on without you, rather than stalling for everyone else.
  static const double startTimeoutSeconds = 3;

  /// The pause between one turn ending and the next one being dealt.
  static const double settleSeconds = 0.6;

  /// Points for every second banked before the burst.
  static const int pointsPerSecond = 10;

  /// How long the bank/burst wash lasts on the phone it happened to.
  static const double flashMs = 500;
}
